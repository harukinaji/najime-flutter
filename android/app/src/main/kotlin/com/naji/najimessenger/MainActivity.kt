package com.naji.najimessenger

import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.input.InputManager
import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.IsoDep
import android.nfc.tech.Ndef
import android.nfc.tech.NdefFormatable
import android.app.Activity
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.os.Build
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.MediaStore
import android.util.Log
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import java.util.UUID
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceFragmentActivity

class MainActivity : AudioServiceFragmentActivity(), InputManager.InputDeviceListener, SensorEventListener {
    companion object {
        const val TAG = "NajiGamepad"
        const val NOTIFICATION_CHANNEL = "com.naji.najimessenger/notifications"
        const val GAMEPAD_CHANNEL = "com.naji.najimessenger/gamepads"
        const val GYROSCOPE_CHANNEL = "com.naji.najimessenger/gyroscope"
        const val ACCELEROMETER_CHANNEL = "com.naji.najimessenger/accelerometer"
        const val VIBRATOR_CHANNEL = "com.naji.najimessenger/vibrator"
        const val NFC_CHANNEL = "com.naji.najimessenger/nfc"
        const val CAMERA_CHANNEL = "com.naji.najimessenger/camera"
        const val BLUETOOTH_CHANNEL = "com.naji.najimessenger/bluetooth"
        const val TOKEN_CHANNEL = "com.naji.najimessenger/token"
        var pendingReply: Map<String, String>? = null
    }

    private var methodChannel: MethodChannel? = null
    private var gamepadChannel: MethodChannel? = null
    private var gyroscopeChannel: MethodChannel? = null
    private var accelerometerChannel: MethodChannel? = null
    private var inputManager: InputManager? = null
    private var sensorManager: SensorManager? = null
    private var gyroscopeSensor: Sensor? = null
    private var accelerometerSensor: Sensor? = null
    private var gyroscopeListening = false
    private var accelerometerListening = false
    private var lastGyroscopeData: Map<String, Any?>? = null
    private var lastAccelerometerData: Map<String, Any?>? = null
    private val handler = Handler(Looper.getMainLooper())
    private var gamepadsFound = false
    private var nfcAdapter: NfcAdapter? = null
    private var nfcChannel: MethodChannel? = null
    private var nfcPendingRead = false
    private var nfcPendingWriteRecords: List<Map<String, Any?>>? = null
    private var nfcPendingIsoDep = false
    private var nfcIsoDep: IsoDep? = null
    private var cameraChannel: MethodChannel? = null
    private var pendingCameraResult: MethodChannel.Result? = null
    private var bluetoothChannel: MethodChannel? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothLeScanner: BluetoothLeScanner? = null
    private var bluetoothGattMap = mutableMapOf<String, BluetoothGatt>()

