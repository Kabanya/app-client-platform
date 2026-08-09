import 'package:flutter/services.dart';

import 'voice_models.dart';
import 'voice_recognizers.dart';

const systemSpeechChannelName = 'pomodoist/system_speech';

class MethodChannelSystemSpeechTranscriber implements SystemSpeechTranscriber {
  MethodChannelSystemSpeechTranscriber({
    MethodChannel channel = const MethodChannel(systemSpeechChannelName),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<void> prepare({String? locale}) {
    return _invoke(
      () => _channel.invokeMethod<void>('prepare', {'locale': locale}),
    );
  }

  @override
  Future<VoiceRecognitionTranscript> transcribeFile(
    String path, {
    String? locale,
  }) async {
    final response = await _invoke(
      () => _channel.invokeMapMethod<String, Object?>(
        'transcribeFile',
        {'path': path, 'locale': locale},
      ),
    );
    final text = response?['text'];
    if (text is! String || text.trim().isEmpty) {
      throw const VoiceRecognitionException(
        'empty_transcript',
        'System speech recognition returned no text.',
      );
    }
    final confidence = response?['confidence'];
    return VoiceRecognitionTranscript(
      text: text.trim(),
      confidence: confidence is num ? confidence.toDouble() : null,
      raw: response,
    );
  }

  @override
  Future<void> cancel() {
    return _invoke(() => _channel.invokeMethod<void>('cancel'));
  }

  Future<T> _invoke<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on PlatformException catch (error) {
      throw VoiceRecognitionException(
        error.code,
        error.message ?? 'System speech recognition failed.',
      );
    }
  }
}
