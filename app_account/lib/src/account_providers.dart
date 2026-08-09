import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_client.dart';
import 'account_models.dart';

typedef AccountDeviceIdResolver = FutureOr<String> Function(Ref ref);

Provider<bool> createAccountConfiguredProvider(
  Provider<AccountClient?> accountClientProvider,
) {
  return Provider<bool>((ref) => ref.watch(accountClientProvider) != null);
}

FutureProvider<AccountOverview?> createAccountOverviewProvider({
  required Provider<AccountClient?> accountClientProvider,
  required String appId,
  required AccountDeviceIdResolver deviceId,
  String platform = 'flutter',
  String? appVersion,
}) {
  return FutureProvider<AccountOverview?>((ref) async {
    final account = ref.watch(accountClientProvider);
    if (account == null || account.currentUserId == null) {
      return null;
    }
    await account.registerInstall(
      appId: appId,
      deviceId: await deviceId(ref),
      platform: platform,
      appVersion: appVersion,
    );
    return account.getOverview();
  });
}