    private val bluetoothScanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device
            val deviceMap = mapOf(
                "name" to (device.name ?: ""),
                "address" to (device.address ?: ""),
                "rssi" to result.rssi,
                "deviceId" to device.address
            )
            Log.d(TAG, "BLE device found: ${device.name} (${device.address}) RSSI=${result.rssi}")
            bluetoothChannel?.invokeMethod("onDeviceFound", deviceMap)
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>) {
            Log.d(TAG, "BLE batch scan results: ${results.size} devices")
            for (result in results) {
                onScanResult(0, result)
            }
        }

        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "BLE scan failed with error code: $errorCode")
            bluetoothChannel?.invokeMethod("onBluetoothError", mapOf(
                "error" to "BLE scan failed",
                "errorCode" to errorCode
            ))
        }
    }

    private var bluetoothScanResult: MethodChannel.Result? = null
    private var bluetoothReadResult: MethodChannel.Result? = null

    private val bluetoothPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val allGranted = permissions.values.all { it }
        if (allGranted) {
            Log.d(TAG, "Bluetooth permissions granted, starting scan")
            startBluetoothScanInternal()
        } else {
            Log.e(TAG, "Bluetooth permissions denied: $permissions")
            bluetoothChannel?.invokeMethod("onBluetoothError", mapOf("error" to "permissions_denied"))
            bluetoothScanResult?.error("BLUETOOTH_PERMISSION_DENIED", "Bluetooth permissions not granted", null)
            bluetoothScanResult = null
        }
    }

    private val cameraLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val pending = pendingCameraResult
        pendingCameraResult = null
        if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            val bitmap = result.data!!.extras?.get("data") as? Bitmap
            if (bitmap != null) {
                val stream = java.io.ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.JPEG, 80, stream)
                val bytes = stream.toByteArray()
                val base64 = java.util.Base64.getEncoder().encodeToString(bytes)
                handler.post { pending?.success(base64) }
            } else {
                handler.post { pending?.success(null) }
            }
        } else {
            handler.post { pending?.error("CANCELLED", "Camera cancelled", null) }
        }
    }

    private val nfcReaderCallback = NfcAdapter.ReaderCallback { tag -> onNfcTagDetected(tag) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialReply" -> {
                    val reply = pendingReply
                    pendingReply = null
                    result.success(reply)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TOKEN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "encrypt" -> {
                    val plain = call.arguments as? String ?: ""
                    result.success(TokenCrypto.encrypt(plain))
                }
                "decrypt" -> {
                    result.success(TokenCrypto.decrypt(call.arguments as? String ?: ""))
                }
                else -> result.notImplemented()
            }
        }

        // App Attestation Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.naji.najimessenger/attestation").setMethodCallHandler { call, result ->
            when (call.method) {
                "getAttestationKey" -> {
                    result.success(AppAttestationKey.getRawKey())
                }
                "setAttestationKey" -> {
                    // Key is already managed by Android Keystore
                    result.success(true)
                }
                "getDeviceId" -> {
                    result.success(AppAttestationKey.getDeviceId())
                }
                "sign" -> {
                    val data = call.arguments as? String ?: ""
                    result.success(AppAttestationKey.sign(data))
                }
                else -> result.notImplemented()
            }
        }

        gamepadChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GAMEPAD_CHANNEL)
        gamepadChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getGamepads" -> {
                    val gamepads = getConnectedGamepads()
                    Log.d(TAG, "getGamepads called, found ${gamepads.size} gamepads")
                    result.success(gamepads)
                }
                else -> result.notImplemented()
            }
        }

        gyroscopeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GYROSCOPE_CHANNEL)
        gyroscopeChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getGyroscopeState" -> {
                    result.success(lastGyroscopeData)
                }
                "startGyroscope" -> {
                    startGyroscopeListening()
                    result.success(true)
                }
                "stopGyroscope" -> {
                    stopGyroscopeListening()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        accelerometerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ACCELEROMETER_CHANNEL)
        accelerometerChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getAccelerometerState" -> {
                    result.success(lastAccelerometerData)
                }
                "startAccelerometer" -> {
                    startAccelerometerListening()
                    result.success(true)
                }
                "stopAccelerometer" -> {
                    stopAccelerometerListening()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VIBRATOR_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "vibrate" -> {
                    val duration = (call.arguments as? Number)?.toLong() ?: 200L
                    vibrate(duration)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        nfcChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NFC_CHANNEL)
        nfcChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isNfcAvailable" -> result.success(nfcAdapter != null)
                "isNfcEnabled" -> result.success(nfcAdapter?.isEnabled == true)
                "startRead" -> {
                    nfcPendingRead = true
                    nfcPendingWriteRecords = null
                    enableNfcReader()
                    result.success(true)
                }
                "writeTag" -> {
                    val records = call.argument<List<Map<String, Any?>>>("records")
                    nfcPendingWriteRecords = records
                    nfcPendingRead = false
                    enableNfcReader()
                    result.success(true)
                }
                "sharePayload" -> {
                    val text = call.argument<String>("text") ?: ""
                    shareNfcPayload(text)
                    result.success(true)
                }
                "stopShare" -> {
                    stopNfcShare()
                    result.success(true)
                }
                "connectIsoDep" -> {
                    nfcPendingIsoDep = true
                    nfcPendingRead = false
                    nfcPendingWriteRecords = null
                    enableNfcReader()
                    result.success(true)
                }
                "transceive" -> {
                    val hex = call.argument<String>("command") ?: ""
                    val isodep = nfcIsoDep
                    if (isodep == null) {
                        result.error("NOT_CONNECTED", "IsoDep not connected", null)
                    } else {
                        Thread {
                            try {
                                val apdu = hexToBytes(hex)
                                val response = isodep.transceive(apdu)
                                val hexResponse = bytesToHex(response)
                                handler.post { result.success(hexResponse) }
                            } catch (e: Exception) {
                                handler.post { result.error("TRANSCEIVE_ERROR", e.message, null) }
                            }
                        }.start()
                    }
                }
                "disconnectIsoDep" -> {
                    disconnectIsoDep()
                    result.success(true)
                }
                "stopRead" -> {
                    disconnectIsoDep()
                    disableNfcReader()
                    nfcPendingRead = false
                    nfcPendingWriteRecords = null
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        cameraChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAMERA_CHANNEL)
        cameraChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePhoto" -> {
                    val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
                    if (intent.resolveActivity(packageManager) != null) {
                        pendingCameraResult = result
                        cameraLauncher.launch(intent)
                    } else {
                        result.error("NO_CAMERA_APP", "No camera app available", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        bluetoothChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLUETOOTH_CHANNEL)
        bluetoothChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startScan" -> {
                    val args = call.arguments as? Map<String, Any?>
                    val services = args?.get("services") as? List<String>
                    startBluetoothScan(services, result)
                }
                "stopScan" -> {
                    stopBluetoothScan()
                    result.success(true)
                }
                "connect" -> {
                    val args = call.arguments as? Map<String, Any?>
                    val deviceId = args?.get("deviceId") as? String ?: ""
                    connectBluetoothDevice(deviceId)
                    result.success(mapOf("status" to "connecting", "deviceId" to deviceId))
                }
                "sendRaw" -> {
                    val args = call.arguments as? Map<String, Any?>
                    val deviceId = args?.get("deviceId") as? String ?: ""
                    val data = args?.get("data") as? String ?: ""
                    sendBluetoothRaw(deviceId, data)
                    result.success(mapOf("status" to "sent"))
                }
                "discoverServices" -> {
                    val args = call.arguments as? Map<String, Any?>
                    val deviceId = args?.get("deviceId") as? String ?: ""
                    discoverServices(deviceId, result)
                }
                "subscribe" -> {
                    val args = call.arguments as? Map<String, Any?>
                    val deviceId = args?.get("deviceId") as? String ?: ""
                    val serviceUuid = args?.get("serviceUuid") as? String ?: ""
                    val characteristicUuid = args?.get("characteristicUuid") as? String ?: ""
                    setCharacteristicNotification(deviceId, serviceUuid, characteristicUuid, true, result)
                }
                "unsubscribe" -> {
                    val args = call.arguments as? Map<String, Any?>
                    val deviceId = args?.get("deviceId") as? String ?: ""
                    val serviceUuid = args?.get("serviceUuid") as? String ?: ""
                    val characteristicUuid = args?.get("characteristicUuid") as? String ?: ""
                    setCharacteristicNotification(deviceId, serviceUuid, characteristicUuid, false, result)
                }
                "readRaw" -> {
                    val args = call.arguments as? Map<String, Any?>
                    val deviceId = args?.get("deviceId") as? String ?: ""
                    val serviceUuid = args?.get("serviceUuid") as? String ?: ""
                    val characteristicUuid = args?.get("characteristicUuid") as? String ?: ""
                    readCharacteristic(deviceId, serviceUuid, characteristicUuid, result)
                }
                else -> result.notImplemented()
            }
        }

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "naji_webview", NajiWebViewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )

        nfcAdapter = NfcAdapter.getDefaultAdapter(this)

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        gyroscopeSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
        accelerometerSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

        inputManager = getSystemService(INPUT_SERVICE) as? InputManager
        inputManager?.registerInputDeviceListener(this, null)

        Log.d(TAG, "configureFlutterEngine: registered InputDeviceListener")
        logAllDevices("init")

        handler.postDelayed({ logAllDevices("delayed-500ms"); notifyGamepadsUpdate() }, 500)
        handler.postDelayed({ logAllDevices("delayed-2s"); notifyGamepadsUpdate() }, 2000)
        handler.postDelayed({ logAllDevices("delayed-5s"); notifyGamepadsUpdate() }, 5000)

        handleIntent(intent)
    }

    private fun logAllDevices(stage: String) {
        val deviceIds = inputManager?.inputDeviceIds
        Log.d(TAG, "[$stage] InputDevice count: ${deviceIds?.size ?: 0}")
        if (deviceIds != null) {
            for (id in deviceIds) {
                val device = inputManager?.getInputDevice(id) ?: continue
                Log.d(TAG, "[$stage] Device id=$id name='${device.name}' sources=0x${device.sources.toString(16)} " +
                    "enabled=${device.isEnabled} virtual=${device.isVirtual} " +
                    "motionRanges=${device.motionRanges?.map { "${it.axis}(src=0x${it.source.toString(16)})" }?.joinToString() ?: "none"}")
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val autoReply = intent?.getBooleanExtra("auto_reply", false) ?: false
        val chatId = intent?.getStringExtra("chat_id")
        val replyText = intent?.getStringExtra("reply_text")

        if (autoReply && chatId != null && replyText != null) {
            val reply = mapOf("chat_id" to chatId, "reply_text" to replyText)
            if (methodChannel != null) {
                methodChannel?.invokeMethod("onReply", reply)
            } else {
                pendingReply = reply
            }
            intent?.removeExtra("auto_reply")
            intent?.removeExtra("reply_text")
        }
    }

    private fun getConnectedGamepads(): List<Map<String, Any?>> {
        val gamepads = mutableListOf<Map<String, Any?>>()
        val deviceIds = inputManager?.inputDeviceIds ?: return gamepads

        for (id in deviceIds) {
            val device = inputManager?.getInputDevice(id) ?: continue
            if (device.isVirtual) continue
            if (!device.isEnabled) continue

            val sources = device.sources
            val isGamepad = (sources and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD
            val isJoystick = (sources and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK

            val hasGamepadButtons = device.hasKeys(
                KeyEvent.KEYCODE_BUTTON_A, KeyEvent.KEYCODE_BUTTON_B,
                KeyEvent.KEYCODE_BUTTON_X, KeyEvent.KEYCODE_BUTTON_Y,
                KeyEvent.KEYCODE_BUTTON_L1, KeyEvent.KEYCODE_BUTTON_R1,
                KeyEvent.KEYCODE_BUTTON_L2, KeyEvent.KEYCODE_BUTTON_R2,
                KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN,
                KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT
            ).any { it }

            val hasAnalogAxes = device.motionRanges.any { range ->
                range.axis == MotionEvent.AXIS_X ||
                range.axis == MotionEvent.AXIS_Y ||
                range.axis == MotionEvent.AXIS_Z ||
                range.axis == MotionEvent.AXIS_RX ||
                range.axis == MotionEvent.AXIS_RY ||
                range.axis == MotionEvent.AXIS_RZ ||
                range.axis == MotionEvent.AXIS_HAT_X ||
                range.axis == MotionEvent.AXIS_HAT_Y
            }

            if (!isGamepad && !isJoystick) continue

            Log.d(TAG, "Found gamepad: id=$id name='${device.name}' sources=0x${sources.toString(16)} " +
                "isGamepad=$isGamepad isJoystick=$isJoystick hasButtons=$hasGamepadButtons hasAxes=$hasAnalogAxes")

            val axes = mutableListOf<Double>()
            val axisIds = intArrayOf(
                MotionEvent.AXIS_X, MotionEvent.AXIS_Y,
                MotionEvent.AXIS_Z, MotionEvent.AXIS_RZ,
                MotionEvent.AXIS_HAT_X, MotionEvent.AXIS_HAT_Y
            )
            for (axisId in axisIds) {
                val range = device.getMotionRange(axisId, InputDevice.SOURCE_JOYSTICK)
                    ?: device.getMotionRange(axisId, InputDevice.SOURCE_GAMEPAD)
                    ?: device.getMotionRange(axisId)
                if (range != null) {
                    axes.add(0.0)
                }
            }

            if (axes.isEmpty()) {
                axes.addAll(listOf(0.0, 0.0))
            }

            val buttons = mutableListOf<Map<String, Any?>>()
            for (b in 0 until 16) {
                buttons.add(mapOf(
                    "pressed" to false,
                    "touched" to false,
                    "value" to 0.0
                ))
            }

            gamepads.add(mapOf(
                "id" to "native_${device.id}_${device.name}",
                "index" to gamepads.size,
                "connected" to true,
                "timestamp" to System.currentTimeMillis(),
                "mapping" to "standard",
                "name" to (device.name ?: "Unknown Gamepad"),
                "axes" to axes,
                "buttons" to buttons
            ))
        }
        return gamepads
    }

    override fun onInputDeviceAdded(deviceId: Int) {
        Log.d(TAG, "onInputDeviceAdded: id=$deviceId")
        val device = inputManager?.getInputDevice(deviceId)
        Log.d(TAG, "  device: name='${device?.name}' sources=0x${device?.sources?.toString(16) ?: "?"}")
        handler.postDelayed({ notifyGamepadsUpdate() }, 200)
        handler.postDelayed({ notifyGamepadsUpdate() }, 1000)
        handler.postDelayed({ notifyGamepadsUpdate() }, 3000)
    }

    override fun onInputDeviceRemoved(deviceId: Int) {
        Log.d(TAG, "onInputDeviceRemoved: id=$deviceId")
        notifyGamepadsUpdate()
    }

    override fun onInputDeviceChanged(deviceId: Int) {
        Log.d(TAG, "onInputDeviceChanged: id=$deviceId")
        notifyGamepadsUpdate()
    }

    private fun notifyGamepadsUpdate() {
        val gamepads = getConnectedGamepads()
        if (gamepads.isNotEmpty()) gamepadsFound = true
        Log.d(TAG, "notifyGamepadsUpdate: ${gamepads.size} gamepads")
        runOnUiThread {
            gamepadChannel?.invokeMethod("onGamepadsUpdate", gamepads)
        }
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        val source = event.source
        if ((source and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK ||
            (source and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD) {
            Log.d(TAG, "dispatchGenericMotionEvent: action=${event.action} source=0x${source.toString(16)} " +
                "device=${event.device?.name} x=${event.x} y=${event.y}")
            if (!gamepadsFound) {
                notifyGamepadsUpdate()
            }
        }
        return super.dispatchGenericMotionEvent(event)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        if (keyCode in 96..111 || keyCode in 188..204) {
            Log.d(TAG, "dispatchKeyEvent: keyCode=$keyCode action=${event.action} device=${event.device?.name}")
            if (!gamepadsFound) {
                notifyGamepadsUpdate()
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode in 96..111 || keyCode in 188..204) {
            notifyGamepadsUpdate()
        }
        return super.onKeyDown(keyCode, event)
    }

    // ── Gyroscope ──────────────────────────────────────────────────────

    private fun startGyroscopeListening() {
        if (gyroscopeListening) return
        val sensor = gyroscopeSensor ?: return
        sensorManager?.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)
        gyroscopeListening = true
        Log.d(TAG, "gyroscope listening started")
    }

    private fun stopGyroscopeListening() {
        if (!gyroscopeListening) return
        sensorManager?.unregisterListener(this)
        gyroscopeListening = false
        Log.d(TAG, "gyroscope listening stopped")
    }

    // ── Accelerometer ──────────────────────────────────────────────────

    private fun startAccelerometerListening() {
        if (accelerometerListening) return
        val sensor = accelerometerSensor ?: return
        sensorManager?.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)
        accelerometerListening = true
        Log.d(TAG, "accelerometer listening started")
    }

    private fun stopAccelerometerListening() {
        if (!accelerometerListening) return
        sensorManager?.unregisterListener(this)
        accelerometerListening = false
        Log.d(TAG, "accelerometer listening stopped")
    }

    override fun onSensorChanged(event: SensorEvent?) {
        val data = event?.values ?: return
        when (event.sensor.type) {
            Sensor.TYPE_GYROSCOPE -> {
                val gyroData = mapOf(
                    "x" to data[0].toDouble(),
                    "y" to data[1].toDouble(),
                    "z" to data[2].toDouble(),
                    "timestamp" to event.timestamp,
                    "sensorAccuracy" to event.accuracy
                )
                lastGyroscopeData = gyroData
                runOnUiThread {
                    gyroscopeChannel?.invokeMethod("onGyroscopeUpdate", gyroData)
                }
            }
            Sensor.TYPE_ACCELEROMETER -> {
                val accelData = mapOf(
                    "x" to data[0].toDouble(),
                    "y" to data[1].toDouble(),
                    "z" to data[2].toDouble(),
                    "timestamp" to event.timestamp,
                    "sensorAccuracy" to event.accuracy
                )
                lastAccelerometerData = accelData
                runOnUiThread {
                    accelerometerChannel?.invokeMethod("onAccelerometerUpdate", accelData)
                }
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    // ── NFC ─────────────────────────────────────────────────────────────

    private fun enableNfcReader() {
        nfcAdapter?.enableReaderMode(this, nfcReaderCallback,
            NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B or
            NfcAdapter.FLAG_READER_NFC_F or NfcAdapter.FLAG_READER_NFC_V or
            NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK, null)
    }

    private fun disableNfcReader() {
        nfcAdapter?.disableReaderMode(this)
    }

    private fun onNfcTagDetected(tag: Tag) {
        if (nfcPendingIsoDep) {
            connectIsoDepTag(tag)
        } else if (nfcPendingWriteRecords != null) {
            writeNdefToTag(tag, nfcPendingWriteRecords!!)
        } else if (nfcPendingRead) {
            readNdefFromTag(tag)
        }
    }

    private fun readNdefFromTag(tag: Tag) {
        try {
            val ndef = Ndef.get(tag)
            val records = if (ndef != null) {
                ndef.connect()
                val msg = ndef.ndefMessage
                val result = msg?.records?.mapIndexed { i, rec ->
                    mapOf(
                        "index" to i,
                        "tnf" to rec.tnf,
                        "type" to String(rec.type, Charsets.UTF_8),
                        "id" to String(rec.id, Charsets.UTF_8),
                        "payload" to String(rec.payload, Charsets.UTF_8)
                    )
                } ?: emptyList<Map<String, Any?>>()
                ndef.close()
                result
            } else {
                emptyList<Map<String, Any?>>()
            }
            val tagId = tag.id.joinToString("") { "%02x".format(it) }
            nfcPendingRead = false
            disableNfcReader()
            runOnUiThread {
                nfcChannel?.invokeMethod("onNfcTagRead", mapOf(
                    "id" to tagId,
                    "records" to records,
                    "tech" to tag.techList.toList()
                ))
            }
        } catch (e: Exception) {
            Log.e(TAG, "NFC read error: ${e.message}", e)
            nfcPendingRead = false
            disableNfcReader()
            runOnUiThread {
                nfcChannel?.invokeMethod("onNfcError", mapOf("error" to (e.message ?: "read failed")))
            }
        }
    }

    private fun writeNdefToTag(tag: Tag, records: List<Map<String, Any?>>) {
        try {
            val ndefRecords = records.map { rec ->
                val tnfRaw = (rec["tnf"] as? Number)?.toInt() ?: NdefRecord.TNF_WELL_KNOWN.toInt()
                val tnf = tnfRaw.toShort()
                val type = (rec["type"] as? String) ?: ""
                val rawPayload = (rec["payload"] as? String) ?: ""
                if (tnfRaw == NdefRecord.TNF_WELL_KNOWN.toInt() && type == "T") {
                    NdefRecord.createTextRecord("en", rawPayload)
                } else if (tnfRaw == NdefRecord.TNF_WELL_KNOWN.toInt() && type == "U") {
                    NdefRecord.createUri(rawPayload)
                } else {
                    NdefRecord(tnf, type.toByteArray(Charsets.UTF_8), (rec["id"] as? String)?.toByteArray(Charsets.UTF_8) ?: ByteArray(0), rawPayload.toByteArray(Charsets.UTF_8))
                }
            }.toTypedArray()
            val message = NdefMessage(ndefRecords)

            val ndef = Ndef.get(tag)
            if (ndef != null) {
                ndef.connect()
                if (ndef.maxSize >= message.toByteArray().size) {
                    ndef.writeNdefMessage(message)
                } else {
                    throw Exception("message too large for tag")
                }
                ndef.close()
            } else {
                val formatable = NdefFormatable.get(tag)
                if (formatable != null) {
                    formatable.connect()
                    formatable.format(message)
                    formatable.close()
                } else {
                    throw Exception("tag does not support NDEF")
                }
            }

            nfcPendingWriteRecords = null
            disableNfcReader()
            runOnUiThread {
                nfcChannel?.invokeMethod("onNfcWritten", null)
            }
        } catch (e: Exception) {
            nfcPendingWriteRecords = null
            disableNfcReader()
            runOnUiThread {
                nfcChannel?.invokeMethod("onNfcError", mapOf("error" to (e.message ?: "write failed")))
            }
        }
    }

    // ── NFC IsoDep ──────────────────────────────────────────────────────

    private fun connectIsoDepTag(tag: Tag) {
        try {
            val isodep = IsoDep.get(tag)
            if (isodep == null) {
                nfcPendingIsoDep = false
                runOnUiThread {
                    nfcChannel?.invokeMethod("onNfcError", mapOf("error" to "Tag does not support IsoDep"))
                }
                return
            }
            isodep.connect()
            nfcIsoDep = isodep
            nfcPendingIsoDep = false
            val histBytes = isodep.historicalBytes?.let { bytesToHex(it) } ?: ""
            val uid = tag.id.joinToString("") { "%02x".format(it) }
            runOnUiThread {
                nfcChannel?.invokeMethod("onIsoDepConnected", mapOf(
                    "uid" to uid,
                    "historicalBytes" to histBytes,
                    "tech" to tag.techList.toList()
                ))
            }
        } catch (e: Exception) {
            nfcPendingIsoDep = false
            nfcIsoDep = null
            runOnUiThread {
                nfcChannel?.invokeMethod("onNfcError", mapOf("error" to (e.message ?: "isodep connect failed")))
            }
        }
    }

    private fun disconnectIsoDep() {
        try { nfcIsoDep?.close() } catch (_: Exception) {}
        nfcIsoDep = null
        nfcPendingIsoDep = false
    }

    private fun hexToBytes(hex: String): ByteArray {
        val clean = hex.replace(" ", "").replace("\n", "")
        return clean.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    }

    private fun bytesToHex(bytes: ByteArray): String {
        return bytes.joinToString("") { "%02x".format(it) }
    }

    private fun shareNfcPayload(text: String) {
        try {
            val record = NdefRecord.createTextRecord("en", text)
            val message = NdefMessage(arrayOf(record))
            try {
                val method = NfcAdapter::class.java.getMethod("setNdefPushMessage", NdefMessage::class.java, android.app.Activity::class.java)
                method.invoke(nfcAdapter, message, this)
            } catch (_: NoSuchMethodException) {
                Log.w(TAG, "setNdefPushMessage not available (Android 13+)")
            }
            Log.d(TAG, "NFC share payload set")
        } catch (e: Exception) {
            Log.e(TAG, "NFC share failed: $e")
        }
    }

    private fun stopNfcShare() {
        try {
            try {
                val method = NfcAdapter::class.java.getMethod("setNdefPushMessage", NdefMessage::class.java, android.app.Activity::class.java)
                method.invoke(nfcAdapter, null, this)
            } catch (_: NoSuchMethodException) {
                Log.w(TAG, "setNdefPushMessage not available (Android 13+)")
            }
            Log.d(TAG, "NFC share stopped")
        } catch (e: Exception) {
            Log.e(TAG, "NFC stop share failed: $e")
        }
    }

    // ── Vibrator ──────────────────────────────────────────────────────

    private fun vibrate(durationMs: Long) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vibratorManager.defaultVibrator.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                vibrator.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
            }
            Log.d(TAG, "vibrated for ${durationMs}ms")
        } catch (e: Exception) {
            Log.e(TAG, "vibrate failed: $e")
        }
    }

    // ── Bluetooth ──────────────────────────────────────────────────────

    private fun getBluetoothAdapter(): BluetoothAdapter? {
        if (bluetoothAdapter == null) {
            val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            bluetoothAdapter = manager?.adapter
        }
        return bluetoothAdapter
    }

    private fun getBluetoothPermissions(): Array<String> {
        val permissions = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions.add(android.Manifest.permission.BLUETOOTH_SCAN)
            permissions.add(android.Manifest.permission.BLUETOOTH_CONNECT)
            permissions.add(android.Manifest.permission.ACCESS_FINE_LOCATION)
        } else {
            permissions.add(android.Manifest.permission.ACCESS_FINE_LOCATION)
        }
        return permissions.toTypedArray()
    }

    private fun hasBluetoothPermissions(): Boolean {
        return getBluetoothPermissions().all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun startBluetoothScan(serviceUuids: List<String>?, result: MethodChannel.Result?) {
        bluetoothScanResult = result
        if (hasBluetoothPermissions()) {
            startBluetoothScanInternal()
        } else {
            bluetoothPermissionLauncher.launch(getBluetoothPermissions())
        }
    }

    private fun startBluetoothScanInternal() {
        try {
            val adapter = getBluetoothAdapter() ?: throw Exception("Bluetooth not available")
            if (!adapter.isEnabled) throw Exception("Bluetooth is disabled")
            bluetoothLeScanner = adapter.bluetoothLeScanner
            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build()
            bluetoothLeScanner?.startScan(emptyList(), settings, bluetoothScanCallback)
            Log.d(TAG, "Bluetooth scan started")
            bluetoothScanResult?.success(mapOf("status" to "scanning"))
        } catch (e: Exception) {
            Log.e(TAG, "Bluetooth start scan failed: $e")
            bluetoothScanResult?.error("BLUETOOTH_ERROR", e.message, null)
        } finally {
            bluetoothScanResult = null
        }
    }

    private fun stopBluetoothScan() {
        try {
            bluetoothLeScanner?.stopScan(bluetoothScanCallback)
            bluetoothLeScanner = null
            Log.d(TAG, "Bluetooth scan stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Bluetooth stop scan failed: $e")
        }
    }

    private val bluetoothGattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            Log.d(TAG, "GATT connection state: device=${gatt.device?.address} newState=$newState status=$status")
            if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                Log.d(TAG, "GATT connected, discovering services...")
                gatt.discoverServices()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                val stateMap = mapOf(
                    "deviceId" to (gatt.device?.address ?: ""),
                    "connected" to false
                )
                handler.post {
                    bluetoothChannel?.invokeMethod("onConnectionStateChanged", stateMap)
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                val services = gatt.services
                Log.d(TAG, "GATT services discovered: ${services?.size ?: 0} services")
                services?.forEach { s ->
                    Log.d(TAG, "  Service UUID: ${s.uuid}, characteristics: ${s.characteristics?.size ?: 0}")
                }
                val stateMap = mapOf(
                    "deviceId" to (gatt.device?.address ?: ""),
                    "connected" to true,
                    "servicesReady" to true
                )
                handler.post {
                    bluetoothChannel?.invokeMethod("onConnectionStateChanged", stateMap)
                }
            } else {
                Log.e(TAG, "GATT services discovery failed: status=$status")
                handler.post {
                    bluetoothChannel?.invokeMethod("onBluetoothError", mapOf(
                        "error" to "Services discovery failed: $status"
                    ))
                }
            }
        }

        override fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
            val hexData = value.joinToString("") { "%02x".format(it) }
            val dataMap = mapOf(
                "deviceId" to (gatt.device?.address ?: ""),
                "data" to hexData
            )
            val pending = bluetoothReadResult
            bluetoothReadResult = null
            handler.post {
                if (pending != null) {
                    pending.success(dataMap)
                }
                bluetoothChannel?.invokeMethod("onDataReceived", dataMap)
            }
        }

        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
            val devId = gatt.device?.address ?: ""
            val svcUuid = characteristic.service?.uuid?.toString() ?: ""
            val charUuid = characteristic.uuid.toString()
            val hex = value.joinToString("") { "%02x".format(it) }
            val str = String(value, Charsets.UTF_8)
            Log.d(TAG, "BLE notification from $charUuid: ${value.size} bytes")
            handler.post {
                bluetoothChannel?.invokeMethod("onDataReceived", mapOf(
                    "deviceId" to devId,
                    "serviceUuid" to svcUuid,
                    "characteristicUuid" to charUuid,
                    "data" to hex,
                    "dataString" to str
                ))
            }
        }
    }

    private fun connectBluetoothDevice(deviceId: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
            bluetoothPermissionLauncher.launch(arrayOf(android.Manifest.permission.BLUETOOTH_CONNECT))
            return
        }
        try {
            val adapter = getBluetoothAdapter() ?: throw Exception("Bluetooth not available")
            if (!adapter.isEnabled) throw Exception("Bluetooth is disabled")
            val device = adapter.getRemoteDevice(deviceId)
            val gatt = device.connectGatt(this, false, bluetoothGattCallback)
            bluetoothGattMap[deviceId] = gatt
            Log.d(TAG, "Bluetooth connecting to $deviceId")
        } catch (e: Exception) {
            Log.e(TAG, "Bluetooth connect failed: $e")
        }
    }

    private fun sendBluetoothRaw(deviceId: String, hexData: String) {
        try {
            val gatt = bluetoothGattMap[deviceId] ?: throw Exception("Not connected to $deviceId")
            val allServices = gatt.services
            if (allServices.isNullOrEmpty()) throw Exception("No services discovered yet")
            val service = allServices.firstOrNull() ?: throw Exception("No services found")
            val characteristic = service.characteristics?.firstOrNull() ?: throw Exception("No characteristics found")
            val bytes = hexData.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
            characteristic.setValue(bytes)
            characteristic.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE)
            gatt.writeCharacteristic(characteristic)
            Log.d(TAG, "Bluetooth raw data sent to $deviceId via ${service.uuid}")
        } catch (e: Exception) {
            Log.e(TAG, "Bluetooth send failed: $e")
        }
    }

    private fun findCharacteristic(deviceId: String, serviceUuid: String, characteristicUuid: String): BluetoothGattCharacteristic? {
        val gatt = bluetoothGattMap[deviceId] ?: return null
        val service = if (serviceUuid.isNotBlank()) {
            gatt.services?.firstOrNull { it.uuid.toString().equals(serviceUuid, ignoreCase = true) }
        } else {
            gatt.services?.firstOrNull()
        }
        val characteristic = if (characteristicUuid.isNotBlank() && service != null) {
            service.characteristics?.firstOrNull { it.uuid.toString().equals(characteristicUuid, ignoreCase = true) }
        } else {
            service?.characteristics?.firstOrNull()
        }
        return characteristic
    }

    private fun discoverServices(deviceId: String, result: MethodChannel.Result) {
        try {
            val gatt = bluetoothGattMap[deviceId] ?: throw Exception("Not connected to $deviceId")
            gatt.discoverServices()
            result.success(mapOf("status" to "discovering"))
        } catch (e: Exception) {
            Log.e(TAG, "Bluetooth discover services failed: $e")
            result.error("BLUETOOTH_ERROR", e.message, null)
        }
    }

    private fun setCharacteristicNotification(deviceId: String, serviceUuid: String, characteristicUuid: String, enable: Boolean, result: MethodChannel.Result) {
        try {
            val gatt = bluetoothGattMap[deviceId] ?: throw Exception("Not connected to $deviceId")
            val characteristic = findCharacteristic(deviceId, serviceUuid, characteristicUuid)
                ?: throw Exception("Characteristic not found")
            val cccdUuid = java.util.UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
            val cccd = characteristic.descriptors?.firstOrNull { it.uuid == cccdUuid }
                ?: throw Exception("CCCD descriptor not found")
            gatt.setCharacteristicNotification(characteristic, enable)
            cccd.setValue(if (enable) BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE else BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE)
            gatt.writeDescriptor(cccd)
            Log.d(TAG, "Bluetooth notification ${if (enable) "enabled" else "disabled"} for $deviceId $characteristicUuid")
            result.success(mapOf("status" to if (enable) "subscribed" else "unsubscribed"))
        } catch (e: Exception) {
            Log.e(TAG, "Bluetooth notification set failed: $e")
            result.error("BLUETOOTH_ERROR", e.message, null)
        }
    }

    private fun readCharacteristic(deviceId: String, serviceUuid: String, characteristicUuid: String, result: MethodChannel.Result) {
        try {
            val gatt = bluetoothGattMap[deviceId] ?: throw Exception("Not connected to $deviceId")
            val characteristic = findCharacteristic(deviceId, serviceUuid, characteristicUuid)
                ?: throw Exception("Characteristic not found")
            bluetoothReadResult = result
            gatt.readCharacteristic(characteristic)
            Log.d(TAG, "Bluetooth read characteristic $deviceId $characteristicUuid")
        } catch (e: Exception) {
            bluetoothReadResult = null
            Log.e(TAG, "Bluetooth read failed: $e")
            result.error("BLUETOOTH_ERROR", e.message, null)
        }
    }

    override fun onDestroy() {
        bluetoothGattMap.values.forEach { gatt ->
            try { gatt.disconnect(); gatt.close() } catch (_: Exception) {}
        }
        bluetoothGattMap.clear()
        stopBluetoothScan()
        disconnectIsoDep()
        disableNfcReader()
        stopNfcShare()
        stopGyroscopeListening()
        stopAccelerometerListening()
        handler.removeCallbacksAndMessages(null)
        inputManager?.unregisterInputDeviceListener(this)
        super.onDestroy()
    }
}
