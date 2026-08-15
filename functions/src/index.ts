import { initializeApp } from 'firebase-admin/app';
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

import { REGION } from './config';
import { scoreOnPublish } from './ranking';

initializeApp();

export { aggregateViewEvents } from './views';
export { nightlyRankAndReconcile } from './ranking';
export { setVerified, setModerator } from './admin';
export {
  notifyOnLike,
  notifyOnCooked,
  notifyOnComment,
  notifyOnFollow,
} from './notifications';
export { onUserDeleted, cleanupOrphanedMedia } from './cleanup';
export {
  onLikeCreated,
  onLikeDeleted,
  onCookedCreated,
  onCookedDeleted,
  onCommentCreated,
  onCommentDeleted,
  onSaveCreated,
  onSaveDeleted,
  onRecipeViewerCreated,
  onPlanViewerCreated,
  onFollowCreated,
  onFollowDeleted,
  onRecipeDeleted,
  onPlanDeleted,
} from './counters';

/**
 * Publication side effects.
 *
 * A recipe that only gets a score at 3am is invisible on the day it is
 * written, which is the day its author is most likely to be watching. The
 * author's published count moves here too, since drafts don't count and the
 * transition draft → published is what makes it real.
 */
export const onRecipePublished = onDocumentUpdated(
  { document: 'recipes/{recipeId}', region: REGION },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const justPublished =
      before.status !== 'published' && after.status === 'published';
    const justUnpublished =
      before.status === 'published' && after.status !== 'published';

    if (justPublished) {
      await Promise.all([
        scoreOnPublish(event.data!.after.ref, after),
        getFirestore()
          .doc(`users/${after.author?.uid}`)
          .set(
            { counts: { recipes: FieldValue.increment(1) } },
            { merge: true },
          )
          .catch(() => undefined),
      ]);
    } else if (justUnpublished) {
      await getFirestore()
        .doc(`users/${after.author?.uid}`)
        .set({ counts: { recipes: FieldValue.increment(-1) } }, { merge: true })
        .catch(() => undefined);
    }
  },
);

/**
 * Same for a week: publishing it is what counts, not creating it.
 */
export const onPlanPublished = onDocumentUpdated(
  { document: 'plans/{planId}', region: REGION },
  async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after) return;

  if (!before.publishedAt && after.publishedAt) {
    await getFirestore()
      .doc(`users/${after.owner?.uid}`)
      .set({ counts: { plans: FieldValue.increment(1) } }, { merge: true })
      .catch(() => undefined);
  }
});
