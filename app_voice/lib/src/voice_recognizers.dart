import 'voice_models.dart';

abstract class RecordedVoiceRecognizer {
  Future<void> start(VoiceRecognitionConfig config);

  Future<VoiceRecognitionTranscript> stop(VoiceRecognitionConfig config);

  Future<void> cancel();

  void dispose() {}
}

abstract interface class RecordedVoiceAmplitudeSource {
  Stream<double> get amplitudeDbfs;
}

abstract class SystemSpeechTranscriber {
  Future<void> prepare({String? locale});

  Future<VoiceRecognitionTranscript> transcribeFile(
    String path, {
    String? locale,
  });

  Future<void> cancel();
}
