import 'dart:async';

import 'package:app_voice/app_voice.dart';
import 'package:app_voice/src/recorded_voice_recognizer_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

void main() {
  test('recorded system mode emits final transcript on stop', () async {
    final controller = VoiceRecognitionController(
      recordedRecognizer: _FakeRecordedRecognizer(
        transcript: const VoiceRecognitionTranscript(text: 'review roadmap'),
      ),
      platformSupport: const VoicePlatformSupport(
        supportsRecordedSystem: true,
      ),
    );
    final events = <VoiceRecognitionEvent>[];
    final subscription = controller
        .start(const VoiceRecognitionConfig(locale: 'en-US'))
        .listen(events.add);

    await pumpEventQueue();
    await controller.stop();
    await subscription.cancel();

    expect(
      events.map((event) => event.status),
      [
        VoiceRecognitionStatus.requestingPermission,
        VoiceRecognitionStatus.recording,
        VoiceRecognitionStatus.transcribing,
        VoiceRecognitionStatus.completed,
      ],
    );
    expect(events.last.finalText, 'review roadmap');
  });

  test('stop waits for an in-flight start before stopping the recorder',
      () async {
    final recognizer = _DelayedRecordedRecognizer();
    final controller = VoiceRecognitionController(
      recordedRecognizer: recognizer,
      platformSupport: const VoicePlatformSupport(
        supportsRecordedSystem: true,
      ),
    );
    final subscription =
        controller.start(const VoiceRecognitionConfig()).listen((_) {});

    await recognizer.startEntered.future;
    final stopping = controller.stop();
    await pumpEventQueue();
    expect(recognizer.stopCalls, 0);

    recognizer.allowStart.complete();
    await stopping;
    await subscription.cancel();

    expect(recognizer.stopCalls, 1);
  });

  test('cancel waits for start and closes the session exactly once', () async {
    final recognizer = _DelayedRecordedRecognizer();
    final controller = VoiceRecognitionController(
      recordedRecognizer: recognizer,
      platformSupport: const VoicePlatformSupport(
        supportsRecordedSystem: true,
      ),
    );
    final events = <VoiceRecognitionEvent>[];
    final subscription =
        controller.start(const VoiceRecognitionConfig()).listen(events.add);

    await recognizer.startEntered.future;
    final firstCancel = controller.cancel();
    final secondCancel = controller.cancel();
    await pumpEventQueue();
    expect(recognizer.cancelCalls, 0);

    recognizer.allowStart.complete();
    await Future.wait([firstCancel, secondCancel]);
    await subscription.cancel();

    expect(recognizer.cancelCalls, 1);
    expect(
      events.where((event) => event.status == VoiceRecognitionStatus.canceled),
      hasLength(1),
    );
  });

  test('max duration stops and transcribes once', () async {
    final recognizer = _FakeRecordedRecognizer();
    final controller = VoiceRecognitionController(
      recordedRecognizer: recognizer,
      platformSupport: const VoicePlatformSupport(
        supportsRecordedSystem: true,
      ),
    );

    final events = await controller
        .start(
          const VoiceRecognitionConfig(
            maxDuration: Duration(milliseconds: 5),
          ),
        )
        .toList();

    expect(recognizer.stopCalls, 1);
    expect(events.last.status, VoiceRecognitionStatus.completed);
  });

  test('cancel interrupts an in-flight transcription', () async {
    final recognizer = _BlockingRecordedRecognizer();
    final controller = VoiceRecognitionController(
      recordedRecognizer: recognizer,
      platformSupport: const VoicePlatformSupport(
        supportsRecordedSystem: true,
      ),
    );
    final eventsFuture =
        controller.start(const VoiceRecognitionConfig()).toList();

    await recognizer.started.future;
    final stopping = controller.stop();
    await recognizer.stopEntered.future;
    await controller.cancel();
    await stopping;
    final events = await eventsFuture;

    expect(recognizer.cancelCalls, 1);
    expect(
      events.where((event) => event.status == VoiceRecognitionStatus.canceled),
      hasLength(1),
    );
    expect(
      events.where((event) => event.status == VoiceRecognitionStatus.error),
      isEmpty,
    );
  });

  test('can start a new session after a recognition error', () async {
    final recognizer = _FailOnceRecordedRecognizer();
    final controller = VoiceRecognitionController(
      recordedRecognizer: recognizer,
      platformSupport: const VoicePlatformSupport(
        supportsRecordedSystem: true,
      ),
    );

    final firstEvents =
        controller.start(const VoiceRecognitionConfig()).toList();
    await pumpEventQueue();
    await controller.stop();
    expect(
      (await firstEvents).last.status,
      VoiceRecognitionStatus.error,
    );

    final secondEvents =
        controller.start(const VoiceRecognitionConfig()).toList();
    await pumpEventQueue();
    await controller.stop();

    expect((await secondEvents).last.finalText, 'second attempt');
  });

  test('a stale transcription cannot affect the current session', () async {
    final recognizer = _QueuedRecordedRecognizer();
    final controller = VoiceRecognitionController(
      recordedRecognizer: recognizer,
      platformSupport: const VoicePlatformSupport(
        supportsRecordedSystem: true,
      ),
    );

    final firstEvents =
        controller.start(const VoiceRecognitionConfig()).toList();
    await pumpEventQueue();
    final firstStop = controller.stop();
    await recognizer.stopEntered(0);
    await controller.cancel();
    await firstEvents;

    final secondEvents =
        controller.start(const VoiceRecognitionConfig()).toList();
    await pumpEventQueue();
    final secondStop = controller.stop();
    await recognizer.stopEntered(1);

    recognizer.completeStop(0, 'stale');
    await firstStop;
    await pumpEventQueue();
    await controller.cancel();
    await secondStop;
    final events = await secondEvents;

    expect(recognizer.cancelCalls, 2);
    expect(
      events.where((event) => event.status == VoiceRecognitionStatus.completed),
      isEmpty,
    );
    expect(events.last.status, VoiceRecognitionStatus.canceled);
  });

  test('unsupported platform returns unsupported event without starting',
      () async {
    final recognizer = _FakeRecordedRecognizer();
    final controller = VoiceRecognitionController(
      recordedRecognizer: recognizer,
      platformSupport: const VoicePlatformSupport(
        supportsRecordedSystem: false,
      ),
    );

    final events =
        await controller.start(const VoiceRecognitionConfig()).toList();

    expect(events.single.status, VoiceRecognitionStatus.unsupportedPlatform);
    expect(recognizer.started, isFalse);
  });

  test('prefers built-in microphone from input devices', () {
    final builtIn = selectBuiltInInputDevice(const <InputDevice>[
      InputDevice(id: 'airpods', label: 'AirPods Pro'),
      InputDevice(id: 'macbook', label: 'MacBook Pro Microphone'),
    ]);

    expect(builtIn?.id, 'macbook');
  });
}

