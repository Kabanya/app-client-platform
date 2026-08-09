import 'dart:async';

import 'recorded_voice_recognizer.dart';
import 'voice_models.dart';
import 'voice_platform_support.dart';
import 'voice_recognizers.dart';

class VoiceRecognitionController {
  VoiceRecognitionController({
    RecordedVoiceRecognizer? recordedRecognizer,
    VoicePlatformSupport platformSupport = const VoicePlatformSupport(),
  })  : _recordedRecognizer =
            recordedRecognizer ?? createRecordedVoiceRecognizer(),
        _platformSupport = platformSupport;

  final RecordedVoiceRecognizer _recordedRecognizer;
  final VoicePlatformSupport _platformSupport;

  StreamController<VoiceRecognitionEvent>? _events;
  VoiceRecognitionConfig? _activeConfig;
  Future<void>? _startFuture;
  Future<void>? _ending;
  Future<void>? _canceling;
  Timer? _maxDurationTimer;
  var _cancelRequested = false;
  int? _transcribingSession;
  var _session = 0;

  Stream<double> get amplitudeDbfs {
    final recognizer = _recordedRecognizer;
    return recognizer is RecordedVoiceAmplitudeSource
        ? (recognizer as RecordedVoiceAmplitudeSource).amplitudeDbfs
        : const Stream<double>.empty();
  }

  Stream<VoiceRecognitionEvent> start(VoiceRecognitionConfig config) {
    if (_activeConfig != null) {
      throw StateError('Voice recognition is already active.');
    }
    final session = ++_session;
    _cancelRequested = false;
    _transcribingSession = null;
    final events = StreamController<VoiceRecognitionEvent>();
    _events = events;
    _activeConfig = config;
    final startFuture = _start(config, session);
    _startFuture = startFuture;
    unawaited(
      startFuture.whenComplete(() {
        if (session == _session && identical(_startFuture, startFuture)) {
          _startFuture = null;
        }
      }),
    );
    return events.stream;
  }

  Future<void> stop() => _end(cancel: false);

  Future<void> cancel() {
    final existing = _ending;
    if (existing == null) {
      return _end(cancel: true);
    }
    if (_cancelRequested) {
      return _canceling ?? existing;
    }
    _cancelRequested = true;
    if (_transcribingSession != _session) {
      return existing;
    }
    final session = _session;
    final canceling = _interruptTranscription(session);
    _canceling = canceling;
    return canceling.whenComplete(() {
      if (identical(_canceling, canceling)) {
        _canceling = null;
      }
    });
  }

  Future<void> _end({required bool cancel}) {
    final existing = _ending;
    if (existing != null) {
      return existing;
    }
    final config = _activeConfig;
    if (config == null) {
      return Future<void>.value();
    }
    if (cancel) {
      _cancelRequested = true;
    }
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    final session = _session;
    final ending = _finish(config, session, cancel: cancel);
    _ending = ending;
    return ending.whenComplete(() {
      if (identical(_ending, ending)) {
        _ending = null;
      }
    });
  }

  void dispose() {
    final ending = cancel();
    unawaited(ending.whenComplete(_recordedRecognizer.dispose));
  }

  Future<void> _start(VoiceRecognitionConfig config, int session) async {
    try {
      if (!_platformSupport.supportsRecordedSystem) {
        _add(
          VoiceRecognitionEvent.unsupportedPlatform(
            'Recorded system speech recognition is available on iOS and macOS.',
          ),
          session,
        );
        await _close(session);
        return;
      }
      _add(VoiceRecognitionEvent.requestingPermission, session);
      await _recordedRecognizer.start(config);
      if (!_isCurrent(session) || _ending != null) {
        return;
      }
      _add(VoiceRecognitionEvent.recording, session);
      _maxDurationTimer = Timer(config.maxDuration, () {
        unawaited(stop());
      });
    } catch (error) {
      await _fail(error, session);
    }
  }

  Future<void> _finish(
    VoiceRecognitionConfig config,
    int session, {
    required bool cancel,
  }) async {
    try {
      await _startFuture;
      if (!_isCurrent(session)) {
        return;
      }
      if (cancel || _cancelRequested) {
        await _recordedRecognizer.cancel();
        _add(VoiceRecognitionEvent.canceled, session);
      } else {
        _transcribingSession = session;
        _add(VoiceRecognitionEvent.transcribing, session);
        late final VoiceRecognitionTranscript transcript;
        try {
          transcript = await _recordedRecognizer.stop(config);
        } finally {
          if (_transcribingSession == session) {
            _transcribingSession = null;
          }
        }
        if (!_isCurrent(session)) {
          return;
        }
        if (transcript.text.trim().isEmpty) {
          _add(VoiceRecognitionEvent.canceled, session);
        } else {
          _add(
            VoiceRecognitionEvent.completed(
              text: transcript.text,
              confidence: transcript.confidence,
            ),
            session,
          );
        }
      }
      await _close(session);
    } catch (error) {
      if (_cancelRequested && _isCurrent(session)) {
        _add(VoiceRecognitionEvent.canceled, session);
        await _close(session);
      } else {
        await _fail(error, session);
      }
    }
  }

  Future<void> _interruptTranscription(int session) async {
    try {
      await _recordedRecognizer.cancel();
      if (_isCurrent(session)) {
        _add(VoiceRecognitionEvent.canceled, session);
        await _close(session);
      }
    } catch (error) {
      await _fail(error, session);
    }
  }

  bool _isCurrent(int session) => session == _session && _activeConfig != null;

  void _add(VoiceRecognitionEvent event, int session) {
    final events = _events;
    if (!_isCurrent(session) || events == null || events.isClosed) {
      return;
    }
    events.add(event);
  }

  Future<void> _fail(Object error, int session) async {
    if (!_isCurrent(session)) {
      return;
    }
    try {
      await _recordedRecognizer.cancel();
    } catch (_) {}
    final voiceError = error is VoiceRecognitionException
        ? error.toError()
        : VoiceRecognitionError(code: 'voice_error', message: error.toString());
    _add(VoiceRecognitionEvent.error(voiceError), session);
    await _close(session);
  }

  Future<void> _close(int session) async {
    if (session != _session) {
      return;
    }
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    _activeConfig = null;
    _startFuture = null;
    _ending = null;
    _canceling = null;
    _cancelRequested = false;
    if (_transcribingSession == session) {
      _transcribingSession = null;
    }
    final events = _events;
    _events = null;
    if (events != null && !events.isClosed) {
      await events.close();
    }
  }
}
