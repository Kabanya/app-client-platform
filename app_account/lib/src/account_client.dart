import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_models.dart';
import 'sync_models.dart';

bool isEmailConfirmationRequired(Object error) =>
    error is AuthException && error.code == ErrorCode.emailNotConfirmed.code;

Future<AuthorizationCredentialAppleID> _requestAppleCredential(
  String hashedNonce,
) {
  return SignInWithApple.getAppleIDCredential(
    scopes: const [
      AppleIDAuthorizationScopes.email,
      AppleIDAuthorizationScopes.fullName,
    ],
    nonce: hashedNonce,
  );
}

Future<AccountClient?> initializeAccountClientIfConfigured({
  required String supabaseUrl,
  required String supabaseAnonKey,
}) async {
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    return null;
  }
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  return AccountClient._(
    Supabase.instance.client,
    authBaseUrl: Uri.parse(supabaseUrl).resolve('/auth/v1'),
  );
}

class AccountClient {
  AccountClient._(
    SupabaseClient supabase, {
    Uri? authBaseUrl,
    http.Client? oauthHttpClient,
    bool? nativeAppleSignIn,
    Future<AuthorizationCredentialAppleID> Function(String hashedNonce)?
        appleCredentialProvider,
    Future<void> Function(String? redirectTo)? appleBrowserSignIn,
    Future<void> Function(String? redirectTo, LaunchMode launchMode)?
        googleBrowserSignIn,
  })  : _supabase = supabase,
        _authBaseUrl = authBaseUrl,
        _oauthHttpClient = oauthHttpClient,
        _nativeAppleSignIn = nativeAppleSignIn,
        _appleCredentialProvider =
            appleCredentialProvider ?? _requestAppleCredential,
        _appleBrowserSignIn = appleBrowserSignIn ??
            ((redirectTo) async {
              await supabase.auth.signInWithOAuth(
                OAuthProvider.apple,
                redirectTo: redirectTo,
              );
            }),
        _googleBrowserSignIn = googleBrowserSignIn ??
            ((redirectTo, launchMode) async {
              final launched = await supabase.auth.signInWithOAuth(
                OAuthProvider.google,
                redirectTo: redirectTo,
                authScreenLaunchMode: launchMode,
              );
              if (!launched) {
                throw const AuthException('Could not open Google sign in.');
              }
            });

  @visibleForTesting
  factory AccountClient.fromSupabaseClient(
    SupabaseClient supabase, {
    Uri? authBaseUrl,
    http.Client? oauthHttpClient,
    bool? nativeAppleSignIn,
    Future<AuthorizationCredentialAppleID> Function(String hashedNonce)?
        appleCredentialProvider,
    Future<void> Function(String? redirectTo)? appleBrowserSignIn,
    Future<void> Function(String? redirectTo, LaunchMode launchMode)?
        googleBrowserSignIn,
  }) {
    return AccountClient._(
      supabase,
      authBaseUrl: authBaseUrl,
      oauthHttpClient: oauthHttpClient,
      nativeAppleSignIn: nativeAppleSignIn,
      appleCredentialProvider: appleCredentialProvider,
      appleBrowserSignIn: appleBrowserSignIn,
      googleBrowserSignIn: googleBrowserSignIn,
    );
  }

  final SupabaseClient _supabase;
  final Uri? _authBaseUrl;
  final http.Client? _oauthHttpClient;
  final bool? _nativeAppleSignIn;
  final Future<AuthorizationCredentialAppleID> Function(String hashedNonce)
      _appleCredentialProvider;
  final Future<void> Function(String? redirectTo) _appleBrowserSignIn;
  final Future<void> Function(String? redirectTo, LaunchMode launchMode)
      _googleBrowserSignIn;

  String? get currentUserId => _supabase.auth.currentUser?.id;
  String? get currentEmail => _supabase.auth.currentUser?.email;
  AccountSession? get currentSession =>
      _accountSession(_supabase.auth.currentSession);

  Stream<AccountAuthState> accountAuthStateChanges() {
    return _supabase.auth.onAuthStateChange.map(
      (event) => AccountAuthState(
        signedIn: event.session != null,
        session: _accountSession(event.session),
      ),
    );
  }

  Stream<bool> authStateChanges() {
    return _supabase.auth.onAuthStateChange.map(
      (event) => event.session != null,
    );
  }

  Future<void> signInWithApple({String? redirectTo}) async {
    if (!_usesNativeAppleSignIn) {
      await _appleBrowserSignIn(redirectTo);
      return;
    }

    final rawNonce = _supabase.auth.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    late final AuthorizationCredentialAppleID credential;
    try {
      credential = await _appleCredentialProvider(hashedNonce);
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        return;
      }
      rethrow;
    }

