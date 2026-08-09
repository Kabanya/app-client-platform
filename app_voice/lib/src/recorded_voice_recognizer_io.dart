import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'system_speech_transcriber.dart';
import 'voice_models.dart';
import 'voice_recognizers.dart';

RecordedVoiceRecognizer createRecordedVoiceRecognizer() {
  return RecordFileVoiceRecognizer();
}

class RecordFileVoiceRecognizer
    implements RecordedVoiceRecognizer, RecordedVoiceAmplitudeSource {
  RecordFileVoiceRecognizer({
    AudioRecorder? recorder,
    SystemSpeechTranscriber? transcriber,
  })  : _recorder = recorder ?? AudioRecorder(),
        _transcriber = transcriber ?? MethodChannelSystemSpeechTranscriber();

  final AudioRecorder _recorder;
  final SystemSpeechTranscriber _transcriber;
  String? _path;

  @override
  Stream<double> get amplitudeDbfs => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 100))
      .map((amplitude) => amplitude.current);

  @override
  Future<void> start(VoiceRecognitionConfig config) async {
    await _transcriber.prepare(locale: config.locale);
    if (!await _recorder.hasPermission()) {
      throw const VoiceRecognitionException(
        'permission_denied',
        'Microphone permission was not granted.',
      );
    }
    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/app_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    _path = path;
    final device = selectBuiltInInputDevice(
      await _recorder.listInputDevices(),
    );
    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        device: device,
      ),
      path: path,
    );
  }

  @override
  Future<VoiceRecognitionTranscript> stop(VoiceRecognitionConfig config) async {
    final stoppedPath = await _recorder.stop();
    final path = stoppedPath ?? _path;
    _path = null;
    if (path == null) {
      throw const VoiceRecognitionException(
        'empty_recording',
        'No recorded audio was produced.',
      );
    }
    try {
      final file = File(path);
      if (!await file.exists() || await file.length() == 0) {
        throw const VoiceRecognitionException(
          'empty_recording',
          'No recorded audio was produced.',
        );
      }
      return await _transcriber.transcribeFile(
        path,
        locale: config.locale,
      );
    } finally {
      await _deleteIfExists(path);
    }
  }

  @override
  Future<void> cancel() async {
    final path = _path;
    _path = null;
    try {
      await _transcriber.cancel();
    } finally {
      try {
        await _recorder.cancel();
      } finally {
        if (path != null) {
          await _deleteIfExists(path);
        }
      }
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
  }
}

Future<void> _deleteIfExists(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}

InputDevice? selectBuiltInInputDevice(List<InputDevice> devices) {
  for (final device in devices) {
    final label = device.label.toLowerCase();
    if (label.contains('built-in') ||
        label.contains('built in') ||
        label.contains('internal') ||
        label.contains('macbook')) {
      return device;
    }
  }
  return null;
}
