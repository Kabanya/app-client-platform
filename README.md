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

[PolyForm Noncommercial License 1.0.0](LICENSE). This repository is
source-available, not OSI open source.
