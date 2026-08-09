enum VoiceRecognitionStatus {
  idle,
  requestingPermission,
  recording,
  transcribing,
  completed,
  canceled,
  error,
  unsupportedPlatform,
}

class VoiceRecognitionConfig {
  const VoiceRecognitionConfig({
    this.locale,
    this.maxDuration = const Duration(seconds: 59),
  });

  final String? locale;
  final Duration maxDuration;
}

class VoiceRecognitionError {
  const VoiceRecognitionError({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() => message;
}

class VoiceRecognitionException implements Exception {
  const VoiceRecognitionException(this.code, this.message);

  final String code;
  final String message;

  VoiceRecognitionError toError() {
    return VoiceRecognitionError(code: code, message: message);
  }

  @override
  String toString() => message;
}

class VoiceRecognitionTranscript {
  const VoiceRecognitionTranscript({
    required this.text,
    this.confidence,
    this.raw,
  });

  final String text;
  final double? confidence;
  final Object? raw;
}

class VoiceRecognitionEvent {
  const VoiceRecognitionEvent({
    required this.status,
    this.finalText,
    this.confidence,
    this.error,
  });

  final VoiceRecognitionStatus status;
  final String? finalText;
  final double? confidence;
  final VoiceRecognitionError? error;

  String get text => finalText ?? '';

  static const idle = VoiceRecognitionEvent(
    status: VoiceRecognitionStatus.idle,
  );

  static const requestingPermission = VoiceRecognitionEvent(
    status: VoiceRecognitionStatus.requestingPermission,
  );

  static const recording = VoiceRecognitionEvent(
    status: VoiceRecognitionStatus.recording,
  );

  static const transcribing = VoiceRecognitionEvent(
    status: VoiceRecognitionStatus.transcribing,
  );

  static const canceled = VoiceRecognitionEvent(
    status: VoiceRecognitionStatus.canceled,
  );

  factory VoiceRecognitionEvent.completed({
    required String text,
    double? confidence,
  }) {
    return VoiceRecognitionEvent(
      status: VoiceRecognitionStatus.completed,
      finalText: text,
      confidence: confidence,
    );
  }

  factory VoiceRecognitionEvent.error(VoiceRecognitionError error) {
    return VoiceRecognitionEvent(
      status: VoiceRecognitionStatus.error,
      error: error,
    );
  }

  factory VoiceRecognitionEvent.unsupportedPlatform(String message) {
    return VoiceRecognitionEvent(
      status: VoiceRecognitionStatus.unsupportedPlatform,
      error: VoiceRecognitionError(
        code: 'unsupported_platform',
        message: message,
      ),
    );
  }
}
