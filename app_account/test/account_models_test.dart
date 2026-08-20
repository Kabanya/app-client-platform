import 'package:app_account/app_account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports canonical account contract constants', () {
    expect(AccountAppId.values, contains(AccountAppId.nottica));
    expect(AccountAppId.values, contains(AccountAppId.pomodoist));
    expect(AccountAppId.values, contains(AccountAppId.caloriecalc));
    expect(AccountQuotaKey.values, contains(AccountQuotaKey.aiCredits));
    expect(
        AccountQuotaKey.values, contains(AccountQuotaKey.voiceTranscriptions));
    expect(
      AccountQuotaKey.values,
      contains(AccountQuotaKey.photoCredits),
    );
    expect(AccountSyncContract.schemaVersion, 1);
  });

  test('overview parses app entitlements, usage, and storage', () {
    final overview = AccountOverview.fromJson({
      'profile': {
        'id': 'user-1',
        'email': 'dev@example.com',
        'displayName': 'Dev',
        'revenueCatAppUserId': 'user-1',
        'appleAppAccountToken': '11111111-1111-4111-8111-111111111111',
        'pomodoistIsPro': true,
      },
      'apps': [
        {
          'id': AccountAppId.nottica,
          'displayName': 'Nottica',
          'installed': true,
          'entitlements': [
            {
              'appId': AccountAppId.nottica,
              'entitlementId': 'nottica_pro',
              'status': 'active',
              'purchaseType': 'lifetime',
              'source': 'revenuecat',
            },
          ],
          'usage': [
            {
              'appId': AccountAppId.nottica,
              'quotaKey': 'ai_credits',
              'used': 12,
              'limit': 100,
              'unit': 'credits',
            },
          ],
          'storage': {
            'appId': AccountAppId.nottica,
            'usedBytes': 5,
            'limitBytes': 1073741824,
          },
        },
      ],
      'generatedAt': '2026-04-30T00:00:00Z',
    });

    expect(overview.profile.email, 'dev@example.com');
    expect(
      overview.profile.appleAppAccountToken,
      '11111111-1111-4111-8111-111111111111',
    );
    expect(
      overview.profile.toJson()['appleAppAccountToken'],
      '11111111-1111-4111-8111-111111111111',
    );
    expect(overview.profile.pomodoistIsPro, isTrue);
    expect(overview.profile.toJson()['pomodoistIsPro'], isTrue);
    expect(overview.apps.single.hasActiveEntitlement, isTrue);
    expect(overview.apps.single.usage.single.remaining, 88);
    expect(overview.apps.single.storage?.remainingBytes, 1073741819);
  });

  test('profile Pro flag accepts snake case and defaults safely', () {
    expect(
      AccountProfile.fromJson({
        'id': 'snake-user',
        'pomodoist_is_pro': true,
      }).pomodoistIsPro,
      isTrue,
    );
    expect(
      AccountProfile.fromJson({'id': 'legacy-user'}).pomodoistIsPro,
      isFalse,
    );
  });

  test('sync operation serializes expected rpc payload', () {
    final op = AccountSyncOperation.upsertV1(
      opId: 'op-1',
      entityType: 'task',
      entityId: 'task-1',
      payload: const {'content': 'Ship sync'},
      clientUpdatedAt: DateTime.utc(2026, 4, 30),
    );

    expect(op.toJson(), {
      'opId': 'op-1',
      'entityType': 'task',
      'entityId': 'task-1',
      'operation': 'upsert',
      'payload': {'schemaVersion': 1, 'content': 'Ship sync'},
      'clientUpdatedAt': '2026-04-30T00:00:00.000Z',
    });
  });

  test('sync hint serializes topic and realtime payload', () {
    final hint = AccountSyncHint(
      appId: AccountAppId.pomodoist,
      deviceId: 'device-1',
      sentAt: DateTime.utc(2026, 7, 7, 10),
    );

    expect(
      AccountSyncHint.topicFor(
        userId: 'user-1',
        appId: AccountAppId.pomodoist,
      ),
      'sync:user-1:pomodoist',
    );
    expect(hint.toJson(), {
      'appId': AccountAppId.pomodoist,
      'deviceId': 'device-1',
      'sentAt': '2026-07-07T10:00:00.000Z',
    });
    expect(
      AccountSyncHint.fromRealtimePayload({'payload': hint.toJson()}).deviceId,
      'device-1',
    );
  });

  test('account storage bytes are formatted consistently', () {
    expect(formatAccountBytes(512), '512 B');
    expect(formatAccountBytes(2048), '2.0 KB');
    expect(formatAccountBytes(1048576), '1.0 MB');
    expect(formatAccountBytes(1073741824), '1.0 GB');
  });
}
