# Brnj برنج

A community recipe app for Iraq. Flutter + Firebase, no custom backend.

The recipes are the excuse — the product is the kitchen table. Iraqi cooks
talking to each other in Arabic and Kurdish, sharing what they're cooking this
week, in communities, group chats, and voice notes.

Full product and technical plan: **https://claude.ai/code/artifact/49ce177c-95fd-46ac-a978-a995ea686305**

## Running it

```bash
flutter pub get
flutter gen-l10n        # regenerate after editing anything in lib/l10n/*.arb
flutter run
```

The app runs without Firebase configured — it shows sample content and a setup
banner — so UI work isn't blocked on project access.

## Connecting Firebase

```bash
flutterfire configure          # writes lib/firebase_options.dart
```

Then uncomment the two marked lines in [lib/app/bootstrap.dart](lib/app/bootstrap.dart).

Pick the database location once, because it can't be changed: **`me-central1`**
(Doha) is the lowest latency for Iraq, with `europe-west1` as the fallback if a
service isn't offered there yet. Don't accept the `us-central1` default — it
adds 150–250ms to every read for nothing.

Deploy rules and indexes:

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage
```

## Layout

```
lib/
  app/          router, theme, localisation, settings, Firebase bootstrap
  core/         pure Dart utilities with no Flutter or Firebase imports
  data/         models and repositories
  features/     one folder per feature area
  shared/       design-system widgets
  l10n/         .arb source + generated delegates (lib/l10n/gen)
```

Every Firebase call goes through a repository. That's what keeps the planned
Firestore→RTDB move for busy chat rooms, and any eventual search swap, a
contained change rather than a rewrite.

## Things that are easy to get wrong here

**RTL is the default, not a mode.** Three of the four locales are right-to-left.
Never use `left`/`right` in layout — only `start`/`end`, `EdgeInsetsDirectional`,
`PositionedDirectional`. Test every screen in both directions as you build it;
retrofitting RTL is one of the most expensive mistakes available.

**Kurdish is not Arabic.** Sorani (`ckb`) and Badini (`kmr`) need fonts that
carry ڵ ڕ ۆ ێ گ چ پ ژ — Cairo and Tajawal don't. `flutter_localizations` has no
Material translations for either, so
[lib/app/localization.dart](lib/app/localization.dart) supplies fallback
delegates that must stay ahead of the `Global*` ones. And search folding runs in
the *opposite* direction from Arabic (ك→ک, ي→ی), which is why
[lib/core/search_text.dart](lib/core/search_text.dart) takes a script argument.

**The week starts on Saturday.** Friday is the family meal and gets visual
weight. All week arithmetic goes through
[lib/core/iraqi_week.dart](lib/core/iraqi_week.dart) — an ISO week would silently
put Sunday in the wrong week.

**Never write `stats`, `score`, `counts`, `verified`, or `roles` from a client.**
They're Function-owned and the security rules reject them. A client that can
write its own view count will write its own view count.

**Guests are real users.** Anonymous auth signs everyone in at launch so rules
always have a uid and preferences survive registration via `linkWithCredential`.
Never show a login wall — prompt at the action, then complete that action.

## Tests

```bash
flutter test
```

The two utilities with the highest bug-per-line risk — Arabic/Kurdish search
normalisation and Saturday-start week arithmetic — are covered. Keep them that
way.

## Not yet wired

- `flutterfire configure` (needs project access)
- Repositories — models and rules exist, the Firestore calls don't
- Cloud Functions: view aggregation, counters, FCM sends, `setVerified`
- Fonts: drop IBM Plex Sans Arabic into `assets/fonts/` and uncomment the
  `fonts:` block in `pubspec.yaml`

## Note on the toolchain

Built against Flutter 3.35.2 / Dart 3.9. The current `freezed` and
`json_serializable` need Dart 3.10+, so models use hand-written converters —
which suits Firestore anyway, since `Timestamp` needs custom handling
regardless. Upgrading Flutter would unlock codegen if you want it.
