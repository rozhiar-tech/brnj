/**
 * Bulk recipe import.
 *
 * The composer is built for one person writing one recipe on a phone. Three
 * hundred of those is days of thumb-work, so this takes a JSON file instead:
 * draft in a spreadsheet, export, run once.
 *
 *   cd functions
 *   node scripts/import-recipes.js recipes.json --key=~/Downloads/key.json [--publish] [--dry-run]
 *
 * Keywords are deliberately not computed here — the keywordsOnRecipeWrite
 * Function recomputes them server-side for every recipe, so there is only one
 * normaliser that has to be right.
 *
 * See scripts/recipes.example.json for the shape.
 */

const admin = require('firebase-admin');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const args = process.argv.slice(2);
const file = args.find((a) => !a.startsWith('--'));
const publish = args.includes('--publish');
const dryRun = args.includes('--dry-run');
const keyArg = args.find((a) => a.startsWith('--key='))?.slice('--key='.length);
const asUid = args.find((a) => a.startsWith('--as='))?.slice('--as='.length);

const resolve = (p) => path.resolve(p.replace(/^~/, os.homedir()));

if (!file) {
  console.error('Usage: node scripts/import-recipes.js <recipes.json> --key=/path/key.json');
  console.error('       [--as=<uid>]  author, defaults to the only admin');
  console.error('       [--publish]   publish instead of leaving drafts');
  console.error('       [--dry-run]   validate and report, write nothing');
  process.exit(1);
}

const keyPath = keyArg ?? process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!keyPath || !fs.existsSync(resolve(keyPath))) {
  console.error('Need a service-account key: --key=/path/key.json');
  console.error('  https://console.firebase.google.com/project/brnj-54249/settings/serviceaccounts/adminsdk');
  process.exit(1);
}

if (!fs.existsSync(resolve(file))) {
  console.error(`No file at: ${resolve(file)}`);
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(resolve(keyPath))),
  storageBucket: 'brnj-54249.firebasestorage.app',
});

const db = admin.firestore();
const bucket = admin.storage().bucket();

const REGIONS = [
  'baghdadi', 'mosuli', 'basrawi', 'anbari', 'kurdishErbil',
  'kurdishSulaymaniyah', 'kurdishDuhok', 'turkmenKirkuk', 'general',
];
const UNITS = [
  'istikan', 'finjan', 'cup', 'tablespoon', 'teaspoon', 'gram', 'kilo',
  'ml', 'litre', 'piece', 'pinch', 'toTaste',
];
const DIFFICULTY = ['easy', 'medium', 'hard'];
const COST = ['cheap', 'medium', 'occasion'];

/** Fails loudly on a bad file rather than writing ninety good recipes and one
 *  broken one that only shows up as an empty card weeks later. */
function validate(recipe, index) {
  const where = `recipe[${index}]${recipe.title ? ` "${recipe.title}"` : ''}`;
  const errors = [];

  if (!recipe.title?.trim()) errors.push('title is required');
  if (recipe.region && !REGIONS.includes(recipe.region)) {
    errors.push(`region "${recipe.region}" — expected one of ${REGIONS.join(', ')}`);
  }
  if (recipe.difficulty && !DIFFICULTY.includes(recipe.difficulty)) {
    errors.push(`difficulty "${recipe.difficulty}"`);
  }
  if (recipe.costBand && !COST.includes(recipe.costBand)) {
    errors.push(`costBand "${recipe.costBand}"`);
  }
  for (const [i, ing] of (recipe.ingredients ?? []).entries()) {
    if (!ing.item?.trim()) errors.push(`ingredients[${i}] has no item`);
    if (ing.unit && !UNITS.includes(ing.unit)) {
      errors.push(`ingredients[${i}] unit "${ing.unit}" — expected one of ${UNITS.join(', ')}`);
    }
  }
  if (publish) {
    if (!(recipe.ingredients ?? []).length) errors.push('publishing needs ingredients');
    if (!(recipe.steps ?? []).length) errors.push('publishing needs steps');
  }

  return errors.map((e) => `${where}: ${e}`);
}

/// Not fatal, but worth saying out loud.
function warn(recipe, index) {
  const where = `recipe[${index}] "${recipe.title ?? ''}"`;
  const warnings = [];

  // The server does not require a cover, but ranking's quality floor does:
  // a recipe with its own photo and three or more steps scores above one
  // without, so a coverless recipe starts near the bottom of Discover.
  if (publish && !recipe.coverImage && !recipe.coverUrl) {
    warnings.push('no cover image — it will rank low and look empty in the feed');
  }
  if ((recipe.steps ?? []).length < 3) {
    warnings.push('fewer than 3 steps — misses the ranking quality floor');
  }

  return warnings.map((w) => `${where}: ${w}`);
}

const GRAMS = {
  istikan: 100, finjan: 60, cup: 240, tablespoon: 15, teaspoon: 5,
  gram: 1, kilo: 1000, ml: 1, litre: 1000, piece: 0, pinch: 0, toTaste: 0,
};

