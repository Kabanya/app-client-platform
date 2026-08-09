import 'package:flutter/foundation.dart';

class VoicePlatformSupport {
  const VoicePlatformSupport({
    bool? supportsRecordedSystem,
  }) : _supportsRecordedSystem = supportsRecordedSystem;

  final bool? _supportsRecordedSystem;

  bool get supportsRecordedSystem => _supportsRecordedSystem ?? _isAppleRuntime;

  bool get _isAppleRuntime {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }
}
