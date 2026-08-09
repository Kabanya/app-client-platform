import 'dart:io';

import 'package:app_voice/app_voice.dart';
import 'package:app_voice/src/recorded_voice_recognizer_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

void main() {
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
