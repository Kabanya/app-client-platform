import 'dart:convert';

import 'package:app_account/app_account.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('password sign in forwards the CAPTCHA token', () async {
    final httpClient = _RecordingHttpClient();
    final account = _accountClient(httpClient);

    await account.signInWithPassword(
      email: 'dev@example.com',
      password: 'password',
      captchaToken: 'sign-in-captcha',
    );

    expect(httpClient.requests.single.path, '/auth/v1/token');
    expect(
      httpClient.requests.single.body['gotrue_meta_security'],
      {'captcha_token': 'sign-in-captcha'},
    );
  });

  test('password sign up forwards the CAPTCHA token', () async {
    final httpClient = _RecordingHttpClient();
    final account = _accountClient(httpClient);

    await account.signUpWithPassword(
      email: 'dev@example.com',
      password: 'password',
      captchaToken: 'sign-up-captcha',
    );

    expect(httpClient.requests.single.path, '/auth/v1/signup');
    expect(
      httpClient.requests.single.body['gotrue_meta_security'],
      {'captcha_token': 'sign-up-captcha'},
    );
  });

  test('magic-link sign in forwards the CAPTCHA token', () async {
    final httpClient = _RecordingHttpClient();
    final account = _accountClient(httpClient);

    await account.signInWithEmail(
      'dev@example.com',
      captchaToken: 'magic-link-captcha',
    );

    expect(httpClient.requests.single.path, '/auth/v1/otp');
    expect(
      httpClient.requests.single.body['gotrue_meta_security'],
      {'captcha_token': 'magic-link-captcha'},
    );
  });

  test('account auth methods remain callable without a CAPTCHA token',
      () async {
    final httpClient = _RecordingHttpClient();
    final account = _accountClient(httpClient);

    await account.signInWithPassword(
      email: 'dev@example.com',
      password: 'password',
    );
    await account.signUpWithPassword(
      email: 'dev@example.com',
      password: 'password',
    );
    await account.signInWithEmail('dev@example.com');

    expect(httpClient.requests, hasLength(3));
    for (final request in httpClient.requests) {
      expect(
        request.body['gotrue_meta_security'],
        {'captcha_token': null},
      );
    }
  });

  test('Apple sign in uses browser OAuth outside native Apple platforms',
      () async {
    final httpClient = _RecordingHttpClient();
    String? browserRedirect;
    var nativeCalls = 0;
    final account = _accountClient(
      httpClient,
      nativeAppleSignIn: false,
      appleCredentialProvider: (_) async {
        nativeCalls++;
        return _appleCredential();
      },
      appleBrowserSignIn: (redirectTo) async {
        browserRedirect = redirectTo;
      },
    );

    await account.signInWithApple(
      redirectTo: 'https://app.pomodoist.com/login-callback',
    );

    expect(browserRedirect, 'https://app.pomodoist.com/login-callback');
    expect(nativeCalls, 0);
    expect(httpClient.requests, isEmpty);
  });

  test('native Google sign in opens the OAuth callback externally', () async {
    final httpClient = _RecordingHttpClient();
    String? browserRedirect;
    LaunchMode? browserLaunchMode;
    final account = _accountClient(
      httpClient,
      googleBrowserSignIn: (redirectTo, launchMode) async {
        browserRedirect = redirectTo;
        browserLaunchMode = launchMode;
      },
    );

    await account.signInWithGoogle(
      redirectTo: 'pomodoist://login-callback',
    );

    expect(browserRedirect, 'pomodoist://login-callback');
    expect(browserLaunchMode, LaunchMode.externalApplication);
    expect(httpClient.requests, isEmpty);
  });

  test('native Apple sign in hashes the nonce and stores the Apple name',
      () async {
    final httpClient = _RecordingHttpClient(authenticated: true);
    String? hashedNonce;
    final account = _accountClient(
      httpClient,
      nativeAppleSignIn: true,
      appleCredentialProvider: (nonce) async {
        hashedNonce = nonce;
        return _appleCredential(
          givenName: ' Ethan ',
          familyName: ' Walker ',
        );
      },
    );

    await account.signInWithApple();

    final tokenRequest = httpClient.requests.first;
    final rawNonce = tokenRequest.body['nonce'] as String;
    expect(
      hashedNonce,
      sha256.convert(utf8.encode(rawNonce)).toString(),
    );
    expect(tokenRequest.path, '/auth/v1/token');
    expect(tokenRequest.body['provider'], 'apple');
    expect(tokenRequest.body['id_token'], 'apple-id-token');
    expect(
      httpClient.requests.last.body['data'],
      {
        'full_name': 'Ethan Walker',
        'given_name': 'Ethan',
        'family_name': 'Walker',
      },
    );
    expect(account.currentSession, isNotNull);
  });

  test('canceling native Apple sign in returns without a request', () async {
    final httpClient = _RecordingHttpClient();
    final account = _accountClient(
      httpClient,
      nativeAppleSignIn: true,
      appleCredentialProvider: (_) =>
          throw const SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.canceled,
        message: 'Canceled',
      ),
    );

    await account.signInWithApple();

    expect(httpClient.requests, isEmpty);
  });

  test('native Apple sign in rejects a missing identity token', () async {
    final httpClient = _RecordingHttpClient();
    final account = _accountClient(
      httpClient,
      nativeAppleSignIn: true,
      appleCredentialProvider: (_) async => _appleCredential(
        identityToken: null,
      ),
    );

    await expectLater(
      account.signInWithApple(),
      throwsA(isA<AuthException>()),
    );
    expect(httpClient.requests, isEmpty);
  });

  test('Apple name update failure preserves the established session', () async {
    final httpClient = _RecordingHttpClient(
      authenticated: true,
      failUserUpdate: true,
    );
    final account = _accountClient(
      httpClient,
      nativeAppleSignIn: true,
      appleCredentialProvider: (_) async => _appleCredential(
        givenName: 'Ethan',
        familyName: 'Walker',
      ),
    );

    await account.signInWithApple();

    expect(account.currentSession, isNotNull);
    expect(
      httpClient.requests.map((request) => request.path),
      ['/auth/v1/token', '/auth/v1/user'],
    );
  });
}

