import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';
import '../../config.dart';
import '../../data/api_service.dart';
import '../../data/auth_state.dart';
import '../../data/contacts_service.dart';
import '../../data/p2p_room_service.dart';
import '../../wallet/services/wallet_access_proxy.dart';
import '../../wallet/services/wallet_service.dart';
import '../../wallet/state/app_state.dart';

/// Allowed URL prefixes for mini-app loading. Only HTTPS is allowed.
bool _isAllowedMiniAppUrl(String url) {
  try {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host == '127.0.0.1' || host == '0.0.0.0')
      return false;
    if (host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        host.startsWith('172.'))
      return false;
    if (host == '169.254.169.254') return false;
    return true;
  } catch (_) {
    return false;
  }
}

/// Allowed API path prefixes for mini-app requests.
const _allowedApiPathPrefixes = ['/api/miniapp/', '/api/me', '/api/stickers/'];

const _bridgeScript = '''
(function() {
  var _firstRun = !window.__najiBridgeReady;
  window.__najiBridgeReady = true;

  if (_firstRun) {
    window.__najiPending = {};
    window.__najiReqCounter = 0;
    window.__najiEventListeners = {};
    window.__najiGamepadState = [];
    window.__najiNativeGamepads = [];
  }

  var _pending = window.__najiPending;
  var _reqCounter = window.__najiReqCounter;
  var _eventListeners = window.__najiEventListeners;
  var _gamepadState = window.__najiGamepadState;
  var _nativeGamepads = window.__najiNativeGamepads;

  function _createReqId() {
    window.__najiReqCounter += 1;
    return 'req_' + Date.now() + '_' + window.__najiReqCounter;
  }

  function _toBridge(type, payload) {
    window.NajiBridge.postMessage(JSON.stringify({ type: type, payload: payload || {} }));
  }

  function _resolveReq(reqId, result) {
    var entry = _pending[reqId];
    if (!entry) return;
    delete _pending[reqId];
    if (entry.resolve) entry.resolve(result);
  }

  function _rejectReq(reqId, error) {
    var entry = _pending[reqId];
    if (!entry) return;
    delete _pending[reqId];
    if (entry.reject) entry.reject(new Error(error));
  }

  function _emitEvent(eventName, payload) {
    var handlers = _eventListeners[eventName];
    if (handlers) {
      for (var i = 0; i < handlers.length; i++) {
        try { handlers[i](payload); } catch(e) {}
      }
    }
  }

  function _normalizeNativeGamepad(raw) {
    if (!raw) return null;
    return {
      id: raw.id || '',
      index: raw.index || 0,
      connected: raw.connected !== false,
      timestamp: raw.timestamp || Date.now(),
      mapping: raw.mapping || 'standard',
      name: raw.name || 'Unknown Gamepad',
      axes: raw.axes || [],
      buttons: (raw.buttons || []).map(function(b) {
        if (typeof b === 'object') return b;
        return { pressed: b > 0.5, touched: false, value: b || 0 };
      })
    };
  }

  function _handleMessage(data) {
    if (!data || !data.type) return;
    if (data.type === 'NAJI_ASYNC_RESPONSE') {
      if (data.error) { _rejectReq(data.reqId, data.error); }
      else { _resolveReq(data.reqId, data.result); }
      return;
    }
    if (data.type === 'NAJI_EVENT') {
      if (data.eventName === 'gyroscopeChanged') {
        window.__najiGyroscopeData = data.payload;
      }
      if (data.eventName === 'accelerometerChanged') {
        window.__najiAccelerometerData = data.payload;
      }
      _emitEvent(data.eventName, data.payload);
      return;
    }
    if (data.type === 'NAJI_INIT_DATA') {
      window.__najiInitData = data;
      if (data.gyroscope) window.__najiGyroscopeData = data.gyroscope;
      if (data.accelerometer) window.__najiAccelerometerData = data.accelerometer;
      _emitEvent('init', data);
      _emitEvent('initDataChanged', data);
      _emitEvent('themeChanged', data.theme || 'light');
      _emitEvent('walletChanged', data.wallet || null);
      _emitEvent('orientationChanged', data.orientation || null);
      _emitEvent('multiplayerStateChanged', data.multiplayer || null);
      _emitEvent('voiceStateChanged', data.voice || null);
      _emitEvent('voiceParticipantsChanged', (data.voice && data.voice.participants) || []);
      var gp = data.gamepads || [];
      _gamepadState = gp.map(_normalizeNativeGamepad).filter(Boolean);
      _emitEvent('gamepadsChanged', { gamepads: _gamepadState, supported: Boolean(data.gamepadSupported), primary: _gamepadState[0] || null, reason: 'init' });
      return;
    }
    if (data.type === 'NAJI_WALLET_UPDATE') {
      if (window.__najiInitData) {
        window.__najiInitData.wallet = data.wallet || null;
      }
      _emitEvent('walletChanged', data.wallet || null);
      return;
    }
    if (data.type === 'NATIVE_GAMEPADS_UPDATE') {
      _nativeGamepads = data.gamepads || [];
      var gamepads = _nativeGamepads.map(_normalizeNativeGamepad).filter(Boolean);
      var prevIds = _gamepadState.map(function(g) { return g ? g.id : ''; });
      var currIds = gamepads.map(function(g) { return g.id; });
      for (var i = 0; i < gamepads.length; i++) {
        if (prevIds.indexOf(gamepads[i].id) === -1) {
          _emitEvent('gamepadConnected', { gamepad: gamepads[i], index: i });
        }
      }
      for (var j = 0; j < _gamepadState.length; j++) {
        if (_gamepadState[j] && currIds.indexOf(_gamepadState[j].id) === -1) {
          _emitEvent('gamepadDisconnected', { gamepad: _gamepadState[j], index: j });
        }
      }
      var changed = gamepads.length !== _gamepadState.length;
      if (!changed) {
        for (var k = 0; k < gamepads.length; k++) {
          if (JSON.stringify(gamepads[k]) !== JSON.stringify(_gamepadState[k])) { changed = true; break; }
        }
      }
      _gamepadState = gamepads;
      if (changed || gamepads.length > 0) {
        _emitEvent('gamepadsChanged', { gamepads: gamepads, supported: gamepads.length > 0, primary: gamepads[0] || null });
      }
      return;
    }
  }

  window.__najiHandleMessage = function(data) {
    _handleMessage(data);
    if (window.__najiOrigPostMessage) {
      try { window.__najiOrigPostMessage(data, '*'); } catch(e) {}
    }
  };

  if (_firstRun) {
    window.__najiOrigPostMessage = window.postMessage.bind(window);
    window.postMessage = function(data, origin) {
      if (data && typeof data === 'object' && data.type && window.NajiBridge) {
        window.NajiBridge.postMessage(JSON.stringify(data));
        return;
      }
      window.__najiOrigPostMessage(data, origin);
    };
  }

  function _on(name, handler) {
    if (!_eventListeners[name]) _eventListeners[name] = [];
    _eventListeners[name].push(handler);
    return function() {
      if (_eventListeners[name]) {
        _eventListeners[name] = _eventListeners[name].filter(function(h) { return h !== handler; });
      }
    };
  }

  function _off(name, handler) {
    if (!name) { _eventListeners = {}; return; }
    if (!handler) { _eventListeners[name] = []; return; }
    if (_eventListeners[name]) {
      _eventListeners[name] = _eventListeners[name].filter(function(h) { return h !== handler; });
    }
  }

  function _makeReq(type, payload) {
    return new Promise(function(resolve, reject) {
      var reqId = _createReqId();
      _pending[reqId] = { resolve: resolve, reject: reject };
      _toBridge(type, Object.assign({}, payload || {}, { reqId: reqId }));
      setTimeout(function() {
        if (_pending[reqId]) {
          delete _pending[reqId];
          reject(new Error('Request timeout'));
        }
      }, 15000);
    });
  }

  var sdk = {
    init: function() {
      if (window.__najiInitData) return Promise.resolve(window.__najiInitData);
      return _makeReq('NAJI_SDK_INIT');
    },
    ready: function() { _toBridge('APP_READY', {}); },
    close: function() { _toBridge('NAJI_CLOSE_APP', {}); },
    expand: function() { _toBridge('SET_FULLSCREEN_APP', { value: true }); },
    collapse: function() { _toBridge('SET_FULLSCREEN_APP', { value: false }); },
    setHeaderColor: function(color) { _toBridge('SET_HEADER_COLOR', { color: color }); },
    requestContext: function() {
      return _makeReq('GET_CONTEXT').then(function(ctx) {
        if (ctx && typeof ctx === 'object') {
          window.__najiInitData = Object.assign({}, window.__najiInitData || {}, ctx);
          if (Array.isArray(ctx.gamepads)) {
            _nativeGamepads = ctx.gamepads;
            _gamepadState = ctx.gamepads.map(_normalizeNativeGamepad).filter(Boolean);
          }
        }
        return ctx;
      });
    },
    ping: function() { return _makeReq('NAJI_SDK_PING'); },
    on: _on,
    off: _off,
    get initData() { return window.__najiInitData || null; },
    get user() { var d = window.__najiInitData; return d && d.user ? d.user : null; },
    get theme() { var d = window.__najiInitData; return d && d.theme ? d.theme : 'light'; },
    get platform() { var d = window.__najiInitData; return d && d.platform ? d.platform : 'android'; },
    get parentOrigin() { return null; },
    get permissions() { return {}; },
    get sparks() { var d = window.__najiInitData; return d && d.sparks ? d.sparks : { balance: 0 }; },
    get gamepads() { return _gamepadState; },
    get gamepadSupported() { var d = window.__najiInitData; return d && d.gamepadSupported ? d.gamepadSupported : _gamepadState.length > 0; },
    get startParams() { var d = window.__najiInitData; return d && d.startParams ? d.startParams : null; },
    get orientation() { var d = window.__najiInitData; return d && d.orientation ? d.orientation : null; },
    get multiplayer() { var d = window.__najiInitData; return d && d.multiplayer ? d.multiplayer : null; },
    get voice() { var d = window.__najiInitData; return d && d.voice ? d.voice : null; },
    backButton: {
      show: function() { _toBridge('BACK_BUTTON_UPDATE', { visible: true }); },
      hide: function() { _toBridge('BACK_BUTTON_UPDATE', { visible: false }); },
      onClick: function(handler) { return sdk.on('backButtonClicked', handler); }
    },
    storage: {
      get: function(key) { return _makeReq('STORAGE_GET', { key: key }); },
      set: function(key, value) { return _makeReq('STORAGE_SET', { key: key, value: value }); },
      remove: function(key) { return _makeReq('STORAGE_REMOVE', { key: key }); },
      keys: function() { return _makeReq('STORAGE_KEYS'); }
    },
    api: {
      request: function(path, opts) {
        var o = opts || {};
        return _makeReq('API_REQUEST', { path: path, method: o.method || 'GET', headers: o.headers || {}, body: o.body || null });
      }
    },
    contacts: {
      list: function() { return _makeReq('MINIAPP_CONTACTS_GET').then(function(x) { return Array.isArray(x) ? x : []; }); },
      get: function() { return this.list(); },
      share: function(o) { return _makeReq('MINIAPP_SHARE_TO_CONTACT', o || {}); },
      invite: function(o) { return _makeReq('MINIAPP_CONTACT_INVITE', o || {}); },
      inviteRoom: function(o) { return _makeReq('MINIAPP_CONTACT_INVITE', Object.assign({ intent: 'room_invite' }, o || {})); }
    },
    ui: {
      alert: function(msg) { _toBridge('SHOW_ALERT', { message: msg }); },
      toast: function(msg, t) { return _makeReq('SHOW_TOAST', { message: msg, type: t || 'info' }); },
      openLink: function(url) { return _makeReq('OPEN_LINK', { url: url }); },
      copy: function(text) { return _makeReq('CLIPBOARD_WRITE', { text: text }); }
    },
    wallet: {
      getState: function() { return _makeReq('GET_CONTEXT').then(function(ctx) { return ctx ? ctx.wallet : null; }); },
      // Full wallet info (alias of getState for discoverability).
      getInfo: function() { return this.getState(); },
      refresh: function() { _toBridge('NAJI_WALLET_STATE_REQUEST', {}); },
      // Opens the host wallet connect flow; resolves with {address, ...} or null.
      view: function(o) { return _makeReq('NAJI_WALLET_VIEW', o || {}); },
      getBinding: function() { return _makeReq('MINIAPP_WALLET_GET_BINDING'); },
      // Just the public address string, or null when no wallet is connected.
      getAddress: function() {
        return _makeReq('MINIAPP_WALLET_GET_ADDRESS').then(function(b) {
          return b && b.publicKey ? b.publicKey : null;
        });
      },
      onChange: function(handler) { return sdk.on('walletChanged', handler); },
      signMessage: function(o) { return _makeReq('MINIAPP_WALLET_SIGN_MESSAGE', o || {}); },
      signTransaction: function(o) { return _makeReq('MINIAPP_WALLET_SIGN_TRANSACTION', o || {}); },
      signAndSendTransaction: function(o) { return _makeReq('MINIAPP_WALLET_SIGN_AND_SEND', o || {}); }
    },
    gamepad: {
      get supported() { var d = window.__najiInitData; return d && d.gamepadSupported ? true : _gamepadState.length > 0; },
      get state() { return _gamepadState; },
      get primary() { return _gamepadState[0] || null; },
      getState: function() {
        return _makeReq('GET_GAMEPADS').then(function(gamepads) {
          var prev = _gamepadState;
          _gamepadState = (gamepads || []).map(_normalizeNativeGamepad).filter(Boolean);
          var changed = _gamepadState.length !== prev.length;
          if (!changed) {
            for (var k = 0; k < _gamepadState.length; k++) {
              if (JSON.stringify(_gamepadState[k]) !== JSON.stringify(prev[k])) { changed = true; break; }
            }
          }
          if (changed) {
            _emitEvent('gamepadsChanged', { gamepads: _gamepadState, supported: _gamepadState.length > 0, primary: _gamepadState[0] || null });
          }
          return _gamepadState;
        });
      },
      refresh: function() { return this.getState(); },
      onChange: function(handler) { return sdk.on('gamepadsChanged', handler); },
      onConnect: function(handler) { return sdk.on('gamepadConnected', handler); },
      onDisconnect: function(handler) { return sdk.on('gamepadDisconnected', handler); }
    },
    orientation: {
      get state() { var d = window.__najiInitData; return d && d.orientation ? d.orientation : null; },
      getState: function() { return _makeReq('GET_ORIENTATION'); },
      refresh: function() { return this.getState(); },
      onChange: function(handler) { return sdk.on('orientationChanged', handler); }
    },
    multiplayer: {
      get state() { var d = window.__najiInitData; return d && d.multiplayer ? d.multiplayer : null; },
      get currentRoom() { var s = this.state; return s && s.room ? s.room : null; },
      get queue() { var s = this.state; return s && s.queue ? s.queue : null; },
      getState: function() { return _makeReq('MINIAPP_MULTIPLAYER_GET_STATE'); },
      createRoom: function(o) { return _makeReq('MINIAPP_MULTIPLAYER_CREATE_ROOM', o || {}); },
      joinRoom: function(o) { return _makeReq('MINIAPP_MULTIPLAYER_JOIN_ROOM', o || {}); },
      leaveRoom: function(o) { return _makeReq('MINIAPP_MULTIPLAYER_LEAVE_ROOM', o || {}); },
      joinMatchmaking: function(o) { return _makeReq('MINIAPP_MULTIPLAYER_JOIN_MATCHMAKING', o || {}); },
      leaveMatchmaking: function(o) { return _makeReq('MINIAPP_MULTIPLAYER_LEAVE_MATCHMAKING', o || {}); },
      updateState: function(state, o) { return _makeReq('MINIAPP_MULTIPLAYER_UPDATE_STATE', Object.assign({ state: state || {} }, o || {})); },
      send: function(evt, payload, o) {
        var opts = o || {};
        if (opts.transient || opts.noAck || opts.fireAndForget) {
          _toBridge('MINIAPP_MULTIPLAYER_SEND_EVENT_FAST', Object.assign({ eventName: evt, payload: payload || {} }, opts));
          return Promise.resolve({ ok: true, transient: true, ts: Date.now() });
        }
        return _makeReq('MINIAPP_MULTIPLAYER_SEND_EVENT', Object.assign({ eventName: evt, payload: payload || {} }, opts));
      },
      onChange: function(handler) { return sdk.on('multiplayerStateChanged', handler); },
      onMatchFound: function(handler) { return sdk.on('multiplayerMatchFound', handler); },
      onEvent: function(handler) { return sdk.on('multiplayerEvent', handler); }
    },
    voice: {
      get state() { var d = window.__najiInitData; return d && d.voice ? d.voice : null; },
      get participants() { var s = this.state; return s && s.participants ? s.participants : []; },
      getState: function() { return _makeReq('MINIAPP_VOICE_GET_STATE'); },
      join: function(o) { return _makeReq('MINIAPP_VOICE_JOIN', o || {}); },
      leave: function() { return _makeReq('MINIAPP_VOICE_LEAVE'); },
      setMuted: function(m) { return _makeReq('MINIAPP_VOICE_SET_MUTED', { muted: !!m }); },
      toggleMuted: function() {
        var s = this.state;
        var nextMuted = !(s && s.muted);
        return this.setMuted(nextMuted);
      },
      onChange: function(handler) { return sdk.on('voiceStateChanged', handler); },
      onParticipantsChange: function(handler) { return sdk.on('voiceParticipantsChanged', handler); },
      onParticipantJoined: function(handler) { return sdk.on('voiceParticipantJoined', handler); },
      onParticipantLeft: function(handler) { return sdk.on('voiceParticipantLeft', handler); }
    },
    gyroscope: {
      get state() { return window.__najiGyroscopeData || null; },
      getState: function() { return _makeReq('GYROSCOPE_GET_STATE'); },
      start: function() { _toBridge('GYROSCOPE_START', {}); },
      stop: function() { _toBridge('GYROSCOPE_STOP', {}); },
      onChange: function(handler) { return sdk.on('gyroscopeChanged', handler); }
    },
    accelerometer: {
      get state() { return window.__najiAccelerometerData || null; },
      getState: function() { return _makeReq('ACCELEROMETER_GET_STATE'); },
      start: function() { _toBridge('ACCELEROMETER_START', {}); },
      stop: function() { _toBridge('ACCELEROMETER_STOP', {}); },
      onChange: function(handler) { return sdk.on('accelerometerChanged', handler); }
    },
    vibrator: {
      vibrate: function(duration) { _toBridge('VIBRATE', { duration: duration || 200 }); }
    },
    nfc: {
      isAvailable: function() { return _makeReq('NFC_IS_AVAILABLE').then(function(r) { return r && r.available; }); },
      isEnabled: function() { return _makeReq('NFC_IS_ENABLED').then(function(r) { return r && r.enabled; }); },
      read: function() { return _makeReq('NFC_READ'); },
      write: function(records) { return _makeReq('NFC_WRITE', { records: records || [] }); },
      sharePayload: function(text) { return _makeReq('NFC_SHARE_PAYLOAD', { text: text || '' }); },
      stopShare: function() { _toBridge('NFC_STOP_SHARE', {}); },
      cancel: function() { _toBridge('NFC_CANCEL', {}); },
      connectIsoDep: function() { return _makeReq('NFC_CONNECT_ISODEP'); },
      transceive: function(command) { return _makeReq('NFC_TRANSCEIVE', { command: command || '' }); },
      disconnect: function() { _toBridge('NFC_DISCONNECT_ISODEP', {}); },
      onTagRead: function(handler) { return sdk.on('nfcTagRead', handler); }
    },
    bluetooth: {
      startScan: function(options) { return _makeReq('BLUETOOTH_START_SCAN', options || {}); },
      stopScan: function() { _toBridge('BLUETOOTH_STOP_SCAN', {}); },
      connect: function(deviceId, options) { return _makeReq('BLUETOOTH_CONNECT', Object.assign({ deviceId: deviceId }, options || {})); },
      sendRaw: function(deviceId, data) { return _makeReq('BLUETOOTH_SEND_RAW', { deviceId: deviceId, data: data }); },
      discoverServices: function(deviceId) { return _makeReq('BLUETOOTH_DISCOVER_SERVICES', { deviceId: deviceId }); },
      subscribe: function(deviceId, serviceUuid, characteristicUuid) {
        return _makeReq('BLUETOOTH_SUBSCRIBE', { deviceId: deviceId, serviceUuid: serviceUuid, characteristicUuid: characteristicUuid });
      },
      unsubscribe: function(deviceId, serviceUuid, characteristicUuid) {
        return _makeReq('BLUETOOTH_UNSUBSCRIBE', { deviceId: deviceId, serviceUuid: serviceUuid, characteristicUuid: characteristicUuid });
      },
      readRaw: function(deviceId, serviceUuid, characteristicUuid) {
        return _makeReq('BLUETOOTH_READ_RAW', { deviceId: deviceId, serviceUuid: serviceUuid, characteristicUuid: characteristicUuid });
      },
      onDeviceFound: function(handler) { return sdk.on('bluetoothDeviceFound', handler); },
      onDataReceived: function(handler) { return sdk.on('bluetoothDataReceived', handler); },
      onData: function(handler) { return sdk.on('bluetoothDataReceived', handler); },
      onConnectionStateChanged: function(handler) { return sdk.on('bluetoothConnectionStateChanged', handler); }
    },
    camera: {
      takePhoto: function() { return _makeReq('CAMERA_TAKE_PHOTO'); },
      getUserMedia: function(constraints) {
        return navigator.mediaDevices.getUserMedia(constraints || { video: true });
      }
    },
    payments: {
      invoice: function(o) { return _makeReq('CREATE_INVOICE_SPARKS', o || {}); },
      solana: function(o) { return _makeReq('MINIAPP_SOLANA_PAYMENT', o || {}); },
      requestPayment: function(options) {
        var o = options || {};
        var amount = Number(o.amount);
        var recipient = String(o.recipient || o.address || '').trim();
        if (!isFinite(amount) || amount <= 0) {
          return Promise.reject(new Error('payments.requestPayment: amount must be > 0'));
        }
        if (!recipient) {
          return Promise.reject(new Error('payments.requestPayment: recipient is required'));
        }
        return _makeReq('MINIAPP_SOLANA_PAYMENT', Object.assign({
          amount: amount,
          recipient: recipient,
          symbol: String(o.currency || o.symbol || 'SOL').toUpperCase(),
          label: o.label || o.memo || o.title || ''
        }, o));
      }
    }
  };

  var target = window.NajiMiniApp || {};
  var sdkNames = Object.getOwnPropertyNames(sdk);
  for (var i = 0; i < sdkNames.length; i++) {
    var desc = Object.getOwnPropertyDescriptor(sdk, sdkNames[i]);
    if (desc) {
      try { Object.defineProperty(target, sdkNames[i], desc); } catch(e) {}
    }
  }
  window.NajiMiniApp = target;
})();
''';

