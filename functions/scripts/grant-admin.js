/**
 * Grants the first admin + moderator claim.
 *
 * There is no way around running this once by hand: `setVerified` and
 * `setModerator` both require a claim that nobody has yet, and the Firebase CLI
 * has no command for custom claims. After the first admin exists, everything
 * else happens inside the app.
 *
 *   cd functions
 *   node scripts/grant-admin.js <uid> [--revoke]
 *
 * Needs a service-account key:
 *   Firebase Console → Project settings → Service accounts → Generate new
 *   private key. Then either export GOOGLE_APPLICATION_CREDENTIALS=/path/key.json
 *   or pass --key=/path/key.json.
 *
 * The key is a root credential for the whole project. Keep it out of the repo
 * and delete it when you're done — you only need it this once.
 */

const admin = require('firebase-admin');
const path = require('node:path');

const args = process.argv.slice(2);
const uid = args.find((a) => !a.startsWith('--'));
const revoke = args.includes('--revoke');
const keyArg = args.find((a) => a.startsWith('--key='))?.slice('--key='.length);

if (!uid) {
  console.error('Usage: node scripts/grant-admin.js <uid> [--revoke] [--key=/path/key.json]');
  console.error('\nFind your uid in Firebase Console → Authentication → Users,');
  console.error('or in the app under Me → Settings → Account (debug builds).');
  process.exit(1);
}

const keyPath = keyArg ?? process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!keyPath) {
  console.error('No service-account key. Pass --key=/path/key.json or set');
  console.error('GOOGLE_APPLICATION_CREDENTIALS. Generate one at:');
  console.error('  Firebase Console → Project settings → Service accounts');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(path.resolve(keyPath))),
});

(async () => {
  const user = await admin.auth().getUser(uid);

  // Merge rather than replace: setCustomUserClaims overwrites the whole object,
  // so a naive write here would silently strip someone's verified mark.
  const claims = {
    ...(user.customClaims ?? {}),
    admin: !revoke,
    moderator: !revoke,
  };

  await admin.auth().setCustomUserClaims(uid, claims);

  console.log(`${revoke ? 'Revoked' : 'Granted'} admin + moderator`);
  console.log(`  uid:   ${uid}`);
  console.log(`  who:   ${user.displayName ?? user.phoneNumber ?? user.email ?? '—'}`);
  console.log(`  now:   ${JSON.stringify(claims)}`);
  console.log('\nClaims only reach a device when its ID token is reissued.');
  console.log('In the app: sign out and back in, or open Me → Moderation and tap retry.');
  process.exit(0);
})().catch((error) => {
  console.error(`Failed: ${error.message}`);
  process.exit(1);
});