async function uploadCover(recipeId, localPath) {
  const source = resolve(localPath);
  if (!fs.existsSync(source)) throw new Error(`no image at ${source}`);

  const destination = `recipes/${recipeId}/cover.jpg`;
  await bucket.upload(source, {
    destination,
    metadata: { contentType: 'image/jpeg', cacheControl: 'public, max-age=604800' },
  });

  const fileRef = bucket.file(destination);
  await fileRef.makePublic();
  return `https://storage.googleapis.com/${bucket.name}/${destination}`;
}

(async () => {
  const recipes = JSON.parse(fs.readFileSync(resolve(file), 'utf8'));
  if (!Array.isArray(recipes)) {
    console.error('Expected a JSON array of recipes.');
    process.exit(1);
  }

  const warnings = recipes.flatMap(warn);
  if (warnings.length) {
    console.warn(`${warnings.length} warning(s):\n`);
    for (const w of warnings) console.warn(`  ${w}`);
    console.warn('');
  }

  const errors = recipes.flatMap(validate);
  if (errors.length) {
    console.error(`${errors.length} problem(s) — nothing was written:\n`);
    for (const e of errors) console.error(`  ${e}`);
    process.exit(1);
  }

  let authorUid = asUid;
  if (!authorUid) {
    // Default to the only admin, which during seeding is the person running
    // this. Ambiguity here would silently attribute the whole corpus to
    // whoever sorted first.
    const admins = [];
    let token;
    do {
      const page = await admin.auth().listUsers(1000, token);
      for (const u of page.users) {
        if (u.customClaims?.admin === true) admins.push(u.uid);
      }
      token = page.pageToken;
    } while (token);

    if (admins.length !== 1) {
      console.error(`Found ${admins.length} admins — pass --as=<uid> to choose an author.`);
      process.exit(1);
    }
    authorUid = admins[0];
  }

  const profile = await db.doc(`users/${authorUid}`).get();
  if (!profile.exists) {
    console.error(`No profile for ${authorUid}. Sign in on the app once first.`);
    process.exit(1);
  }

  const author = {
    uid: authorUid,
    name: profile.get('displayName') ?? '',
    verified: profile.get('verified') === true,
    ...(profile.get('photoUrl') ? { photoUrl: profile.get('photoUrl') } : {}),
  };

  console.log(`${dryRun ? 'Would import' : 'Importing'} ${recipes.length} recipe(s)`);
  console.log(`  author:  ${author.name} (${authorUid})${author.verified ? ' ✓' : ''}`);
  console.log(`  status:  ${publish ? 'published' : 'draft'}\n`);

  if (dryRun) {
    for (const r of recipes) console.log(`  ok  ${r.title}`);
    console.log('\nNothing written (--dry-run).');
    process.exit(0);
  }

  let done = 0;
  for (const r of recipes) {
    const ref = db.collection('recipes').doc();

    let coverUrl = r.coverUrl ?? null;
    if (r.coverImage) coverUrl = await uploadCover(ref.id, r.coverImage);

    const ingredients = (r.ingredients ?? []).map((i) => {
      const unit = i.unit ?? 'toTaste';
      const grams = GRAMS[unit];
      return {
        item: i.item,
        ...(i.quantity != null ? { quantity: i.quantity } : {}),
        unit,
        ...(i.group ? { group: i.group } : {}),
        ...(i.note ? { note: i.note } : {}),
        ...(i.quantity != null && grams > 0
          ? { canonicalGrams: i.quantity * grams }
          : {}),
      };
    });

    await ref.set({
      author,
      title: r.title.trim(),
      language: r.language ?? 'ar',
      ...(r.description ? { description: r.description } : {}),
      ...(coverUrl ? { coverUrl } : {}),
      gallery: [],
      region: r.region ?? 'general',
      tags: r.tags ?? [],
      occasions: r.occasions ?? [],
      difficulty: r.difficulty ?? 'easy',
      costBand: r.costBand ?? 'medium',
      prepMinutes: r.prepMinutes ?? 0,
      cookMinutes: r.cookMinutes ?? 0,
      servings: r.servings ?? 4,
      ingredients,
      steps: (r.steps ?? []).map((s) =>
        typeof s === 'string'
          ? { text: s }
          : {
              text: s.text,
              ...(s.timerMinutes ? { timerSeconds: s.timerMinutes * 60 } : {}),
            },
      ),
      // keywords are left out on purpose — keywordsOnRecipeWrite fills them in
      // so there is exactly one normaliser in the system.
      status: publish ? 'published' : 'draft',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(publish ? { publishedAt: admin.firestore.FieldValue.serverTimestamp() } : {}),
    });

    done += 1;
    console.log(`  ${done}/${recipes.length}  ${r.title}`);
  }

  console.log(`\nDone. ${done} recipe(s) written as ${publish ? 'published' : 'drafts'}.`);
  if (!publish) console.log('Review them in the app under Me → My recipes, then publish.');
  process.exit(0);
})().catch((error) => {
  console.error(`\nFailed: ${error.message}`);
  process.exit(1);
});
