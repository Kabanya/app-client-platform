import 'account_models.dart';

class AccountSyncHint {
  const AccountSyncHint({
    required this.appId,
    required this.deviceId,
    required this.sentAt,
  });

  static const eventName = 'changed';

  final String appId;
  final String deviceId;
  final DateTime sentAt;

  static String topicFor({required String userId, required String appId}) {
    return 'sync:$userId:$appId';
  }

  factory AccountSyncHint.fromJson(JsonMap json) {
    return AccountSyncHint(
      appId: json['appId'] as String? ?? json['app_id'] as String? ?? '',
      deviceId:
          json['deviceId'] as String? ?? json['device_id'] as String? ?? '',
      sentAt: DateTime.tryParse(json['sentAt'] as String? ?? '') ??
          DateTime.tryParse(json['sent_at'] as String? ?? '') ??
          DateTime.now().toUtc(),
    );
  }

  factory AccountSyncHint.fromRealtimePayload(JsonMap json) {
    final payload = switch (json['payload']) {
      final JsonMap value => value,
      final Map value => Map<String, Object?>.from(value),
      _ => json,
    };
    return AccountSyncHint.fromJson(payload);
  }

  JsonMap toJson() {
    return {
      'appId': appId,
      'deviceId': deviceId,
      'sentAt': sentAt.toUtc().toIso8601String(),
    };
  }
}

class AccountSyncOperation {
  const AccountSyncOperation({
    required this.opId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.clientUpdatedAt,
  });

  final String opId;
  final String entityType;
  final String entityId;
  final String operation;
  final JsonMap payload;
  final DateTime clientUpdatedAt;

  factory AccountSyncOperation.upsertV1({
    required String opId,
    required String entityType,
    required String entityId,
    required JsonMap payload,
    required DateTime clientUpdatedAt,
  }) {
    return AccountSyncOperation(
      opId: opId,
      entityType: entityType,
      entityId: entityId,
      operation: 'upsert',
      payload: {'schemaVersion': AccountSyncContract.schemaVersion, ...payload},
      clientUpdatedAt: clientUpdatedAt.toUtc(),
    );
  }

  factory AccountSyncOperation.deleteV1({
    required String opId,
    required String entityType,
    required String entityId,
    JsonMap payload = const <String, Object?>{},
    required DateTime clientUpdatedAt,
  }) {
    return AccountSyncOperation(
      opId: opId,
      entityType: entityType,
      entityId: entityId,
      operation: 'delete',
      payload: {'schemaVersion': AccountSyncContract.schemaVersion, ...payload},
      clientUpdatedAt: clientUpdatedAt.toUtc(),
    );
  }

  factory AccountSyncOperation.fromJson(JsonMap json) {
    return AccountSyncOperation(
      opId: json['opId'] as String? ?? json['op_id'] as String? ?? '',
      entityType:
          json['entityType'] as String? ?? json['entity_type'] as String? ?? '',
      entityId:
          json['entityId'] as String? ?? json['entity_id'] as String? ?? '',
      operation: json['operation'] as String? ?? 'upsert',
      payload: switch (json['payload']) {
        final JsonMap value => value,
        final Map value => Map<String, Object?>.from(value),
        _ => const <String, Object?>{},
      },
      clientUpdatedAt:
          DateTime.tryParse(json['clientUpdatedAt'] as String? ?? '') ??
              DateTime.tryParse(json['client_updated_at'] as String? ?? '') ??
              DateTime.now().toUtc(),
    );
  }

  JsonMap toJson() {
    return {
      'opId': opId,
      'entityType': entityType,
      'entityId': entityId,
      'operation': operation,
      'payload': payload,
      'clientUpdatedAt': clientUpdatedAt.toUtc().toIso8601String(),
    };
  }
}

class AccountSyncEntity {
  const AccountSyncEntity({
    required this.entityType,
    required this.entityId,
    required this.serverRevision,
    required this.data,
    this.deletedAt,
    this.updatedAt,
  });

  final String entityType;
  final String entityId;
  final int serverRevision;
  final JsonMap data;
  final DateTime? deletedAt;
  final DateTime? updatedAt;

  bool get deleted => deletedAt != null;

  factory AccountSyncEntity.fromJson(JsonMap json) {
    return AccountSyncEntity(
      entityType:
          json['entityType'] as String? ?? json['entity_type'] as String? ?? '',
      entityId:
          json['entityId'] as String? ?? json['entity_id'] as String? ?? '',
      serverRevision: switch (
          json['serverRevision'] ?? json['server_revision']) {
        final int value => value,
        final num value => value.toInt(),
        final String value => int.tryParse(value) ?? 0,
        _ => 0,
      },
      data: switch (json['data']) {
        final JsonMap value => value,
        final Map value => Map<String, Object?>.from(value),
        _ => const <String, Object?>{},
      },
      deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? '') ??
          DateTime.tryParse(json['deleted_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.tryParse(json['updated_at'] as String? ?? ''),
    );
  }
}

class AccountSyncPushResult {
  const AccountSyncPushResult({
    required this.serverRevision,
    required this.applied,
  });

  final int serverRevision;
  final List<AccountSyncEntity> applied;

  factory AccountSyncPushResult.fromJson(JsonMap json) {
    return AccountSyncPushResult(
      serverRevision: switch (
          json['serverRevision'] ?? json['server_revision']) {
        final int value => value,
        final num value => value.toInt(),
        final String value => int.tryParse(value) ?? 0,
        _ => 0,
      },
      applied: switch (json['applied']) {
        final List value => value
            .whereType<Map>()
            .map(
              (item) =>
                  AccountSyncEntity.fromJson(Map<String, Object?>.from(item)),
            )
            .toList(growable: false),
        _ => const <AccountSyncEntity>[],
      },
    );
  }
}

class AccountSyncPullResult {
  const AccountSyncPullResult({
    required this.nextCursor,
    required this.hasMore,
    required this.changes,
  });

  final int nextCursor;
  final bool hasMore;
  final List<AccountSyncEntity> changes;

  factory AccountSyncPullResult.fromJson(JsonMap json) {
    return AccountSyncPullResult(
      nextCursor: switch (json['nextCursor'] ?? json['next_cursor']) {
        final int value => value,
        final num value => value.toInt(),
        final String value => int.tryParse(value) ?? 0,
        _ => 0,
      },
      hasMore: json['hasMore'] as bool? ?? json['has_more'] as bool? ?? false,
      changes: switch (json['changes']) {
        final List value => value
            .whereType<Map>()
            .map(
              (item) =>
                  AccountSyncEntity.fromJson(Map<String, Object?>.from(item)),
            )
            .toList(growable: false),
        _ => const <AccountSyncEntity>[],
      },
    );
  }
}