    final identityToken = credential.identityToken;
    if (identityToken == null || identityToken.isEmpty) {
      throw const AuthException('Apple did not return an identity token.');
    }

    await _supabase.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: identityToken,
      nonce: rawNonce,
    );

    final givenName = credential.givenName?.trim() ?? '';
    final familyName = credential.familyName?.trim() ?? '';
    final fullName = [givenName, familyName]
        .where((component) => component.isNotEmpty)
        .join(' ');
    final metadata = <String, String>{
      if (fullName.isNotEmpty) 'full_name': fullName,
      if (givenName.isNotEmpty) 'given_name': givenName,
      if (familyName.isNotEmpty) 'family_name': familyName,
    };
    if (metadata.isEmpty) {
      return;
    }

    try {
      await _supabase.auth.updateUser(UserAttributes(data: metadata));
    } on AuthException {
      // The authenticated session is valid even if optional name storage fails.
    }
  }

  bool get _usesNativeAppleSignIn {
    final override = _nativeAppleSignIn;
    if (override != null) {
      return override;
    }
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  Future<void> signInWithGoogle({String? redirectTo}) {
    return _googleBrowserSignIn(
      redirectTo,
      kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
  }

  Future<void> signInWithEmail(
    String email, {
    String? redirectTo,
    String? captchaToken,
  }) {
    return _supabase.auth.signInWithOtp(
      email: email,
      emailRedirectTo: redirectTo,
      captchaToken: captchaToken,
    );
  }

  Future<void> signInWithPassword({
    required String email,
    required String password,
    String? captchaToken,
  }) async {
    await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
      captchaToken: captchaToken,
    );
  }

  Future<void> signUpWithPassword({
    required String email,
    required String password,
    String? redirectTo,
    String? captchaToken,
  }) async {
    await _supabase.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: redirectTo,
      captchaToken: captchaToken,
    );
  }

  Future<void> signOut() {
    return _supabase.auth.signOut();
  }

  Future<AccountOAuthAuthorization> getOAuthAuthorization(
    String authorizationId,
  ) async {
    final response = await _supabase.auth.oauth.getAuthorizationDetails(
      authorizationId,
    );
    return switch (response) {
      final OAuthAuthorizationDetailsResponse details =>
        AccountOAuthAuthorizationDetails(
          authorizationId: details.authorizationId,
          clientId: details.client.clientId,
          clientName: details.client.clientName,
          redirectUri: details.redirectUri,
          scopes: _scopes(details.scope),
        ),
      final OAuthAuthorizationRedirectResponse redirect =>
        AccountOAuthAuthorizationRedirect(redirectUrl: redirect.redirectUrl),
    };
  }

  Future<AccountOAuthConsentResult> approveOAuthAuthorization(
    String authorizationId,
  ) async {
    final response = await _supabase.auth.oauth.approveAuthorization(
      authorizationId,
    );
    return AccountOAuthConsentResult(redirectUrl: response.redirectUrl);
  }

  Future<AccountOAuthConsentResult> denyOAuthAuthorization(
    String authorizationId,
  ) async {
    final response = await _supabase.auth.oauth.denyAuthorization(
      authorizationId,
    );
    return AccountOAuthConsentResult(redirectUrl: response.redirectUrl);
  }

  Future<List<AccountOAuthGrant>> listOAuthGrants() async {
    final response = await _oauthGrantRequest('GET');
    final data = jsonDecode(response.body);
    if (data is! List) {
      throw const FormatException('Malformed OAuth grants response.');
    }
    return data
        .map((item) {
          if (item is! Map) {
            throw const FormatException('Malformed OAuth grant response.');
          }
          return AccountOAuthGrant.fromJson(Map<String, Object?>.from(item));
        })
        .toList(growable: false);
  }

  Future<void> revokeOAuthGrant(String clientId) async {
    if (!_uuid.hasMatch(clientId)) {
      throw ArgumentError.value(clientId, 'clientId', 'Must be a UUID.');
    }
    await _oauthGrantRequest('DELETE', clientId: clientId);
  }

  Future<http.Response> _oauthGrantRequest(
    String method, {
    String? clientId,
  }) async {
    final session = _supabase.auth.currentSession;
    if (session == null) {
      throw AuthSessionMissingException();
    }
    final authBaseUrl = _authBaseUrl;
    if (authBaseUrl == null) {
      throw StateError('OAuth Auth base URL is not configured.');
    }
    final path =
        '${authBaseUrl.path.replaceFirst(RegExp(r'/$'), '')}'
        '/user/oauth/grants';
    final request = http.Request(
      method,
      authBaseUrl.replace(
        path: path,
        queryParameters: clientId == null ? null : {'client_id': clientId},
      ),
    );
    request.headers.addAll({
      ..._supabase.auth.headers,
      'Authorization': 'Bearer ${session.accessToken}',
    });
    final ownedClient = _oauthHttpClient == null;
    final client = _oauthHttpClient ?? http.Client();
    try {
      final response = await http.Response.fromStream(
        await client.send(request),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AuthApiException(
          _authErrorMessage(response.body),
          statusCode: response.statusCode.toString(),
        );
      }
      return response;
    } finally {
      if (ownedClient) {
        client.close();
      }
    }
  }

  Future<AccountOverview> getOverview() async {
    final data = await _supabase.rpc<Object?>('get_account_overview');
    return AccountOverview.fromJson(_jsonMap(data));
  }

  Future<String?> getAppleAppAccountToken() async {
    final data = await _supabase.rpc<Object?>('get_apple_app_account_token');
    return data is String && data.isNotEmpty ? data : null;
  }

  Future<AccountUsagePeriod> getUsagePeriod({
    required String appId,
    required String quotaKey,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    final now = DateTime.now().toUtc();
    final start = periodStart ?? DateTime.utc(now.year, now.month);
    final end = periodEnd ?? DateTime.utc(now.year, now.month + 1);
    final userId = currentUserId;
    if (userId == null) {
      return AccountUsagePeriod(
        appId: appId,
        quotaKey: quotaKey,
        used: 0,
        limit: 0,
        unit: 'count',
        periodEnd: end,
      );
    }

    final data = await _supabase.rpc<Object?>(
      'get_usage_period',
      params: {
        'p_app_id': appId,
        'p_quota_key': quotaKey,
        'p_period_start': start.toIso8601String(),
        'p_period_end': end.toIso8601String(),
      },
    );
    return AccountUsagePeriod.fromJson(_jsonMap(data));
  }

  Future<void> registerInstall({
    required String appId,
    required String deviceId,
    String? platform,
    String? appVersion,
  }) async {
    await _supabase.from('user_app_installs').upsert({
      'user_id': currentUserId,
      'app_id': appId,
      'device_id': deviceId,
      'platform': platform,
      'app_version': appVersion,
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,app_id,device_id');
  }

  Future<AccountUsagePeriod> consumeQuota({
    required String appId,
    required String quotaKey,
    required int units,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    final now = DateTime.now().toUtc();
    final start = periodStart ?? DateTime.utc(now.year, now.month);
    final end = periodEnd ?? DateTime.utc(now.year, now.month + 1);
    final data = await _supabase.rpc<Object?>(
      'consume_quota',
      params: {
        'p_app_id': appId,
        'p_quota_key': quotaKey,
        'p_units': units,
        'p_period_start': start.toIso8601String(),
        'p_period_end': end.toIso8601String(),
      },
    );
    final json = _jsonMap(data);
    return AccountUsagePeriod.fromJson({
      'appId': appId,
      'quotaKey': quotaKey,
      'used': json['used'],
      'limit': json['limit'],
      'unit': json['unit'],
      'periodEnd': json['resetsAt'] ?? end.toIso8601String(),
    });
  }

  Future<AccountSyncPushResult> pushChanges({
    required String appId,
    required String deviceId,
    required List<AccountSyncOperation> operations,
  }) async {
    final data = await _supabase.rpc<Object?>(
      'push_changes',
      params: {
        'p_app_id': appId,
        'p_device_id': deviceId,
        'p_operations': operations.map((item) => item.toJson()).toList(),
      },
    );
    return AccountSyncPushResult.fromJson(_jsonMap(data));
  }

  Future<void> pushChangesInBatches({
    required String appId,
    required String deviceId,
    required List<AccountSyncOperation> operations,
    int batchSize = 100,
  }) async {
    if (operations.isEmpty) {
      return;
    }
    for (var index = 0; index < operations.length; index += batchSize) {
      final end = index + batchSize > operations.length
          ? operations.length
          : index + batchSize;
      await pushChanges(
        appId: appId,
        deviceId: deviceId,
        operations: operations.sublist(index, end),
      );
    }
  }

  Future<AccountSyncPullResult> pullChanges({
    required String appId,
    required String deviceId,
    required int sinceRevision,
    int limit = 500,
  }) async {
    final data = await _supabase.rpc<Object?>(
      'pull_changes',
      params: {
        'p_app_id': appId,
        'p_device_id': deviceId,
        'p_since_revision': sinceRevision,
        'p_limit': limit,
      },
    );
    return AccountSyncPullResult.fromJson(_jsonMap(data));
  }

  Stream<AccountSyncHint> syncHints({required String appId}) {
    final userId = currentUserId;
    if (userId == null) {
      return const Stream<AccountSyncHint>.empty();
    }
    RealtimeChannel? channel;
    late final StreamController<AccountSyncHint> controller;
    controller = StreamController<AccountSyncHint>(
      onListen: () {
        channel = _supabase.channel(
          AccountSyncHint.topicFor(userId: userId, appId: appId),
          opts: const RealtimeChannelConfig(private: true),
        );
        channel!
            .onBroadcast(
          event: AccountSyncHint.eventName,
          callback: (payload) {
            final hint = AccountSyncHint.fromRealtimePayload(payload);
            if (hint.appId == appId) {
              controller.add(hint);
            }
          },
        )
            .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            controller.addError(
              StateError('Sync hint channel failed: $status ($error)'),
            );
          }
        });
      },
      onCancel: () async {
        final active = channel;
        if (active != null) {
          await _supabase.removeChannel(active);
        }
      },
    );
    return controller.stream;
  }

  Future<void> broadcastSyncHint({
    required String appId,
    required String deviceId,
  }) async {
    final userId = currentUserId;
    if (userId == null) {
      return;
    }
    final channel = _supabase.channel(
      AccountSyncHint.topicFor(userId: userId, appId: appId),
      opts: const RealtimeChannelConfig(private: true, ack: true),
    );
    try {
      await _subscribe(channel);
      await channel.sendBroadcastMessage(
        event: AccountSyncHint.eventName,
        payload: AccountSyncHint(
          appId: appId,
          deviceId: deviceId,
          sentAt: DateTime.now().toUtc(),
        ).toJson(),
      );
    } finally {
      await _supabase.removeChannel(channel);
    }
  }

  Future<AccountFunctionResponse> invokeFunction(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Map<String, dynamic>? queryParameters,
    String? region,
  }) async {
    final response = await _supabase.functions.invoke(
      functionName,
      headers: headers,
      body: body,
      queryParameters: queryParameters,
      region: region,
    );
    return AccountFunctionResponse(
        status: response.status, data: response.data);
  }

  Future<String> uploadStorageBytes({
    required String bucket,
    required String path,
    required List<int> bytes,
    String? contentType,
    bool upsert = true,
    String cacheControl = '3600',
    Map<String, dynamic>? metadata,
    Map<String, String>? headers,
  }) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    return _supabase.storage.from(bucket).uploadBinary(
          _normalizedObjectPath(path),
          data,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: upsert,
            cacheControl: cacheControl,
            metadata: metadata,
            headers: headers,
          ),
        );
  }

  Future<Uint8List> downloadStorageBytes({
    required String bucket,
    required String path,
  }) {
    return _supabase.storage.from(bucket).download(_normalizedObjectPath(path));
  }
}

