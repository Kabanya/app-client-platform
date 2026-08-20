typedef JsonMap = Map<String, Object?>;

abstract final class AccountAppId {
  static const pomodoist = 'pomodoist';
  static const nottica = 'nottica';
  static const caloriecalc = 'caloriecalc';

  static const values = <String>{pomodoist, nottica, caloriecalc};
}

abstract final class AccountQuotaKey {
  static const aiCredits = 'ai_credits';
  static const voiceTranscriptions = 'voice_transcriptions';
  static const photoCredits = 'photo_credits';

  static const values = <String>{
    aiCredits,
    voiceTranscriptions,
    photoCredits,
  };
}

abstract final class AccountSyncContract {
  static const schemaVersion = 1;
}

class AccountSession {
  const AccountSession({
    required this.userId,
    this.email,
    this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  final String userId;
  final String? email;
  final String? accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
}

class AccountAuthState {
  const AccountAuthState({
    required this.signedIn,
    this.session,
  });

  final bool signedIn;
  final AccountSession? session;
}

sealed class AccountOAuthAuthorization {
  const AccountOAuthAuthorization();
}

final class AccountOAuthAuthorizationDetails extends AccountOAuthAuthorization {
  AccountOAuthAuthorizationDetails({
    required this.authorizationId,
    required this.clientId,
    required this.clientName,
    required this.redirectUri,
    required List<String> scopes,
  }) : scopes = List.unmodifiable(scopes);

  final String authorizationId;
  final String clientId;
  final String? clientName;
  final String redirectUri;
  final List<String> scopes;
}

final class AccountOAuthAuthorizationRedirect
    extends AccountOAuthAuthorization {
  const AccountOAuthAuthorizationRedirect({required this.redirectUrl});

  final String redirectUrl;
}

final class AccountOAuthConsentResult {
  const AccountOAuthConsentResult({this.redirectUrl});

  final String? redirectUrl;
}

final class AccountOAuthGrant {
  AccountOAuthGrant({
    required this.clientId,
    required this.clientName,
    required List<String> scopes,
    required this.connectedAt,
  }) : scopes = List.unmodifiable(scopes);

  final String clientId;
  final String? clientName;
  final List<String> scopes;
  final DateTime connectedAt;

  factory AccountOAuthGrant.fromJson(JsonMap json) {
    final client = _map(json['client']);
    final clientId = _string(client?['id']);
    final connectedAt = _date(json['granted_at']);
    final scopes = json['scopes'];
    if (clientId == null ||
        connectedAt == null ||
        scopes is! List ||
        scopes.any((scope) => scope is! String)) {
      throw const FormatException('Malformed OAuth grant response.');
    }
    return AccountOAuthGrant(
      clientId: clientId,
      clientName: _string(client?['name']),
      scopes: scopes.cast<String>(),
      connectedAt: connectedAt,
    );
  }
}

class AccountFunctionResponse {
  const AccountFunctionResponse({
    required this.status,
    this.data,
  });

  final int status;
  final Object? data;
}

class AccountProfile {
  const AccountProfile({
    required this.id,
    this.email,
    this.displayName,
    this.avatarUrl,
    this.revenueCatAppUserId,
    this.appleAppAccountToken,
    this.pomodoistIsPro = false,
  });

  final String id;
  final String? email;
  final String? displayName;
  final String? avatarUrl;
  final String? revenueCatAppUserId;
  final String? appleAppAccountToken;
  final bool pomodoistIsPro;

  factory AccountProfile.fromJson(JsonMap json) {
    return AccountProfile(
      id: _string(json['id']) ?? '',
      email: _string(json['email']),
      displayName: _string(json['displayName'] ?? json['display_name']),
      avatarUrl: _string(json['avatarUrl'] ?? json['avatar_url']),
      revenueCatAppUserId: _string(
        json['revenueCatAppUserId'] ?? json['revenuecat_app_user_id'],
      ),
      appleAppAccountToken: _string(
        json['appleAppAccountToken'] ?? json['apple_app_account_token'],
      ),
      pomodoistIsPro:
          _bool(json['pomodoistIsPro'] ?? json['pomodoist_is_pro']) ?? false,
    );
  }

  JsonMap toJson() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'revenueCatAppUserId': revenueCatAppUserId,
      'appleAppAccountToken': appleAppAccountToken,
      'pomodoistIsPro': pomodoistIsPro,
    };
  }
}

