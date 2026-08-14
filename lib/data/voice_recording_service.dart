import 'dart:async';
import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class AmplitudeLevel {
  final double current;
  final double max;
  const AmplitudeLevel({this.current = -160, this.max = -160});
}

class VoiceRecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  DateTime? _startTime;
  Timer? _timer;

  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();
  Stream<Duration> get durationStream => _durationController.stream;

  StreamSubscription<Amplitude>? _ampSub;
  final StreamController<AmplitudeLevel> _amplitudeController =
      StreamController<AmplitudeLevel>.broadcast();
  Stream<AmplitudeLevel> get amplitudeStream => _amplitudeController.stream;

  bool get isRecording => _isRecording;
  Duration get currentDuration =>
      _startTime != null ? DateTime.now().difference(_startTime!) : Duration.zero;

  Future<bool> _requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> startRecording() async {
    if (_isRecording) return false;

    if (!await _requestPermission()) return false;

    final dir = await getTemporaryDirectory();
    final filePath =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    const config = RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 128000,
      sampleRate: 44100,
    );

    await _recorder.start(config, path: filePath);
    _isRecording = true;
    _startTime = DateTime.now();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_startTime != null) {
        _durationController.add(currentDuration);
      }
    });

    _ampSub?.cancel();
    _ampSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 80)).listen(
      (amp) {
        _amplitudeController.add(AmplitudeLevel(
          current: amp.current,
          max: amp.max,
        ));
      },
    );

    return true;
  }

  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    _timer?.cancel();
    _timer = null;
    _ampSub?.cancel();
    _ampSub = null;
    _isRecording = false;

    final path = await _recorder.stop();
    _startTime = null;
    _durationController.add(Duration.zero);

    return path;
  }

  Future<void> cancelRecording() async {
    if (!_isRecording) return;

    _timer?.cancel();
    _timer = null;
    _ampSub?.cancel();
    _ampSub = null;
    _isRecording = false;

    await _recorder.stop();

    final dir = await getTemporaryDirectory();
    final files = dir.listSync().whereType<File>().where(
        (f) => f.path.contains('voice_') && f.path.endsWith('.m4a'));
    for (final f in files) {
      await f.delete();
    }

    _startTime = null;
    _durationController.add(Duration.zero);
  }

  static String formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void dispose() {
    _timer?.cancel();
    _ampSub?.cancel();
    _durationController.close();
    _amplitudeController.close();
    _recorder.dispose();
  }
}