class _FakeRecordedRecognizer implements RecordedVoiceRecognizer {
  _FakeRecordedRecognizer({
    this.transcript = const VoiceRecognitionTranscript(text: 'transcript'),
  });

  final VoiceRecognitionTranscript transcript;
  bool started = false;
  var stopCalls = 0;
  var cancelCalls = 0;

  @override
  Future<void> start(VoiceRecognitionConfig config) async {
    started = true;
  }

  @override
  Future<VoiceRecognitionTranscript> stop(VoiceRecognitionConfig config) async {
    stopCalls += 1;
    return transcript;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
  }

  @override
  void dispose() {}
}

class _DelayedRecordedRecognizer implements RecordedVoiceRecognizer {
  final startEntered = Completer<void>();
  final allowStart = Completer<void>();
  var stopCalls = 0;
  var cancelCalls = 0;

  @override
  Future<void> start(VoiceRecognitionConfig config) async {
    startEntered.complete();
    await allowStart.future;
  }

  @override
  Future<VoiceRecognitionTranscript> stop(VoiceRecognitionConfig config) async {
    stopCalls += 1;
    return const VoiceRecognitionTranscript(text: 'done');
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
  }

  @override
  void dispose() {}
}

class _BlockingRecordedRecognizer implements RecordedVoiceRecognizer {
  final started = Completer<void>();
  final stopEntered = Completer<void>();
  final transcript = Completer<VoiceRecognitionTranscript>();
  var cancelCalls = 0;

  @override
  Future<void> start(VoiceRecognitionConfig config) async {
    started.complete();
  }

  @override
  Future<VoiceRecognitionTranscript> stop(VoiceRecognitionConfig config) {
    stopEntered.complete();
    return transcript.future;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    if (!transcript.isCompleted) {
      transcript.completeError(
        const VoiceRecognitionException('speech_canceled', 'Canceled.'),
      );
    }
  }

  @override
  void dispose() {}
}

class _FailOnceRecordedRecognizer implements RecordedVoiceRecognizer {
  var stopCalls = 0;

  @override
  Future<void> start(VoiceRecognitionConfig config) async {}

  @override
  Future<VoiceRecognitionTranscript> stop(VoiceRecognitionConfig config) async {
    stopCalls += 1;
    if (stopCalls == 1) {
      throw const VoiceRecognitionException(
        'recognition_failed',
        'Recognition failed.',
      );
    }
    return const VoiceRecognitionTranscript(text: 'second attempt');
  }

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}
}

class _QueuedRecordedRecognizer implements RecordedVoiceRecognizer {
  final _stopEntered = <Completer<void>>[];
  final _stops = <Completer<VoiceRecognitionTranscript>>[];
  var cancelCalls = 0;

  Future<void> stopEntered(int index) async {
    while (_stopEntered.length <= index) {
      await pumpEventQueue();
    }
    await _stopEntered[index].future;
  }

  void completeStop(int index, String text) {
    _stops[index].complete(VoiceRecognitionTranscript(text: text));
  }

  @override
  Future<void> start(VoiceRecognitionConfig config) async {}

  @override
  Future<VoiceRecognitionTranscript> stop(VoiceRecognitionConfig config) {
    final entered = Completer<void>()..complete();
    final stop = Completer<VoiceRecognitionTranscript>();
    _stopEntered.add(entered);
    _stops.add(stop);
    return stop.future;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    if (cancelCalls > 1 && _stops.length > 1 && !_stops[1].isCompleted) {
      _stops[1].completeError(
        const VoiceRecognitionException('speech_canceled', 'Canceled.'),
      );
    }
  }

  @override
  void dispose() {}
}
