/**
 * Runs the ranking reconcile immediately instead of waiting for 03:00.
 *
 * Needed after a bulk import: those recipes arrive already published, so there
 * is no draft-to-published transition for the scorer to hang off. This calls
 * the same compiled function the nightly schedule does — reimplementing the
 * formula in a script would give two copies that drift invisibly.
 *
 *   cd functions && npm run build
 *   node scripts/rescore.js --key=/path/key.json
 */
const admin = require('firebase-admin');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const keyArg = process.argv
  .find((a) => a.startsWith('--key='))
  ?.slice('--key='.length);
const keyPath = keyArg ?? process.env.GOOGLE_APPLICATION_CREDENTIALS;

if (!keyPath || !fs.existsSync(path.resolve(keyPath.replace(/^~/, os.homedir())))) {
  console.error('Need a service-account key: --key=/path/key.json');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.resolve(keyPath.replace(/^~/, os.homedir()))),
  ),
});

const { reconcileAndScoreAll } = require('../lib/ranking');

reconcileAndScoreAll()
  .then((n) => {
    console.log(`Rescored ${n} published recipe(s).`);
    process.exit(0);
  })
  .catch((e) => {
    console.error(`Failed: ${e.message}`);
    process.exit(1);
  });