AccountClient _accountClient(
  http.Client httpClient, {
  bool? nativeAppleSignIn,
  Future<AuthorizationCredentialAppleID> Function(String hashedNonce)?
      appleCredentialProvider,
  Future<void> Function(String? redirectTo)? appleBrowserSignIn,
  Future<void> Function(String? redirectTo, LaunchMode launchMode)?
      googleBrowserSignIn,
}) {
  return AccountClient.fromSupabaseClient(
    SupabaseClient(
      'http://localhost:54321',
      'anon-key',
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
      httpClient: httpClient,
    ),
    nativeAppleSignIn: nativeAppleSignIn,
    appleCredentialProvider: appleCredentialProvider,
    appleBrowserSignIn: appleBrowserSignIn,
    googleBrowserSignIn: googleBrowserSignIn,
  );
}

AuthorizationCredentialAppleID _appleCredential({
  String? givenName,
  String? familyName,
  String? identityToken = 'apple-id-token',
}) {
  return AuthorizationCredentialAppleID(
    userIdentifier: 'apple-user',
    givenName: givenName,
    familyName: familyName,
    authorizationCode: 'apple-authorization-code',
    email: 'ethan@example.com',
    identityToken: identityToken,
    state: null,
  );
}

class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient({
    this.authenticated = false,
    this.failUserUpdate = false,
  });

  final bool authenticated;
  final bool failUserUpdate;
  final List<_RecordedRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyText = await request.finalize().bytesToString();
    final body = bodyText.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(bodyText) as Map<String, dynamic>;
    requests.add(_RecordedRequest(path: request.url.path, body: body));

    if (failUserUpdate && request.url.path == '/auth/v1/user') {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"message":"update failed"}')),
        500,
        headers: {'content-type': 'application/json'},
      );
    }

    final response = authenticated && request.url.path == '/auth/v1/token'
        ? _sessionResponse
        : authenticated && request.url.path == '/auth/v1/user'
            ? _userResponse
            : <String, dynamic>{};
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(response))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

const _userResponse = {
  'id': 'apple-user',
  'app_metadata': {'provider': 'apple'},
  'user_metadata': <String, dynamic>{},
  'aud': 'authenticated',
  'created_at': '2026-07-17T00:00:00.000Z',
};

const _sessionResponse = {
  'access_token': 'test-access-token',
  'expires_in': 3600,
  'refresh_token': 'test-refresh-token',
  'token_type': 'bearer',
  'user': _userResponse,
};

class _RecordedRequest {
  const _RecordedRequest({required this.path, required this.body});

  final String path;
  final Map<String, dynamic> body;
}
