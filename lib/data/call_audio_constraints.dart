/// Microphone constraints shared by every NajiMe call path.
///
/// flutter_webrtc's native WebRTC SDK is built with RNNoise support. The
/// standard and `goog*` constraints below explicitly enable its audio
/// processing pipeline instead of relying on platform defaults.
const Map<String, dynamic> najimeCallAudioConstraints = {
  'echoCancellation': true,
  'noiseSuppression': true,
  'autoGainControl': true,
  'channelCount': 1,
  'sampleRate': 48000,
  'sampleSize': 16,
  'googEchoCancellation': true,
  'googEchoCancellation2': true,
  'googDAEchoCancellation': true,
  'googNoiseSuppression': true,
  'googNoiseSuppression2': true,
  'googAutoGainControl': true,
  'googAutoGainControl2': true,
  'googHighpassFilter': true,
  'googTypingNoiseDetection': true,
};
