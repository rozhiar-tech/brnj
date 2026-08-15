# Cloud Functions

Everything that clients are not allowed to write. Security rules reject any
client touching `stats`, `counts`, `score`, `verified`, or `roles`, so until
these run every number in the app reads zero.

Deployed to `me-central1`, alongside Firestore.

```bash
cd functions
npm install
npm run build
firebase deploy --only functions
```

## What runs when

| Function | Trigger | Does |
|---|---|---|
| `aggregateViewEvents` | every 5 min | Drains `viewEvents` into `stats.views`, `viewers/{uid}`, and plan copy counts |
| `nightlyRankAndReconcile` | 03:00 Baghdad | Recounts stats from subcollections, recomputes `score` |
| `cleanupOrphanedMedia` | 04:00 Baghdad | Deletes Storage objects with no owning document |
| `onRecipePublished` | recipe update | Scores immediately on publish, bumps the author's count |
| counter triggers | like/save/cooked/comment/follow/viewer writes | Keep `stats` and `counts` current |
| `setVerified`, `setModerator` | callable | Custom claims + denormalised backfill, moderators only |
| `onUserDeleted` | auth delete | Purges the account's content and media |

## Region is explicit, not global

Every function passes `region: REGION`. `setGlobalOptions` looked like it
worked and did not: TypeScript hoists the `import` / `export … from` requires
above the call, so functions are already defined by the time it runs. The first
deploy landed them in two different regions depending on module load order.

## Counter drift is expected

Firestore triggers are at-least-once, so a retried delivery can double-count.
The incremental counters stay simple and fast; `nightlyRankAndReconcile`
recounts from the subcollections, which are the truth. Drift heals within a day
rather than accumulating.

## Granting the first moderator

`setVerified` requires a `moderator` or `admin` custom claim, and nobody has one
initially. Bootstrap it once from a machine with a service-account key:

```bash
GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node -e "
  const admin = require('firebase-admin');
  admin.initializeApp();
  admin.auth().setCustomUserClaims('YOUR_UID', { admin: true, moderator: true })
    .then(() => console.log('done'));
"
```

Claims only refresh when the client's ID token does — sign out and back in, or
call `getIdToken(true)`.
