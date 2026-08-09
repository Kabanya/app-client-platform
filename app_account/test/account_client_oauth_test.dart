import 'dart:convert';

import 'package:app_account/app_account.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const clientId = '7263e727-435b-4d38-a5ff-a14c954b8680';

  test('maps pending authorization details with requested scopes', () async {
    final fixture = await _Fixture.authenticated();

    final result = await fixture.account.getOAuthAuthorization('pending-id');

    final details = result as AccountOAuthAuthorizationDetails;
    expect(details.authorizationId, 'pending-id');
    expect(details.clientId, clientId);
    expect(details.clientName, 'MCP Inspector');
    expect(details.redirectUri, 'http://127.0.0.1:6274/oauth/callback');
    expect(details.scopes, ['tasks:read', 'tasks:write']);
  });

  test('maps an already-consented authorization redirect opaquely', () async {
    final fixture = await _Fixture.authenticated();

    final result = await fixture.account.getOAuthAuthorization('redirect-id');

    expect(
      (result as AccountOAuthAuthorizationRedirect).redirectUrl,
      'pomodoist-agent://callback?code=a%2Fb&state=x+y',
    );
  });

  test('maps approve and deny redirects opaquely', () async {
    final fixture = await _Fixture.authenticated();

    final approved = await fixture.account.approveOAuthAuthorization(
      'pending-id',
    );
    final denied = await fixture.account.denyOAuthAuthorization('pending-id');

    expect(approved.redirectUrl, 'https://agent.test/callback?code=a%2Fb');
    expect(denied.redirectUrl, 'https://agent.test/callback?error=denied+x');
    expect(
      fixture.http.requests
          .where((request) => request.path.endsWith('/consent'))
          .map((request) => request.body['action']),
      ['approve', 'deny'],
    );
  });

  test('parses authenticated OAuth grants and Auth headers', () async {
    final fixture = await _Fixture.authenticated();

    final grants = await fixture.account.listOAuthGrants();

    expect(grants, hasLength(1));
    expect(grants.single.clientId, clientId);
    expect(grants.single.clientName, 'MCP Inspector');
    expect(grants.single.scopes, ['tasks:read', 'tasks:write']);
    expect(grants.single.connectedAt, DateTime.utc(2026, 7, 30, 12, 34, 56));
    final request = fixture.http.requests.last;
    expect(request.method, 'GET');
    expect(request.path, '/auth/v1/user/oauth/grants');
    expect(request.headers, fixture.expectedOAuthHeaders);
    expect(request.url.toString(), isNot(contains('test-access-token')));
    expect(request.body, isEmpty);
  });

  test('revokes a grant by encoded, validated OAuth client ID', () async {
    final fixture = await _Fixture.authenticated();

    await fixture.account.revokeOAuthGrant(clientId);

    final request = fixture.http.requests.last;
    expect(request.method, 'DELETE');
    expect(request.path, '/auth/v1/user/oauth/grants');
    expect(request.url.queryParameters, {'client_id': clientId});
    expect(
      request.url.toString(),
      endsWith('client_id=7263e727-435b-4d38-a5ff-a14c954b8680'),
    );
    expect(request.headers['Authorization'], 'Bearer test-access-token');
  });

  test('rejects grant calls without a current session', () async {
    final fixture = _Fixture();

    await expectLater(
      fixture.account.listOAuthGrants(),
      throwsA(isA<AuthSessionMissingException>()),
    );
    await expectLater(
      fixture.account.revokeOAuthGrant(clientId),
      throwsA(isA<AuthSessionMissingException>()),
    );
    expect(fixture.http.requests, isEmpty);
  });

  test('rejects a malformed client ID before revoke request', () async {
    final fixture = await _Fixture.authenticated();
    final countBefore = fixture.http.requests.length;

    await expectLater(
      fixture.account.revokeOAuthGrant('../not-a-client'),
      throwsArgumentError,
    );

    expect(fixture.http.requests, hasLength(countBefore));
  });

  test('rejects malformed grant responses', () async {
    final fixture = await _Fixture.authenticated(grantsBody: '{"grants":[]}');

    await expectLater(
      fixture.account.listOAuthGrants(),
      throwsA(isA<FormatException>()),
    );
  });

  test('turns non-2xx grant responses into Auth API errors', () async {
    final fixture = await _Fixture.authenticated(grantsStatus: 503);

    await expectLater(
      fixture.account.listOAuthGrants(),
      throwsA(
        isA<AuthApiException>()
            .having((error) => error.statusCode, 'statusCode', '503')
            .having((error) => error.message, 'message', 'temporarily down'),
      ),
    );
  });
}

