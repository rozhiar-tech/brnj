import * as functionsV1 from 'firebase-functions/v1';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

import { AUTH_TRIGGER_REGION, REGION } from './config';

const db = () => getFirestore();

/**
 * Purges a deleted account.
 *
 * Google Play has required in-app account deletion since 2024, and deletion
 * that leaves the person's recipes, weeks and viewer records behind is not
 * deletion. Auth triggers only exist in the v1 API, which is why this one
 * function is written against it.
 */
export const onUserDeleted = functionsV1
  .region(AUTH_TRIGGER_REGION)
  .auth.user()
  .onDelete(async (user) => {
    const firestore = db();
    const uid = user.uid;

    const owned = await Promise.all([
      firestore.collection('recipes').where('author.uid', '==', uid).get(),
      firestore.collection('plans').where('owner.uid', '==', uid).get(),
    ]);

    const batch = firestore.batch();
    for (const snapshot of owned) {
      for (const doc of snapshot.docs) batch.delete(doc.ref);
    }
    batch.delete(firestore.doc(`users/${uid}`));
    await batch.commit();

    // Storage is not covered by Firestore deletes, and an orphaned avatar is
    // still the person's face sitting on a public URL.
    await getStorage()
      .bucket()
      .deleteFiles({ prefix: `users/${uid}/` })
      .catch(() => undefined);

    logger.info('Purged deleted user', { uid });
  });

/**
 * Deletes Storage objects no document refers to.
 *
 * Abandoned drafts are the main source: someone picks a cover photo, the
 * upload succeeds, and they never publish. Without this the bucket grows
 * forever and the bill grows with it.
 */
export const cleanupOrphanedMedia = onSchedule(
  { schedule: '0 4 * * *', timeZone: 'Asia/Baghdad', timeoutSeconds: 540, region: REGION },
  async () => {
    const firestore = db();
    const bucket = getStorage().bucket();

    const [files] = await bucket.getFiles({ prefix: 'recipes/' });
    const recipeIds = new Set(
      (await firestore.collection('recipes').select().get()).docs.map((d) => d.id),
    );

    let deleted = 0;
    const dayOld = Date.now() - 24 * 3_600_000;

    for (const file of files) {
      const recipeId = file.name.split('/')[1];
      if (recipeIds.has(recipeId)) continue;

      // Only files older than a day: an upload that lands moments before its
      // document is created must not be swept away underneath it.
      const created = new Date(file.metadata.timeCreated ?? 0).getTime();
      if (created > dayOld) continue;

      await file.delete().catch(() => undefined);
      deleted += 1;
    }

    logger.info('Orphaned media cleanup complete', {
      scanned: files.length,
      deleted,
    });
  },
);