class AccountEntitlement {
  const AccountEntitlement({
    required this.appId,
    required this.entitlementId,
    required this.status,
    required this.purchaseType,
    required this.source,
    this.productId,
    this.store,
    this.validUntil,
    this.renewsAt,
  });

  final String appId;
  final String entitlementId;
  final String status;
  final String purchaseType;
  final String source;
  final String? productId;
  final String? store;
  final DateTime? validUntil;
  final DateTime? renewsAt;

  bool get active => status == 'active';
  bool get lifetime => purchaseType == 'lifetime';
  bool get subscription => purchaseType == 'subscription';

  factory AccountEntitlement.fromJson(JsonMap json) {
    return AccountEntitlement(
      appId: _string(json['appId'] ?? json['app_id']) ?? '',
      entitlementId:
          _string(json['entitlementId'] ?? json['entitlement_id']) ?? '',
      status: _string(json['status']) ?? 'inactive',
      purchaseType: _string(json['purchaseType'] ?? json['purchase_type']) ??
          'subscription',
      source: _string(json['source']) ?? 'unknown',
      productId: _string(json['productId'] ?? json['product_id']),
      store: _string(json['store']),
      validUntil: _date(json['validUntil'] ?? json['valid_until']),
      renewsAt: _date(json['renewsAt'] ?? json['renews_at']),
    );
  }

  JsonMap toJson() {
    return {
      'appId': appId,
      'entitlementId': entitlementId,
      'status': status,
      'purchaseType': purchaseType,
      'source': source,
      'productId': productId,
      'store': store,
      'validUntil': validUntil?.toIso8601String(),
      'renewsAt': renewsAt?.toIso8601String(),
    };
  }
}

class AccountUsagePeriod {
  const AccountUsagePeriod({
    required this.appId,
    required this.quotaKey,
    required this.used,
    required this.limit,
    required this.unit,
    this.periodEnd,
  });

  final String appId;
  final String quotaKey;
  final int used;
  final int limit;
  final String unit;
  final DateTime? periodEnd;

  int get remaining => (limit - used).clamp(0, limit);

  factory AccountUsagePeriod.fromJson(JsonMap json) {
    return AccountUsagePeriod(
      appId: _string(json['appId'] ?? json['app_id']) ?? '',
      quotaKey: _string(json['quotaKey'] ?? json['quota_key']) ?? '',
      used: _int(json['used']) ?? 0,
      limit: _int(json['limit']) ?? 0,
      unit: _string(json['unit']) ?? 'count',
      periodEnd: _date(json['periodEnd'] ?? json['period_end']),
    );
  }

  JsonMap toJson() {
    return {
      'appId': appId,
      'quotaKey': quotaKey,
      'used': used,
      'limit': limit,
      'remaining': remaining,
      'unit': unit,
      'periodEnd': periodEnd?.toIso8601String(),
    };
  }
}

class AccountStorageUsage {
  const AccountStorageUsage({
    required this.appId,
    required this.usedBytes,
    required this.limitBytes,
  });

  final String appId;
  final int usedBytes;
  final int limitBytes;

  int get remainingBytes => (limitBytes - usedBytes).clamp(0, limitBytes);

  factory AccountStorageUsage.fromJson(JsonMap json) {
    return AccountStorageUsage(
      appId: _string(json['appId'] ?? json['app_id']) ?? '',
      usedBytes: _int(json['usedBytes'] ?? json['used_bytes']) ?? 0,
      limitBytes: _int(json['limitBytes'] ?? json['limit_bytes']) ?? 0,
    );
  }