class _Fixture {
  _Fixture({String? grantsBody, int grantsStatus = 200})
    : http = _RecordingHttpClient(
        grantsBody: grantsBody,
        grantsStatus: grantsStatus,
      ) {
    final supabase = SupabaseClient(
      'http://localhost:54321',
      'anon-key',
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
      httpClient: http,
    );
    account = AccountClient.fromSupabaseClient(
      supabase,
      authBaseUrl: Uri.parse('http://localhost:54321/auth/v1'),
      oauthHttpClient: http,
    );
    expectedOAuthHeaders = {
      ...supabase.auth.headers,
      'Authorization': 'Bearer test-access-token',
    };
  }

  static Future<_Fixture> authenticated({
    String? grantsBody,
    int grantsStatus = 200,
  }) async {
    final fixture = _Fixture(
      grantsBody: grantsBody,
      grantsStatus: grantsStatus,
    );
    await fixture.account.signInWithPassword(
      email: 'dev@example.com',
      password: 'password',
    );
    fixture.http.requests.clear();
    return fixture;
  }

  final _RecordingHttpClient http;
  late final AccountClient account;
  late final Map<String, String> expectedOAuthHeaders;
}

class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient({String? grantsBody, this.grantsStatus = 200})
    : grantsBody = grantsBody ?? jsonEncode(_grantsResponse);

  final String grantsBody;
  final int grantsStatus;
  final List<_RecordedRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyText = await request.finalize().bytesToString();
    final body = bodyText.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(bodyText) as Map<String, dynamic>;
    requests.add(
      _RecordedRequest(
        method: request.method,
        url: request.url,
        headers: Map<String, String>.from(request.headers),
        body: body,
      ),
    );

    final (status, response) = switch ((request.method, request.url.path)) {
      ('POST', '/auth/v1/token') => (200, jsonEncode(_sessionResponse)),
      ('GET', '/auth/v1/oauth/authorizations/pending-id') => (
        200,
        jsonEncode(_pendingResponse),
      ),
      ('GET', '/auth/v1/oauth/authorizations/redirect-id') => (
        200,
        jsonEncode({
          'redirect_url': 'pomodoist-agent://callback?code=a%2Fb&state=x+y',
        }),
      ),
      ('POST', '/auth/v1/oauth/authorizations/pending-id/consent') => (
        200,
        jsonEncode({
          'redirect_url': body['action'] == 'approve'
              ? 'https://agent.test/callback?code=a%2Fb'
              : 'https://agent.test/callback?error=denied+x',
        }),
      ),
      ('GET', '/auth/v1/user/oauth/grants') => (
        grantsStatus,
        grantsStatus == 200
            ? grantsBody
            : jsonEncode({'message': 'temporarily down'}),
      ),
      ('DELETE', '/auth/v1/user/oauth/grants') => (204, ''),
      _ => (404, jsonEncode({'message': 'not found'})),
    };
    return http.StreamedResponse(
      Stream.value(utf8.encode(response)),
      status,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
  });

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final Map<String, dynamic> body;

  String get path => url.path;
}

const _pendingResponse = {
  'authorization_id': 'pending-id',
  'redirect_uri': 'http://127.0.0.1:6274/oauth/callback',
  'client': {
    'id': '7263e727-435b-4d38-a5ff-a14c954b8680',
    'name': 'MCP Inspector',
  },
  'user': {
    'id': '1bee2038-51fe-4f93-8fbb-442df18657ff',
    'email': 'dev@example.com',
    'app_metadata': {'provider': 'email'},
    'user_metadata': <String, dynamic>{},
    'aud': 'authenticated',
    'created_at': '2026-07-30T00:00:00.000Z',
  },
  'scope': 'tasks:read tasks:write',
};

const _grantsResponse = [
  {
    'client': {
      'id': '7263e727-435b-4d38-a5ff-a14c954b8680',
      'name': 'MCP Inspector',
    },
    'scopes': ['tasks:read', 'tasks:write'],
    'granted_at': '2026-07-30T12:34:56.000Z',
  },
];

const _userResponse = {
  'id': '1bee2038-51fe-4f93-8fbb-442df18657ff',
  'email': 'dev@example.com',
  'app_metadata': {'provider': 'email'},
  'user_metadata': <String, dynamic>{},
  'aud': 'authenticated',
  'created_at': '2026-07-30T00:00:00.000Z',
};

const _sessionResponse = {
  'access_token': 'test-access-token',
  'expires_in': 3600,
  'refresh_token': 'test-refresh-token',
  'token_type': 'bearer',
  'user': _userResponse,
};
