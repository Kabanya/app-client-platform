import 'voice_models.dart';
import 'voice_recognizers.dart';

RecordedVoiceRecognizer createRecordedVoiceRecognizer() {
  return const UnsupportedRecordedVoiceRecognizer();
}

class UnsupportedRecordedVoiceRecognizer implements RecordedVoiceRecognizer {
  const UnsupportedRecordedVoiceRecognizer();

  @override
  Future<void> start(VoiceRecognitionConfig config) {
    throw const VoiceRecognitionException(
      'unsupported_platform',
      'Recorded system speech recognition is not supported on this platform.',
    );
  }

  @override
  Future<VoiceRecognitionTranscript> stop(VoiceRecognitionConfig config) {
    throw const VoiceRecognitionException(
      'unsupported_platform',
      'Recorded system speech recognition is not supported on this platform.',
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}
}