  JsonMap toJson() {
    return {
      'appId': appId,
      'usedBytes': usedBytes,
      'limitBytes': limitBytes,
      'remainingBytes': remainingBytes,
    };
  }
}

class AccountAppSummary {
  const AccountAppSummary({
    required this.id,
    required this.displayName,
    this.installed = false,
    this.entitlements = const [],
    this.usage = const [],
    this.storage,
  });

  final String id;
  final String displayName;
  final bool installed;
  final List<AccountEntitlement> entitlements;
  final List<AccountUsagePeriod> usage;
  final AccountStorageUsage? storage;

  bool get hasActiveEntitlement => entitlements.any((item) => item.active);

  factory AccountAppSummary.fromJson(JsonMap json) {
    return AccountAppSummary(
      id: _string(json['id'] ?? json['appId'] ?? json['app_id']) ?? '',
      displayName: _string(json['displayName'] ?? json['display_name']) ?? '',
      installed: _bool(json['installed']) ?? false,
      entitlements: _list(json['entitlements'])
          .whereType<JsonMap>()
          .map(AccountEntitlement.fromJson)
          .toList(growable: false),
      usage: _list(json['usage'])
          .whereType<JsonMap>()
          .map(AccountUsagePeriod.fromJson)
          .toList(growable: false),
      storage: switch (json['storage']) {
        final JsonMap value => AccountStorageUsage.fromJson(value),
        final Map value => AccountStorageUsage.fromJson(
            Map<String, Object?>.from(value),
          ),
        _ => null,
      },
    );
  }

  JsonMap toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'installed': installed,
      'entitlements': entitlements.map((item) => item.toJson()).toList(),
      'usage': usage.map((item) => item.toJson()).toList(),
      'storage': storage?.toJson(),
    };
  }
}

class AccountOverview {
  const AccountOverview({
    required this.profile,
    required this.apps,
    required this.generatedAt,
  });

  final AccountProfile profile;
  final List<AccountAppSummary> apps;
  final DateTime generatedAt;

  factory AccountOverview.fromJson(JsonMap json) {
    final profileValue = json['profile'];
    return AccountOverview(
      profile: profileValue is JsonMap
          ? AccountProfile.fromJson(profileValue)
          : profileValue is Map
              ? AccountProfile.fromJson(Map<String, Object?>.from(profileValue))
              : const AccountProfile(id: ''),
      apps: _list(json['apps'])
          .whereType<JsonMap>()
          .map(AccountAppSummary.fromJson)
          .toList(growable: false),
      generatedAt: _date(json['generatedAt'] ?? json['generated_at']) ??
          DateTime.now().toUtc(),
    );
  }

  factory AccountOverview.empty(String userId) {
    return AccountOverview(
      profile: AccountProfile(id: userId),
      apps: const [],
      generatedAt: DateTime.now().toUtc(),
    );
  }

  JsonMap toJson() {
    return {
      'profile': profile.toJson(),
      'apps': apps.map((item) => item.toJson()).toList(),
      'generatedAt': generatedAt.toIso8601String(),
    };
  }
}

String? _string(Object? value) => value is String ? value : null;

int? _int(Object? value) {
  return switch (value) {
    final int intValue => intValue,
    final num numValue => numValue.toInt(),
    final String stringValue => int.tryParse(stringValue),
    _ => null,
  };
}

bool? _bool(Object? value) {
  return switch (value) {
    final bool boolValue => boolValue,
    final String stringValue => stringValue == 'true',
    _ => null,
  };
}

DateTime? _date(Object? value) {
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is String) {
    return DateTime.tryParse(value)?.toUtc();
  }
  return null;
}

List<Object?> _list(Object? value) {
  if (value is List) {
    return value.cast<Object?>();
  }
  return const [];
}

JsonMap? _map(Object? value) {
  return value is Map ? Map<String, Object?>.from(value) : null;
}