JsonMap _jsonMap(Object? value) {
  if (value is JsonMap) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  return const <String, Object?>{};
}

AccountSession? _accountSession(Session? session) {
  if (session == null) {
    return null;
  }
  final expiresAt = session.expiresAt;
  return AccountSession(
    userId: session.user.id,
    email: session.user.email,
    accessToken: session.accessToken,
    refreshToken: session.refreshToken,
    expiresAt: expiresAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            expiresAt * 1000,
            isUtc: true,
          ),
  );
}

String _normalizedObjectPath(String path) {
  return path.startsWith('/') ? path.substring(1) : path;
}

Future<void> _subscribe(RealtimeChannel channel) {
  final completer = Completer<void>();
  channel.subscribe((status, error) {
    if (completer.isCompleted) {
      return;
    }
    if (status == RealtimeSubscribeStatus.subscribed) {
      completer.complete();
    } else if (status == RealtimeSubscribeStatus.channelError ||
        status == RealtimeSubscribeStatus.timedOut) {
      completer.completeError(
        StateError('Failed to subscribe: $status ($error)'),
      );
    }
  });
  return completer.future.timeout(const Duration(seconds: 15));
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

List<String> _scopes(String? value) {
  return value
          ?.split(RegExp(r'\s+'))
          .where((scope) => scope.isNotEmpty)
          .toList(growable: false) ??
      const [];
}

String _authErrorMessage(String body) {
  try {
    final data = jsonDecode(body);
    if (data is Map) {
      for (final key in ['message', 'error_description', 'error']) {
        final value = data[key];
        if (value is String && value.isNotEmpty) {
          return value;
        }
      }
    }
  } on FormatException {
    // Fall back to a stable message for non-JSON Auth errors.
  }
  return 'OAuth grant request failed.';
}
