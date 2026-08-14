import 'dart:io';

import 'package:app_voice/app_voice.dart';
import 'package:app_voice/src/recorded_voice_recognizer_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  test('records Apple speech input as mono 16 kHz WAV', () async {
    final directory = await Directory.systemTemp.createTemp('app_voice_test_');
    addTearDown(() => directory.delete(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (_) async {
      return directory.path;
    });
    final recorder = _CapturingAudioRecorder();
    final recognizer = RecordFileVoiceRecognizer(
      recorder: recorder,
      transcriber: _PreparedTranscriber(),
    );

    await recognizer.start(
      const VoiceRecognitionConfig(locale: 'ru-RU'),
    );

    expect(recorder.path, endsWith('.wav'));
    expect(recorder.config?.encoder, AudioEncoder.wav);
    expect(recorder.config?.sampleRate, 16000);
    expect(recorder.config?.numChannels, 1);
  });

  test('exposes recorder amplitude as dBFS', () async {
    final recognizer = RecordFileVoiceRecognizer(
      recorder: _AmplitudeAudioRecorder(),
    );

    await expectLater(recognizer.amplitudeDbfs, emits(-24));
  });

  test('deletes the temporary recording when transcription fails', () async {
    final directory = await Directory.systemTemp.createTemp('app_voice_test_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/recording.m4a');
    await file.writeAsBytes([1, 2, 3]);
    final recognizer = RecordFileVoiceRecognizer(
      recorder: _StoppedAudioRecorder(file.path),
      transcriber: _FailingTranscriber(),
    );

    await expectLater(
      recognizer.stop(const VoiceRecognitionConfig(locale: 'en-US')),
      throwsA(isA<VoiceRecognitionException>()),
    );

    expect(await file.exists(), isFalse);
  });
}

class _CapturingAudioRecorder implements AudioRecorder {
  RecordConfig? config;
  String? path;

  @override
  Future<bool> hasPermission({bool request = true}) async => true;

  @override
  Future<List<InputDevice>> listInputDevices() async => const [];

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    this.config = config;
    this.path = path;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AmplitudeAudioRecorder implements AudioRecorder {
  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) =>
      Stream.value(Amplitude(current: -24, max: -8));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StoppedAudioRecorder implements AudioRecorder {
  _StoppedAudioRecorder(this.path);

  final String path;

  @override
  Future<String?> stop() async => path;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingTranscriber implements SystemSpeechTranscriber {
  @override
  Future<void> prepare({String? locale}) async {}

  @override
  Future<VoiceRecognitionTranscript> transcribeFile(
    String path, {
    String? locale,
  }) {
    throw const VoiceRecognitionException(
      'recognition_failed',
      'Recognition failed.',
    );
  }

  @override
  Future<void> cancel() async {}
}

class _PreparedTranscriber implements SystemSpeechTranscriber {
  @override
  Future<void> prepare({String? locale}) async {}

  @override
  Future<VoiceRecognitionTranscript> transcribeFile(
    String path, {
    String? locale,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> cancel() async {}
}