const _windowsBridgeShim = '''
(function() {
  if (!window.NajiBridge) {
    window.NajiBridge = {
      postMessage: function(msg) {
        window.chrome.webview.postMessage(msg);
      }
    };
  }
})();
''';

class MiniAppScreen extends StatefulWidget {
  final String url;
  final String title;

  const MiniAppScreen({super.key, required this.url, this.title = 'Mini App'});

  @override
  State<MiniAppScreen> createState() => _MiniAppScreenState();
}

class _MiniAppScreenState extends State<MiniAppScreen> {
  MethodChannel? _webviewChannel;
  WebViewController? _webViewController;
  WebviewController? _windowsController;
  bool _loading = true;
  String? _error;
  Color _headerColor = Colors.transparent;
  bool _fullscreen = false;
  bool _backButtonVisible = false;

  bool get _useAndroidView =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _useWindowsNativeWebView =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  bool get _useFlutterWebView =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _useFallback =>
      !kIsWeb &&
      !_useAndroidView &&
      !_useWindowsNativeWebView &&
      !_useFlutterWebView;

  static const _gamepadChannel = MethodChannel(
    'com.naji.najimessenger/gamepads',
  );
  static const _gyroscopeChannel = MethodChannel(
    'com.naji.najimessenger/gyroscope',
  );
  static const _accelerometerChannel = MethodChannel(
    'com.naji.najimessenger/accelerometer',
  );
  static const _vibratorChannel = MethodChannel(
    'com.naji.najimessenger/vibrator',
  );
  static const _nfcChannel = MethodChannel('com.naji.najimessenger/nfc');
  static const _cameraChannel = MethodChannel('com.naji.najimessenger/camera');
  static const _bluetoothChannel = MethodChannel(
    'com.naji.najimessenger/bluetooth',
  );
  List<Map<String, dynamic>> _nativeGamepads = [];
  Map<String, dynamic>? _lastGyroscopeData;
  Map<String, dynamic>? _lastAccelerometerData;
  String? _nfcPendingReqId;

