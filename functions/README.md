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

## Granting the first admin

`setVerified` and `setModerator` both require a claim nobody has yet, and the
Firebase CLI has no command for custom claims — so the first one is granted by
hand, once. Everything after that happens in the app under Me → Moderation.

1. **Get your uid.** Run the app in debug and open Me → Settings → Account →
   Your user ID, which copies it. (Or Firebase Console → Authentication → Users.)

2. **Download a service-account key.** Firebase Console → Project settings →
   Service accounts → Generate new private key.

3. **Run it:**

   ```bash
   cd functions
   npm install                                    # once
   node scripts/grant-admin.js <uid> --key=/path/to/key.json
   ```

4. **Sign out and back in** in the app. Custom claims only reach a device when
   its ID token is reissued, so an already-signed-in session won't see it.
   Me → Moderation also has a retry button that forces a token refresh.

5. **Delete the key.** It is a root credential for the entire project and you
   only need it this once.

Revoke with `node scripts/grant-admin.js <uid> --revoke --key=…`.
