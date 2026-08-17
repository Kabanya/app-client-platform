# App Client Platform

Shared Flutter client packages used by Pomodoist, Noten, and Nottica.

- `app_account`: account, entitlement, quota, and sync client contracts.
- `app_voice`: recorded Apple system speech recognition.

## Checks

```sh
(cd app_account && flutter pub get && flutter analyze && flutter test)
(cd app_voice && flutter pub get && flutter analyze && flutter test)
```

Applications consume tagged revisions from this repository. For simultaneous
local development, use an untracked `pubspec_overrides.yaml` with path
overrides to a sibling checkout.

## Backend

Supabase migrations, RLS policies, Edge Functions, deployment configuration,
and production secrets are not part of this repository.

## License

Copyright © 2026 FinchForge LLC.

This repository is open-source software licensed under the
[GNU Affero General Public License v3.0 only](LICENSE) (`AGPL-3.0-only`).
The packages and official client binaries that include them remain licensed
under `AGPL-3.0-only`. Paid Pomodoist subscriptions cover hosted services and
account entitlements, not a proprietary client license. See the
[licensing model](LICENSING.md).
Contributions are accepted under the [Contributor License Agreement](CLA.md);
see [CONTRIBUTING.md](CONTRIBUTING.md).