  @override
  void initState() {
    super.initState();
    _setupNativeGamepadListener();
    _setupNativeGyroscopeListener();
    _setupNativeAccelerometerListener();
    _setupNativeNfcListener();
    _setupNativeBluetoothListener();
    if (_useFlutterWebView) {
      _initFlutterWebView();
    }
    if (_useWindowsNativeWebView) {
      _initWindowsWebView();
    }
    P2PRoomService.instance.onChanged = _onP2pChanged;
    P2PRoomService.instance.onEvent = _onP2pEvent;
  }

  Future<void> _initFlutterWebView() async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'NajiBridge',
        onMessageReceived: (m) => _onJsMessage(m.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
            _runJs(_bridgeScript);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
            _runJs(_bridgeScript);
            _autoInitSdk();
            _refreshGamepads();
            Future.delayed(const Duration(seconds: 1), _refreshGamepads);
            Future.delayed(const Duration(seconds: 3), _refreshGamepads);
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _error = 'Failed to load: ${error.description}';
                _loading = false;
              });
            }
          },
        ),
      );
    try {
      if (!_isAllowedMiniAppUrl(widget.url)) {
        if (mounted) {
          setState(() {
            _error =
                'URL not allowed: only HTTPS URLs from trusted hosts are permitted';
            _loading = false;
          });
        }
        return;
      }
      await controller.loadRequest(Uri.parse(widget.url));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load ${widget.url}';
          _loading = false;
        });
      }
    }
    _webViewController = controller;
  }

  Future<void> _initWindowsWebView() async {
    final controller = WebviewController();
    controller.loadingState.listen((state) {
      if (state == LoadingState.loading) {
        if (mounted) setState(() => _loading = true);
      } else if (state == LoadingState.navigationCompleted) {
        if (mounted) setState(() => _loading = false);
        _runJs(_bridgeScript);
        _autoInitSdk();
        _refreshGamepads();
        Future.delayed(const Duration(seconds: 1), _refreshGamepads);
        Future.delayed(const Duration(seconds: 3), _refreshGamepads);
      }
    });
    controller.onLoadError.listen((status) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load: $status';
          _loading = false;
        });
      }
    });
    controller.webMessage.listen((message) {
      if (message is String) {
        _onJsMessage(message);
      } else if (message is Map) {
        _onJsMessage(jsonEncode(message));
      }
    });
    try {
      if (!_isAllowedMiniAppUrl(widget.url)) {
        if (mounted) {
          setState(() {
            _error =
                'URL not allowed: only HTTPS URLs from trusted hosts are permitted';
            _loading = false;
          });
        }
        return;
      }
      await controller.initialize();
      await controller.addScriptToExecuteOnDocumentCreated(_windowsBridgeShim);
      await controller.addScriptToExecuteOnDocumentCreated(_bridgeScript);
      await controller.loadUrl(widget.url);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load ${widget.url}: $e';
          _loading = false;
        });
      }
    }
    _windowsController = controller;
  }

  void _onPlatformViewCreated(int id) {
    _webviewChannel = MethodChannel('naji_webview_$id');
    _webviewChannel!.setMethodCallHandler(_handleNativeCallback);
    if (!_isAllowedMiniAppUrl(widget.url)) {
      if (mounted) {
        setState(() {
          _error =
              'URL not allowed: only HTTPS URLs from trusted hosts are permitted';
          _loading = false;
        });
      }
      return;
    }
    _webviewChannel!.invokeMethod('loadUrl', {'url': widget.url});
  }

  Future<void> _handleNativeCallback(MethodCall call) async {
    switch (call.method) {
      case 'onJsMessage':
        final msg = call.arguments as String;
        _onJsMessage(msg);
        break;
      case 'onPageStarted':
        if (mounted) setState(() => _loading = true);
        _runJs(_bridgeScript);
        break;
      case 'onPageFinished':
        if (mounted) setState(() => _loading = false);
        _runJs(_bridgeScript);
        _autoInitSdk();
        _refreshGamepads();
        Future.delayed(const Duration(seconds: 1), _refreshGamepads);
        Future.delayed(const Duration(seconds: 3), _refreshGamepads);
        break;
      case 'onWebResourceError':
        if (mounted) {
          setState(() {
            _error = 'Failed to load: ${call.arguments}';
            _loading = false;
          });
        }
        break;
    }
  }

  void _onJsMessage(String msg) {
    final data = jsonDecode(msg) as Map<String, dynamic>;
    final type = data['type'] as String? ?? '';
    final payload = data['payload'] as Map<String, dynamic>? ?? {};

    switch (type) {
      case 'NAJI_SDK_INIT':
        _handleSdkInit(payload);
        break;
      case 'APP_READY':
        break;
      case 'NAJI_CLOSE_APP':
        _handleClose();
        break;
      case 'SET_FULLSCREEN_APP':
        _handleFullscreen(payload);
        break;
      case 'SET_HEADER_COLOR':
        _handleHeaderColor(payload);
        break;
      case 'BACK_BUTTON_UPDATE':
        _handleBackButton(payload);
        break;
      case 'STORAGE_GET':
        _handleStorageGet(payload);
        break;
      case 'STORAGE_SET':
        _handleStorageSet(payload);
        break;
      case 'STORAGE_REMOVE':
        _handleStorageRemove(payload);
        break;
      case 'STORAGE_KEYS':
        _handleStorageKeys(payload);
        break;
      case 'API_REQUEST':
        _handleApiRequest(payload);
        break;
      case 'SHOW_ALERT':
        _handleAlert(payload);
        break;
      case 'SHOW_TOAST':
        _handleToast(payload);
        break;
      case 'OPEN_LINK':
        _handleOpenLink(payload);
        break;
      case 'CLIPBOARD_WRITE':
        _handleClipboardWrite(payload);
        break;
      case 'GET_CONTEXT':
        _handleGetContext(payload);
        break;
      case 'GET_GAMEPADS':
        _handleGetGamepads(payload);
        break;
      case 'GET_ORIENTATION':
        _handleGetOrientation(payload);
        break;
      case 'NAJI_SDK_PING':
        _respond(payload, 'pong');
        break;
      case 'NATIVE_GAMEPADS_REQUEST':
        _handleNativeGamepadsRequest(payload);
        break;
      case 'NAJI_WALLET_STATE_REQUEST':
        _handleWalletState(payload);
        break;
      case 'NAJI_WALLET_VIEW':
        _handleWalletView(payload);
        break;
      case 'MINIAPP_SOLANA_PAYMENT':
        _handleSolanaPayment(payload);
        break;
      case 'CREATE_INVOICE_SPARKS':
        _respondError(
          payload,
          'This payment method is not available on this platform',
        );
        break;
      case 'MINIAPP_WALLET_GET_BINDING':
        _handleWalletGetBinding(payload);
        break;
      case 'MINIAPP_WALLET_GET_ADDRESS':
        _handleWalletGetAddress(payload);
        break;
      case 'MINIAPP_WALLET_SIGN_MESSAGE':
        _handleWalletSignMessage(payload);
        break;
      case 'MINIAPP_WALLET_SIGN_TRANSACTION':
        _handleWalletSignTransaction(payload);
        break;
      case 'MINIAPP_WALLET_SIGN_AND_SEND':
        _handleWalletSignAndSend(payload);
        break;
      case 'MINIAPP_CONTACTS_GET':
      case 'MINIAPP_SHARE_TO_CONTACT':
      case 'MINIAPP_CONTACT_INVITE':
        _handleContacts(type, payload);
        break;
      case 'MINIAPP_MULTIPLAYER_CREATE_ROOM':
      case 'MINIAPP_MULTIPLAYER_JOIN_ROOM':
      case 'MINIAPP_MULTIPLAYER_LEAVE_ROOM':
      case 'MINIAPP_MULTIPLAYER_GET_STATE':
      case 'MINIAPP_MULTIPLAYER_JOIN_MATCHMAKING':
      case 'MINIAPP_MULTIPLAYER_LEAVE_MATCHMAKING':
      case 'MINIAPP_MULTIPLAYER_UPDATE_STATE':
      case 'MINIAPP_MULTIPLAYER_SEND_EVENT':
      case 'MINIAPP_MULTIPLAYER_SEND_EVENT_FAST':
        _handleMultiplayer(type, payload);
        break;
      case 'MINIAPP_VOICE_GET_STATE':
      case 'MINIAPP_VOICE_JOIN':
      case 'MINIAPP_VOICE_LEAVE':
      case 'MINIAPP_VOICE_SET_MUTED':
        _handleVoice(type, payload);
        break;
      case 'GYROSCOPE_GET_STATE':
        _handleGyroscopeGetState(payload);
        break;
      case 'GYROSCOPE_START':
        _handleGyroscopeStart(payload);
        break;
      case 'GYROSCOPE_STOP':
        _handleGyroscopeStop(payload);
        break;
      case 'ACCELEROMETER_GET_STATE':
        _handleAccelerometerGetState(payload);
        break;
      case 'ACCELEROMETER_START':
        _handleAccelerometerStart(payload);
        break;
      case 'ACCELEROMETER_STOP':
        _handleAccelerometerStop(payload);
        break;
      case 'VIBRATE':
        _handleVibrate(payload);
        break;
      case 'NFC_IS_AVAILABLE':
        _handleNfcIsAvailable(payload);
        break;
      case 'NFC_IS_ENABLED':
        _handleNfcIsEnabled(payload);
        break;
      case 'NFC_READ':
        _handleNfcRead(payload);
        break;
      case 'NFC_WRITE':
        _handleNfcWrite(payload);
        break;
      case 'NFC_SHARE_PAYLOAD':
        _handleNfcSharePayload(payload);
        break;
      case 'NFC_STOP_SHARE':
        _handleNfcStopShare(payload);
        break;
      case 'NFC_CANCEL':
        _handleNfcCancel(payload);
        break;
      case 'NFC_CONNECT_ISODEP':
        _handleNfcConnectIsoDep(payload);
        break;
      case 'NFC_TRANSCEIVE':
        _handleNfcTransceive(payload);
        break;
      case 'NFC_DISCONNECT_ISODEP':
        _handleNfcDisconnectIsoDep(payload);
        break;
      case 'CAMERA_TAKE_PHOTO':
        _handleCameraTakePhoto(payload);
        break;
      case 'BLUETOOTH_START_SCAN':
        _handleBluetoothStartScan(payload);
        break;
      case 'BLUETOOTH_STOP_SCAN':
        _handleBluetoothStopScan(payload);
        break;
      case 'BLUETOOTH_CONNECT':
        _handleBluetoothConnect(payload);
        break;
      case 'BLUETOOTH_SEND_RAW':
        _handleBluetoothSendRaw(payload);
        break;
      case 'BLUETOOTH_DISCOVER_SERVICES':
        _handleBluetoothDiscoverServices(payload);
        break;
      case 'BLUETOOTH_SUBSCRIBE':
        _handleBluetoothSubscribe(payload);
        break;
      case 'BLUETOOTH_UNSUBSCRIBE':
        _handleBluetoothUnsubscribe(payload);
        break;
      case 'BLUETOOTH_READ_RAW':
        _handleBluetoothReadRaw(payload);
        break;
    }
  }

  // ── SDK Init ──────────────────────────────────────────────────────

  Future<void> _autoInitSdk() async {
    try {
      final user = await _getUser();
      final brightness = MediaQuery.platformBrightnessOf(context);
      final isDark = brightness == Brightness.dark;
      final platform = _getPlatform();
      final wallet = await _resolveWalletContext();

      try {
        final result = await _gamepadChannel.invokeMethod<List>('getGamepads');
        _nativeGamepads = (result ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {}
      final hasGamepads = _nativeGamepads.isNotEmpty;

      final initData = {
        'user': user,
        'theme': isDark ? 'dark' : 'light',
        'platform': platform,
        'permissions': {},
        'sparks': wallet ?? {'balance': 0},
        'wallet': wallet,
        'gamepadSupported': hasGamepads,
        'gamepads': _nativeGamepads,
        'orientation': await _getOrientationState(),
        'multiplayer': P2PRoomService.instance.multiplayerState,
        'voice': P2PRoomService.instance.voiceState,
        'startParams': null,
        'launchParams': null,
      };

      _sendToWeb('NAJI_INIT_DATA', initData);
    } catch (e) {
      _sendToWeb('NAJI_INIT_DATA', _fallbackInitData());
    }
  }

  Map<String, dynamic> _fallbackInitData() {
    return {
      'user': {
        'id': 'anonymous',
        'name': 'User',
        'username': '',
        'avatar': '',
        'is_premium': false,
      },
      'theme': 'light',
      'platform': _getPlatform(),
      'permissions': {},
      'sparks': {'balance': 0},
      'wallet': null,
      'gamepadSupported': false,
      'gamepads': <Map<String, dynamic>>[],
      'orientation': {'orientation': 'portrait', 'angle': 0},
      'multiplayer': null,
      'voice': null,
      'startParams': null,
      'launchParams': null,
    };
  }

  Future<void> _handleSdkInit(Map<String, dynamic> payload) async {
    Map<String, dynamic> initData;
    try {
      final user = await _getUser();
      final brightness = MediaQuery.platformBrightnessOf(context);
      final isDark = brightness == Brightness.dark;
      final platform = _getPlatform();
      final wallet = await _resolveWalletContext();

      try {
        final result = await _gamepadChannel.invokeMethod<List>('getGamepads');
        _nativeGamepads = (result ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {}
      final hasGamepads = _nativeGamepads.isNotEmpty;

      initData = {
        'user': user,
        'theme': isDark ? 'dark' : 'light',
        'platform': platform,
        'permissions': {},
        'sparks': wallet ?? {'balance': 0},
        'wallet': wallet,
        'gamepadSupported': hasGamepads,
        'gamepads': _nativeGamepads,
        'orientation': await _getOrientationState(),
        'multiplayer': null,
        'voice': null,
        'startParams': null,
        'launchParams': null,
      };
    } catch (e) {
      initData = _fallbackInitData();
    }

    final json = jsonEncode(initData);
    final b64 = base64Encode(utf8.encode(json));
    _runJs("window.__najiInitData = JSON.parse(atob('$b64'));");
    _sendToWeb('NAJI_INIT_DATA', initData);
    _respond(payload, initData);
  }

  Future<Map<String, dynamic>> _getUser() async {
    final auth = AuthState.instance;
    return {
      'id': auth.username ?? 'anonymous',
      'name': auth.displayName ?? auth.username ?? 'User',
      'username': auth.username ?? '',
      'avatar': auth.avatarUrl ?? '',
      'is_premium': false,
    };
  }

  String _getPlatform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      default:
        return 'web';
    }
  }

  // ── Close ─────────────────────────────────────────────────────────

  void _handleClose() {
    if (mounted) Navigator.of(context).pop();
  }

  // ── Fullscreen ────────────────────────────────────────────────────

  void _handleFullscreen(Map<String, dynamic> payload) {
    final value = payload['value'] as bool? ?? false;
    setState(() => _fullscreen = value);
    if (value) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  // ── Header Color ──────────────────────────────────────────────────

  void _handleHeaderColor(Map<String, dynamic> payload) {
    final colorStr = payload['color'] as String? ?? '';
    if (colorStr.isEmpty) {
      setState(() => _headerColor = Colors.transparent);
      return;
    }
    final color = _parseColor(colorStr);
    if (color != null) {
      setState(() => _headerColor = color);
    }
  }

  Color? _parseColor(String input) {
    var hex = input.replaceFirst('#', '').trim();
    if (hex.isEmpty) return null;
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length == 8) {
      return Color(int.tryParse(hex, radix: 16) ?? 0);
    }
    return null;
  }

  // ── Back Button ───────────────────────────────────────────────────

  void _handleBackButton(Map<String, dynamic> payload) {
    setState(() => _backButtonVisible = payload['visible'] as bool? ?? false);
  }

  // ── Storage ───────────────────────────────────────────────────────

  Future<void> _handleStorageGet(Map<String, dynamic> payload) async {
    final key = payload['key'] as String? ?? '';
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('miniapp_$key');
    _respond(payload, value);
  }

  Future<void> _handleStorageSet(Map<String, dynamic> payload) async {
    final key = payload['key'] as String? ?? '';
    final value = payload['value'] as String? ?? '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('miniapp_$key', value);
    _respond(payload, true);
  }

  Future<void> _handleStorageRemove(Map<String, dynamic> payload) async {
    final key = payload['key'] as String? ?? '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('miniapp_$key');
    _respond(payload, true);
  }

  Future<void> _handleStorageKeys(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((k) => k.startsWith('miniapp_'))
        .map((k) => k.substring(8))
        .toList();
    _respond(payload, keys);
  }

  // ── API Request ───────────────────────────────────────────────────

  Future<void> _handleApiRequest(Map<String, dynamic> payload) async {
    final path = payload['path'] as String? ?? '/';
    if (!_allowedApiPathPrefixes.any((prefix) => path.startsWith(prefix))) {
      _respondError(payload, 'API path not allowed');
      return;
    }
    final method = (payload['method'] as String? ?? 'GET').toUpperCase();
    final headers = (payload['headers'] as Map<String, dynamic>?) ?? {};

    try {
      final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
      final requestHeaders = <String, String>{
        'Content-Type': 'application/json',
        if (ApiService.accessToken != null)
          'Authorization': 'Bearer ${ApiService.accessToken}',
        ...headers.map((k, v) => MapEntry(k, v.toString())),
      };

      final client = ApiService.client;
      var request = http.Request(method, uri);
      request.headers.addAll(requestHeaders);

      if (payload['body'] != null) {
        final bodyData = payload['body'];
        if (bodyData is Map) {
          request.body = jsonEncode(bodyData);
        }
      }

      final response = await client.send(request);
      final bodyStr = await response.stream.bytesToString();

      dynamic body;
      try {
        body = jsonDecode(bodyStr);
      } catch (_) {
        body = bodyStr;
      }

      _respond(payload, {'status': response.statusCode, 'body': body});
    } catch (e) {
      _respondError(payload, e.toString());
    }
  }

  // ── UI ────────────────────────────────────────────────────────────

  void _handleAlert(Map<String, dynamic> payload) {
    final message = payload['message'] as String? ?? '';
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleToast(Map<String, dynamic> payload) async {
    final message = payload['message'] as String? ?? '';
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    _respond(payload, true);
  }

  Future<void> _handleOpenLink(Map<String, dynamic> payload) async {
    final url = payload['url'] as String? ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      _respondError(payload, 'Only https links are allowed');
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      _respond(payload, true);
    } catch (e) {
      _respondError(payload, e.toString());
    }
  }

  Future<void> _handleClipboardWrite(Map<String, dynamic> payload) async {
    final text = payload['text'] as String? ?? '';
    await Clipboard.setData(ClipboardData(text: text));
    _respond(payload, true);
  }

  // ── Context ───────────────────────────────────────────────────────

  /// Builds the `wallet` object exposed to the mini-app.
  ///
  /// Starts from the backend "sparks" wallet (`/api/miniapp/wallet`) and, when
  /// an on-chain wallet (Phantom/Reown via WalletConnect, or the built-in
  /// wallet) is bound to the profile, merges its base58 address in. If no
  /// binding is found yet, tries to restore a persisted Reown/Phantom session
  /// from storage first — that's what makes the connected wallet survive an
  /// app/mini-app restart instead of always showing "not connected".
  Future<Map<String, dynamic>?> _resolveWalletContext() async {
    var wallet = await ApiService.getMiniAppWallet();
    var binding = await _walletProxy.getBinding();
    if (!binding.bound && mounted) {
      await AppState.instance.restoreExternalWalletSession(context);
      binding = await _walletProxy.getBinding();
    }
    if (binding.bound && binding.publicKey != null) {
      wallet = {
        ...?wallet,
        'address': binding.publicKey,
        'source': binding.source,
        if (binding.peerName != null) 'peer_name': binding.peerName,
        if (wallet == null || wallet['balance'] == null) 'balance': 0,
      };
    }
    return wallet;
  }

  Future<void> _handleGetContext(Map<String, dynamic> payload) async {
    final user = await _getUser();
    final brightness = MediaQuery.platformBrightnessOf(context);
    final wallet = await _resolveWalletContext();
    final hasGamepads = _nativeGamepads.isNotEmpty;
    _respond(payload, {
      'user': user,
      'theme': brightness == Brightness.dark ? 'dark' : 'light',
      'platform': _getPlatform(),
      'permissions': {},
      'sparks': wallet ?? {'balance': 0},
      'wallet': wallet,
      'gamepadSupported': hasGamepads,
      'gamepads': _nativeGamepads,
      'orientation': await _getOrientationState(),
      'multiplayer': null,
      'voice': null,
    });
    // Keep the web SDK in sync if we just restored/changed the binding.
    if (wallet != null) {
      _sendToWeb('NAJI_WALLET_UPDATE', {'wallet': wallet});
    }
  }

  // ── Gamepads ──────────────────────────────────────────────────────

  void _refreshGamepads() {
    _handleNativeGamepadsRequest({});
  }

  void _setupNativeGamepadListener() {
    _gamepadChannel.setMethodCallHandler((call) async {
      if (call.method == 'onGamepadsUpdate') {
        final List list = call.arguments as List? ?? [];
        _nativeGamepads = list
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _sendGamepadsToWeb();
      }
    });
  }

  void _sendGamepadsToWeb() {
    _sendToWeb('NATIVE_GAMEPADS_UPDATE', {'gamepads': _nativeGamepads});
  }

  Future<void> _handleNativeGamepadsRequest(
    Map<String, dynamic> payload,
  ) async {
    try {
      final result = await _gamepadChannel.invokeMethod<List>('getGamepads');
      _nativeGamepads = (result ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      _nativeGamepads = [];
    }
    _sendToWeb('NATIVE_GAMEPADS_UPDATE', {'gamepads': _nativeGamepads});
  }

  Future<void> _handleGetGamepads(Map<String, dynamic> payload) async {
    try {
      final result = await _gamepadChannel.invokeMethod<List>('getGamepads');
      _nativeGamepads = (result ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {}
    _sendGamepadsToWeb();
    _respond(payload, _nativeGamepads);
  }

  // ── Gyroscope ─────────────────────────────────────────────────────

  void _setupNativeGyroscopeListener() {
    _gyroscopeChannel.setMethodCallHandler((call) async {
      if (call.method == 'onGyroscopeUpdate') {
        _lastGyroscopeData = (call.arguments as Map<dynamic, dynamic>?)?.map(
          (k, v) => MapEntry(k.toString(), v),
        );
        _sendToWeb('NAJI_EVENT', {
          'eventName': 'gyroscopeChanged',
          'payload': _lastGyroscopeData,
        });
      }
    });
  }

  Future<void> _handleGyroscopeGetState(Map<String, dynamic> payload) async {
    try {
      final result = await _gyroscopeChannel.invokeMethod<Map>(
        'getGyroscopeState',
      );
      _lastGyroscopeData = result?.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {}
    _respond(payload, _lastGyroscopeData);
  }

  Future<void> _handleGyroscopeStart(Map<String, dynamic> payload) async {
    try {
      await _gyroscopeChannel.invokeMethod('startGyroscope');
    } catch (_) {}
  }

  Future<void> _handleGyroscopeStop(Map<String, dynamic> payload) async {
    try {
      await _gyroscopeChannel.invokeMethod('stopGyroscope');
    } catch (_) {}
  }

  // ── Accelerometer ─────────────────────────────────────────────────

  void _setupNativeAccelerometerListener() {
    _accelerometerChannel.setMethodCallHandler((call) async {
      if (call.method == 'onAccelerometerUpdate') {
        _lastAccelerometerData = (call.arguments as Map<dynamic, dynamic>?)
            ?.map((k, v) => MapEntry(k.toString(), v));
        _sendToWeb('NAJI_EVENT', {
          'eventName': 'accelerometerChanged',
          'payload': _lastAccelerometerData,
        });
      }
    });
  }

  Future<void> _handleAccelerometerGetState(
    Map<String, dynamic> payload,
  ) async {
    try {
      final result = await _accelerometerChannel.invokeMethod<Map>(
        'getAccelerometerState',
      );
      _lastAccelerometerData = result?.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {}
    _respond(payload, _lastAccelerometerData);
  }

  Future<void> _handleAccelerometerStart(Map<String, dynamic> payload) async {
    try {
      await _accelerometerChannel.invokeMethod('startAccelerometer');
    } catch (_) {}
  }

  Future<void> _handleAccelerometerStop(Map<String, dynamic> payload) async {
    try {
      await _accelerometerChannel.invokeMethod('stopAccelerometer');
    } catch (_) {}
  }

  // ── NFC ───────────────────────────────────────────────────────────

  void _setupNativeNfcListener() {
    _nfcChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onNfcTagRead':
          final data = (call.arguments as Map<dynamic, dynamic>?)?.map(
            (k, v) => MapEntry(k.toString(), v),
          );
          final reqId = _nfcPendingReqId;
          _nfcPendingReqId = null;
          if (reqId != null) {
            _respond({'reqId': reqId}, data);
          } else {
            _sendToWeb('NAJI_EVENT', {
              'eventName': 'nfcTagRead',
              'payload': data,
            });
          }
          break;
        case 'onNfcWritten':
          final reqId = _nfcPendingReqId;
          _nfcPendingReqId = null;
          if (reqId != null) {
            _respond({'reqId': reqId}, {'success': true});
          }
          break;
        case 'onNfcError':
          final error = (call.arguments as Map<dynamic, dynamic>?)?.map(
            (k, v) => MapEntry(k.toString(), v),
          );
          final reqId = _nfcPendingReqId;
          _nfcPendingReqId = null;
          if (reqId != null) {
            _respondError({
              'reqId': reqId,
            }, error?['error']?.toString() ?? 'nfc error');
          }
          break;
        case 'onIsoDepConnected':
          final isoData = (call.arguments as Map<dynamic, dynamic>?)?.map(
            (k, v) => MapEntry(k.toString(), v),
          );
          final isoReqId = _nfcPendingReqId;
          _nfcPendingReqId = null;
          if (isoReqId != null) {
            _respond({'reqId': isoReqId}, isoData);
          }
          break;
      }
    });
  }

  Future<void> _handleNfcIsAvailable(Map<String, dynamic> payload) async {
    try {
      final available =
          await _nfcChannel.invokeMethod<bool>('isNfcAvailable') ?? false;
      _respond(payload, {'available': available});
    } catch (_) {
      _respond(payload, {'available': false});
    }
  }

  Future<void> _handleNfcIsEnabled(Map<String, dynamic> payload) async {
    try {
      final enabled =
          await _nfcChannel.invokeMethod<bool>('isNfcEnabled') ?? false;
      _respond(payload, {'enabled': enabled});
    } catch (_) {
      _respond(payload, {'enabled': false});
    }
  }

  Future<void> _handleNfcRead(Map<String, dynamic> payload) async {
    if (_nfcPendingReqId != null) {
      _respondError(payload, 'NFC operation already in progress');
      return;
    }
    _nfcPendingReqId = payload['reqId'];
    try {
      await _nfcChannel.invokeMethod('startRead');
    } catch (_) {
      _nfcPendingReqId = null;
    }
  }

  Future<void> _handleNfcWrite(Map<String, dynamic> payload) async {
    if (_nfcPendingReqId != null) {
      _respondError(payload, 'NFC operation already in progress');
      return;
    }
    _nfcPendingReqId = payload['reqId'];
    try {
      final records = payload['records'] as List<dynamic>?;
      await _nfcChannel.invokeMethod('writeTag', {'records': records ?? []});
    } catch (_) {
      _nfcPendingReqId = null;
    }
  }

  Future<void> _handleNfcSharePayload(Map<String, dynamic> payload) async {
    try {
      final text = payload['text'] as String? ?? '';
      await _nfcChannel.invokeMethod('sharePayload', {'text': text});
      _respond(payload, {'success': true});
    } catch (_) {
      _respond(payload, {'success': false});
    }
  }

  Future<void> _handleNfcStopShare(Map<String, dynamic> payload) async {
    try {
      await _nfcChannel.invokeMethod('stopShare');
    } catch (_) {}
  }

  Future<void> _handleNfcCancel(Map<String, dynamic> payload) async {
    final reqId = _nfcPendingReqId;
    _nfcPendingReqId = null;
    try {
      await _nfcChannel.invokeMethod('stopRead');
    } catch (_) {}
    if (reqId != null) {
      _respondError({'reqId': reqId}, 'NFC operation cancelled');
    }
  }

  // ── NFC IsoDep ────────────────────────────────────────────────────

  Future<void> _handleNfcConnectIsoDep(Map<String, dynamic> payload) async {
    if (_nfcPendingReqId != null) {
      _respondError(payload, 'NFC operation already in progress');
      return;
    }
    _nfcPendingReqId = payload['reqId'];
    try {
      await _nfcChannel.invokeMethod('connectIsoDep');
    } catch (_) {
      _nfcPendingReqId = null;
    }
  }

  Future<void> _handleNfcTransceive(Map<String, dynamic> payload) async {
    try {
      final command = payload['command'] as String? ?? '';
      final result = await _nfcChannel.invokeMethod<String>('transceive', {
        'command': command,
      });
      _respond(payload, result);
    } catch (e) {
      _respondError(payload, e.toString());
    }
  }

  Future<void> _handleNfcDisconnectIsoDep(Map<String, dynamic> payload) async {
    try {
      await _nfcChannel.invokeMethod('disconnectIsoDep');
    } catch (_) {}
  }

  // ── Camera ──────────────────────────────────────────────────────

  Future<void> _handleCameraTakePhoto(Map<String, dynamic> payload) async {
    try {
      final result = await _cameraChannel.invokeMethod<String>('takePhoto');
      _respond(payload, result);
    } catch (e) {
      _respondError(payload, e.toString());
    }
  }

  // ── Bluetooth ────────────────────────────────────────────────────

  void _setupNativeBluetoothListener() {
    _bluetoothChannel.setMethodCallHandler((call) async {
      debugPrint('[Bluetooth] ${call.method}: ${call.arguments}');
      switch (call.method) {
        case 'onDeviceFound':
          final device = (call.arguments as Map<dynamic, dynamic>?)?.map(
            (k, v) => MapEntry(k.toString(), v),
          );
          if (device?['error'] != null) {
            debugPrint('[Bluetooth] Device error: ${device?['error']}');
          }
          _sendToWeb('NAJI_EVENT', {
            'eventName': 'bluetoothDeviceFound',
            'payload': device,
          });
          break;
        case 'onBluetoothError':
          final errorData = (call.arguments as Map<dynamic, dynamic>?)?.map(
            (k, v) => MapEntry(k.toString(), v),
          );
          debugPrint('[Bluetooth] Native error: $errorData');
          _sendToWeb('NAJI_EVENT', {
            'eventName': 'bluetoothDeviceFound',
            'payload': {'error': errorData?['error'] ?? 'unknown'},
          });
          break;
        case 'onDataReceived':
          final data = (call.arguments as Map<dynamic, dynamic>?)?.map(
            (k, v) => MapEntry(k.toString(), v),
          );
          _sendToWeb('NAJI_EVENT', {
            'eventName': 'bluetoothDataReceived',
            'payload': data,
          });
          break;
        case 'onConnectionStateChanged':
          final state = (call.arguments as Map<dynamic, dynamic>?)?.map(
            (k, v) => MapEntry(k.toString(), v),
          );
          _sendToWeb('NAJI_EVENT', {
            'eventName': 'bluetoothConnectionStateChanged',
            'payload': state,
          });
          break;
      }
    });
  }

  Future<void> _handleBluetoothStartScan(Map<String, dynamic> payload) async {
    try {
      final result = await _bluetoothChannel.invokeMethod('startScan', payload);
      _respond(payload, result);
    } catch (e) {
      _respondError(payload, e.toString());
    }
  }

  Future<void> _handleBluetoothStopScan(Map<String, dynamic> payload) async {
    try {
      await _bluetoothChannel.invokeMethod('stopScan');
    } catch (_) {}
  }

  Future<void> _handleBluetoothConnect(Map<String, dynamic> payload) async {
    try {
      final result = await _bluetoothChannel.invokeMethod('connect', payload);
      _respond(payload, result);
    } catch (e) {
      _respondError(payload, e.toString());
    }
  }

  Future<void> _handleBluetoothSendRaw(Map<String, dynamic> payload) async {
    try {
      final result = await _bluetoothChannel.invokeMethod('sendRaw', payload);
      _respond(payload, result);
    } catch (e) {
      _respondError(payload, e.toString());
    }
  }

  Future<void> _handleBluetoothDiscoverServices(
    Map<String, dynamic> payload,
  ) async {
    try {
      final result = await _bluetoothChannel.invokeMethod(
        'discoverServices',
        payload,
      );
      _respond(payload, result);
    } catch (e) {
      _respondError(payload, e.toString());
    }
  }

  Future<void> _handleBluetoothSubscribe(Map<String, dynamic> payload) async {
    try {
      final result = await _bluetoothChannel.invokeMethod('subscribe', payload);
      _respond(payload, result);
    } catch (e) {
      _respondError(payload, e.toString());
    }
  }

  Future<void> _handleBluetoothUnsubscribe(Map<String, dynamic> payload) async {
    try {
      final result = await _bluetoothChannel.invokeMethod(
        'unsubscribe',
        payload,
      );
      _respond(payload, result);
    } catch (e) {
      _respondError(payload, e.toString());
    }
  }

  Future<void> _handleBluetoothReadRaw(Map<String, dynamic> payload) async {
    try {
      final result = await _bluetoothChannel.invokeMethod('readRaw', payload);
      _respond(payload, result);
    } catch (e) {
      _respondError(payload, e.toString());
    }
  }

  // ── Vibrator ──────────────────────────────────────────────────────

  Future<void> _handleVibrate(Map<String, dynamic> payload) async {
    try {
      final duration = (payload['duration'] as num?)?.toInt() ?? 200;
      await _vibratorChannel.invokeMethod('vibrate', duration);
    } catch (_) {}
  }

  // ── Orientation ───────────────────────────────────────────────────

  Future<void> _handleGetOrientation(Map<String, dynamic> payload) async {
    _respond(payload, await _getOrientationState());
  }

  Future<Map<String, dynamic>> _getOrientationState() async {
    final view = View.of(context);
    final size = view.physicalSize;
    final isLandscape = size.width > size.height;
    return {'orientation': isLandscape ? 'landscape' : 'portrait', 'angle': 0};
  }

  // ── Wallet ────────────────────────────────────────────────────────

  Future<void> _handleWalletState(Map<String, dynamic> payload) async {
    final wallet = await ApiService.getMiniAppWallet();
    _sendToWeb('NAJI_WALLET_UPDATE', {'wallet': wallet});
    _respond(payload, wallet);
  }

  static const _walletProxy = WalletAccessProxy();

  Future<void> _handleWalletGetBinding(Map<String, dynamic> payload) async {
    try {
      final binding = await _walletProxy.getBinding();
      _respond(payload, binding.toJson());
    } catch (e) {
      _respondError(payload, e.toString());
    }
  }

  Future<void> _handleWalletGetAddress(Map<String, dynamic> payload) async {
    try {
      final binding = await _walletProxy.getBinding();
      _respond(payload, binding.toJson());
    } catch (e) {
      _respondError(payload, e.toString());
    }
  }

  Future<void> _handleWalletSignMessage(Map<String, dynamic> payload) async {
    final message = payload['message'];
    List<int>? bytes;
    if (message is String) {
      try {
        bytes = base58Decode(message);
      } catch (_) {
        try {
          bytes = base64.decode(message);
        } catch (_) {
          bytes = null;
        }
      }
    } else if (message is List) {
      bytes = message.map((e) => (e as num).toInt()).toList();
    }
    if (bytes == null) {
      _respondError(payload, 'Invalid or missing message');
      return;
    }
    try {
      final result = await _walletProxy.signMessage(context, message: bytes);
      _respond(payload, result.toJson());
    } catch (e) {
      _respondError(payload, e.toString());
    }
  }

  Future<void> _handleWalletSignTransaction(
    Map<String, dynamic> payload,
  ) async {
    final transaction = payload['transaction'];
    if (transaction is! String || transaction.isEmpty) {
      _respondError(payload, 'Missing transaction');
      return;
    }
    try {
      final result = await _walletProxy.signTransaction(
        context,
        transaction: transaction,
      );
      _respond(payload, result.toJson());
    } catch (e) {
      _respondError(payload, e.toString());
    }
  }

  Future<void> _handleWalletSignAndSend(Map<String, dynamic> payload) async {
    final transaction = payload['transaction'];
    if (transaction is! String || transaction.isEmpty) {
      _respondError(payload, 'Missing transaction');
      return;
    }
    try {
      final result = await _walletProxy.signAndSendTransaction(
        context,
        transaction: transaction,
      );
      _respond(payload, result.toJson());
    } catch (e) {
      _respondError(payload, e.toString());
    }
  }

  /// `sdk.wallet.view()` — opens the Reown AppKit connect modal (or the
  /// built-in wallet screen) so the user can connect Phantom/Solflare. When a
  /// wallet is already bound, just returns its info without prompting.
  Future<void> _handleWalletView(Map<String, dynamic> payload) async {
    try {
      var binding = await _walletProxy.getBinding();
      if (!binding.bound) {
        // Try restoring a persisted session first; if still nothing, present
        // the Reown connect modal so the user can pick a wallet.
        if (!mounted) {
          _respondError(payload, 'Mini-app closed');
          return;
        }
        await AppState.instance.restoreExternalWalletSession(context);
        binding = await _walletProxy.getBinding();
      }
      if (!binding.bound) {
        if (!mounted) {
          _respondError(payload, 'Mini-app closed');
          return;
        }
        await AppState.instance.connectExternalWallet(context);
        binding = await _walletProxy.getBinding();
      }
      final wallet = binding.bound && binding.publicKey != null
          ? {
              'address': binding.publicKey,
              'source': binding.source,
              if (binding.peerName != null) 'peer_name': binding.peerName,
              'balance': 0,
            }
          : null;
      if (wallet != null) {
        _sendToWeb('NAJI_WALLET_UPDATE', {'wallet': wallet});
      }
      _respond(payload, wallet);
    } catch (e) {
      _respondError(payload, e.toString());
    }
  }

  /// `sdk.payments.solana()` / `payments.requestPayment({currency:'SOL'})` —
  /// builds a System Program transfer of `amount` SOL (or `lamports` if given)
  /// to `recipient`, then routes it through the connected wallet (Phantom/Reown
  /// when bound, otherwise the built-in wallet). If no wallet is bound, the
  /// Reown connect modal is opened first and the request is retried.
  ///
  /// Supported payload fields:
  ///   amount     number  SOL (human units) — required unless `lamports` set
  ///   lamports   int     raw lamports (overrides amount)
  ///   recipient  string  base58 destination — required (alias: address)
  ///   memo       string  optional on-chain memo
  Future<void> _handleSolanaPayment(Map<String, dynamic> payload) async {
    final recipient = (payload['recipient'] ?? payload['address'] ?? '')
        .toString()
        .trim();
    debugPrint(
      '[miniapp-pay] requested recipient=$recipient amount=${payload['amount']}',
    );
    if (recipient.isEmpty) {
      _respondError(payload, 'Missing recipient');
      return;
    }
    // Fail fast with a readable message instead of the solana package's
    // cryptic "Invalid base58 character found: N" (alphabet excludes 0,O,I,l).
    if (!RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$').hasMatch(recipient)) {
      _respondError(payload, 'Invalid recipient address (base58 expected)');
      return;
    }
    int? lamports;
    final rawLamports = payload['lamports'];
    if (rawLamports is int) {
      lamports = rawLamports;
    } else if (rawLamports is num) {
      lamports = rawLamports.toInt();
    }
    if (lamports == null) {
      final amount = payload['amount'];
      if (amount is num && amount > 0) {
        lamports = (amount * 1e9).round();
      } else {
        _respondError(payload, 'Invalid amount');
        return;
      }
    }
    final memo = payload['memo']?.toString();
    debugPrint('[miniapp-pay] resolved lamports=$lamports memo=$memo');

    try {
      // Ensure a wallet is connected; if not, present Reown connect modal.
      var binding = await _walletProxy.getBinding();
      debugPrint(
        '[miniapp-pay] initial binding bound=${binding.bound} '
        'source=${binding.source} pub=${binding.publicKey}',
      );
      if (!binding.bound) {
        if (!mounted) {
          _respondError(payload, 'Mini-app closed');
          return;
        }
        await AppState.instance.restoreExternalWalletSession(context);
        binding = await _walletProxy.getBinding();
        debugPrint(
          '[miniapp-pay] after restore bound=${binding.bound} '
          'source=${binding.source} pub=${binding.publicKey}',
        );
      }
      if (!binding.bound) {
        if (!mounted) {
          _respondError(payload, 'Mini-app closed');
          return;
        }
        debugPrint('[miniapp-pay] no binding — opening Reown connect modal');
        await AppState.instance.connectExternalWallet(context);
        binding = await _walletProxy.getBinding();
        debugPrint(
          '[miniapp-pay] after connect modal bound=${binding.bound} '
          'source=${binding.source} pub=${binding.publicKey}',
        );
      }
      if (!binding.bound || binding.publicKey == null) {
        _respondError(payload, 'No wallet connected');
        return;
      }

      final result = await _walletProxy.paySolana(
        context,
        recipient: recipient,
        lamports: lamports,
        memo: memo,
      );
      _respond(payload, {
        ...result.toJson(),
        'recipient': recipient,
        'amount_sol': lamports / 1e9,
      });
    } catch (e) {
      debugPrint('[miniapp-pay] failed: $e');
      _respondError(payload, e.toString());
    }
  }

  // ── Contacts ──────────────────────────────────────────────────────

  Future<void> _handleContacts(
    String type,
    Map<String, dynamic> payload,
  ) async {
    if (type == 'MINIAPP_CONTACTS_GET') {
      try {
        final contacts = await NajiContactsService.fetchAndCheck();
        final result = contacts
            .map(
              (c) => {
                'id': c.najiMeUserId ?? '',
                'name': c.name,
                'username': c.najiMeUsername ?? '',
                'avatar': c.najiMeAvatarUrl ?? '',
                'phone': c.phoneNumber,
                'is_registered': c.isOnNajiMe,
              },
            )
            .toList();
        _respond(payload, result);
      } catch (e) {
        _respond(payload, <dynamic>[]);
      }
    } else if (type == 'MINIAPP_SHARE_TO_CONTACT') {
      _respond(payload, {'ok': true, 'shared': true});
    } else if (type == 'MINIAPP_CONTACT_INVITE') {
      _respond(payload, {'ok': true, 'invited': true});
    }
  }

  // ── Multiplayer ───────────────────────────────────────────────────

  void _onP2pChanged() {
    if (!mounted) return;
    _sendToWeb('NAJI_EVENT', {
      'eventName': 'multiplayerStateChanged',
      'payload': P2PRoomService.instance.multiplayerState,
    });
    final voice = P2PRoomService.instance.voiceState;
    _sendToWeb('NAJI_EVENT', {
      'eventName': 'voiceStateChanged',
      'payload': voice,
    });
    _sendToWeb('NAJI_EVENT', {
      'eventName': 'voiceParticipantsChanged',
      'payload': voice['participants'] ?? const [],
    });
  }

  void _onP2pEvent(
    String from,
    String eventName,
    Map<String, dynamic> payload,
  ) {
    if (!mounted) return;
    _sendToWeb('NAJI_EVENT', {
      'eventName': 'multiplayerEvent',
      'payload': {'from': from, 'eventName': eventName, 'payload': payload},
    });
  }

  Future<void> _handleMultiplayer(
    String type,
    Map<String, dynamic> payload,
  ) async {
    final p2p = P2PRoomService.instance;

    if (type == 'MINIAPP_MULTIPLAYER_GET_STATE') {
      _respond(payload, p2p.multiplayerState);
      return;
    }

    if (type == 'MINIAPP_MULTIPLAYER_CREATE_ROOM') {
      final maxPlayers = payload['max_players'] as int? ?? 8;
      await p2p.createRoom(maxPlayers: maxPlayers);
      _respond(payload, p2p.inRoom ? p2p.multiplayerState : null);
      return;
    }

    if (type == 'MINIAPP_MULTIPLAYER_JOIN_ROOM') {
      final roomId = payload['room_id'] as String? ?? '';
      await p2p.joinRoom(roomId);
      _respond(payload, p2p.inRoom ? p2p.multiplayerState : null);
      return;
    }

    if (type == 'MINIAPP_MULTIPLAYER_LEAVE_ROOM') {
      await p2p.leaveRoom();
      _respond(payload, {'ok': true});
      return;
    }

    if (type == 'MINIAPP_MULTIPLAYER_JOIN_MATCHMAKING') {
      final ok = await p2p.joinMatchmaking();
      _respond(payload, ok ? p2p.multiplayerState : null);
      return;
    }

    if (type == 'MINIAPP_MULTIPLAYER_LEAVE_MATCHMAKING') {
      await p2p.leaveRoom();
      _respond(payload, {'ok': true});
      return;
    }

    if (type == 'MINIAPP_MULTIPLAYER_UPDATE_STATE') {
      final roomId = payload['room_id'] as String? ?? '';
      final state = (payload['state'] as Map<String, dynamic>?) ?? {};
      await ApiService.updateMultiplayerState(roomId, state);
      p2p.sendToPeers('room_state_update', state);
      _respond(payload, {'ok': true});
      return;
    }

    if (type == 'MINIAPP_MULTIPLAYER_SEND_EVENT' ||
        type == 'MINIAPP_MULTIPLAYER_SEND_EVENT_FAST') {
      final eventName = payload['eventName'] as String? ?? 'event';
      final eventPayload = (payload['payload'] as Map<String, dynamic>?) ?? {};
      p2p.sendToPeers(
        eventName,
        eventPayload,
        transient: type == 'MINIAPP_MULTIPLAYER_SEND_EVENT_FAST',
      );
      _respond(payload, {'ok': true, 'delivered': true});
      return;
    }

    _respond(payload, {'ok': true});
  }

  // ── Voice ─────────────────────────────────────────────────────────

  Future<void> _handleVoice(String type, Map<String, dynamic> payload) async {
    final p2p = P2PRoomService.instance;
    if (type == 'MINIAPP_VOICE_GET_STATE') {
      _respond(payload, p2p.voiceState);
      return;
    }

    if (type == 'MINIAPP_VOICE_JOIN') {
      if (!p2p.inRoom) {
        _respond(payload, p2p.voiceState);
        return;
      }
      await p2p.joinVoice();
      _respond(payload, p2p.voiceState);
      return;
    }

    if (type == 'MINIAPP_VOICE_LEAVE') {
      await p2p.leaveVoice();
      _respond(payload, p2p.voiceState);
      return;
    }

    if (type == 'MINIAPP_VOICE_SET_MUTED') {
      final muted = payload['muted'] as bool? ?? false;
      await p2p.setMuted(muted);
      _respond(payload, p2p.voiceState);
      return;
    }

    _respond(payload, p2p.voiceState);
  }

  // ── JS Communication ──────────────────────────────────────────────

  void _runJs(String js) {
    if (_useFlutterWebView) {
      _webViewController?.runJavaScript(js);
    } else if (_useWindowsNativeWebView) {
      _windowsController?.executeScript(js);
    } else {
      _webviewChannel?.invokeMethod('runJavaScript', {'js': js});
    }
  }

  void _sendToWeb(String type, Map<String, dynamic> data) {
    final json = jsonEncode({'type': type, ...data});
    final b64 = base64Encode(utf8.encode(json));
    _runJs("window.__najiHandleMessage(JSON.parse(atob('$b64')));");
  }

  void _respond(Map<String, dynamic> payload, dynamic result) {
    final reqId = payload['reqId'] as String?;
    if (reqId == null) return;
    _sendToWeb('NAJI_ASYNC_RESPONSE', {'reqId': reqId, 'result': result});
  }

  void _respondError(Map<String, dynamic> payload, String error) {
    final reqId = payload['reqId'] as String?;
    if (reqId == null) return;
    _sendToWeb('NAJI_ASYNC_RESPONSE', {'reqId': reqId, 'error': error});
  }

  void _retry() {
    if (!_isAllowedMiniAppUrl(widget.url)) {
      setState(() {
        _error =
            'URL not allowed: only HTTPS URLs from trusted hosts are permitted';
        _loading = false;
      });
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    if (_useFlutterWebView) {
      _webViewController?.loadRequest(Uri.parse(widget.url));
    } else if (_useWindowsNativeWebView) {
      _windowsController?.loadUrl(widget.url);
    } else {
      _webviewChannel?.invokeMethod('loadUrl', {'url': widget.url});
    }
  }

  Future<void> _openExternal() async {
    final ok = await launchUrl(Uri.parse(widget.url));
    if (ok && mounted) Navigator.of(context).pop();
  }

  Widget _buildFallback(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.open_in_browser, size: 56, color: cs.primary),
            const SizedBox(height: 16),
            Text(
              'Mini Apps are not supported on this platform yet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openExternal,
              icon: const Icon(Icons.open_in_browser, size: 20),
              label: const Text('Open in browser'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    P2PRoomService.instance.onChanged = null;
    P2PRoomService.instance.onEvent = null;
    _windowsController?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_backButtonVisible,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _backButtonVisible) {
          _sendToWeb('NAJI_EVENT', {
            'eventName': 'backButtonClicked',
            'payload': null,
          });
        }
      },
      child: Scaffold(
        backgroundColor: _headerColor == Colors.transparent
            ? cs.surface
            : _headerColor,
        body: SafeArea(
          top: !_fullscreen,
          bottom: !_fullscreen,
          child: Stack(
            children: [
              if (_useAndroidView)
                AndroidView(
                  viewType: 'naji_webview',
                  creationParams: {'url': widget.url},
                  creationParamsCodec: const StandardMessageCodec(),
                  onPlatformViewCreated: _onPlatformViewCreated,
                )
              else if (_useWindowsNativeWebView)
                (_windowsController != null &&
                        _windowsController!.value.isInitialized
                    ? Webview(_windowsController!)
                    : const SizedBox.expand())
              else if (_useFlutterWebView)
                (_webViewController != null
                    ? WebViewWidget(controller: _webViewController!)
                    : const SizedBox.expand())
              else
                _buildFallback(cs),
              if (_loading)
                Center(child: CircularProgressIndicator(color: cs.primary)),
              if (_error != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: cs.error),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                          onPressed: _retry,
                          child: const Text('Retry'),
                        ),
                        if (_useFallback) ...[
                          const SizedBox(height: 8),
                          FilledButton.tonal(
                            onPressed: _openExternal,
                            child: const Text('Open in browser'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
