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
const fs = require('node:fs');
const os = require('node:os');
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
  console.error('  https://console.firebase.google.com/project/brnj-54249/settings/serviceaccounts/adminsdk');
  process.exit(1);
}

const resolvedKey = path.resolve(keyPath.replace(/^~/, os.homedir()));

if (!fs.existsSync(resolvedKey)) {
  console.error(`No file at: ${resolvedKey}`);
  if (keyPath.includes('/path/to/')) {
    console.error('\nThat looks like the placeholder from the instructions.');
    console.error('Replace it with where the key actually downloaded, usually:');
    console.error('  ~/Downloads/brnj-54249-firebase-adminsdk-*.json');
  }
  console.error('\nDownload one at:');
  console.error('  https://console.firebase.google.com/project/brnj-54249/settings/serviceaccounts/adminsdk');
  console.error('  → Generate new private key');
  process.exit(1);
}

let serviceAccount;
try {
  serviceAccount = JSON.parse(fs.readFileSync(resolvedKey, 'utf8'));
} catch (error) {
  console.error(`That file is not valid JSON: ${resolvedKey}`);
  process.exit(1);
}

// A key for the wrong project authenticates fine and then fails to find the
// user, which reads as "bad uid" and sends you looking in the wrong place.
if (!serviceAccount.private_key || !serviceAccount.project_id) {
  console.error('That JSON is not a service-account key — no private_key field.');
  console.error('Use the file from Project settings → Service accounts,');
  console.error('not google-services.json or GoogleService-Info.plist.');
  process.exit(1);
}

if (serviceAccount.project_id !== 'brnj-54249') {
  console.error(`That key belongs to project "${serviceAccount.project_id}", not brnj-54249.`);
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

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
  if (error.code === 'auth/user-not-found') {
    console.error(`No user with uid "${uid}" in brnj-54249.`);
    console.error('Check Me → Settings → Account → Your user ID in a debug build,');
    console.error('or Firebase Console → Authentication → Users.');
  } else {
    console.error(`Failed: ${error.message}`);
  }
  process.exit(1);
});
