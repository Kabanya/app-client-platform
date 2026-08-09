import 'package:app_voice/app_voice.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(systemSpeechChannelName);

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('uses the recorded system speech channel contract', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'transcribeFile') {
        return <String, Object?>{
          'text': '  Купить молоко  ',
          'confidence': .82,
        };
      }
      return null;
    });
    final transcriber = MethodChannelSystemSpeechTranscriber();

    await transcriber.prepare(locale: 'ru-RU');
    final transcript = await transcriber.transcribeFile(
      '/tmp/voice.m4a',
      locale: 'ru-RU',
    );
    await transcriber.cancel();

    expect(calls.map((call) => call.method), [
      'prepare',
      'transcribeFile',
      'cancel',
    ]);
    expect(calls[0].arguments, {'locale': 'ru-RU'});
    expect(calls[1].arguments, {
      'path': '/tmp/voice.m4a',
      'locale': 'ru-RU',
    });
    expect(transcript.text, 'Купить молоко');
    expect(transcript.confidence, .82);
  });

  test('rejects an empty system transcript', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (_) async => <String, Object?>{'text': '   '},
    );

    expect(
      () => MethodChannelSystemSpeechTranscriber().transcribeFile(
        '/tmp/voice.m4a',
      ),
      throwsA(
        isA<VoiceRecognitionException>().having(
          (error) => error.code,
          'code',
          'empty_transcript',
        ),
      ),
    );
  });

  test('preserves native speech error codes', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (_) => throw PlatformException(
        code: 'speech_permission_denied',
        message: 'Speech permission was denied.',
      ),
    );

    expect(
      () => MethodChannelSystemSpeechTranscriber().prepare(locale: 'en-US'),
      throwsA(
        isA<VoiceRecognitionException>().having(
          (error) => error.code,
          'code',
          'speech_permission_denied',
        ),
      ),
    );
  });
}
