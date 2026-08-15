import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';
import { getFirestore } from 'firebase-admin/firestore';

import { REGION } from './config';

const db = () => getFirestore();

/**
 * Ranking weights.
 *
 * Saves and "cooked" outweigh likes because a like is a reflex and a save is
 * intent — cooking it is proof. Unique viewers barely register, so the boost
 * cannot be farmed by manufacturing views.
 */
const WEIGHTS = {
  saves: 3,
  cooked: 2,
  comments: 2,
  likes: 1,
  uniqueViewers: 0.05,
  qualityFloor: 5,
  verifiedMultiplier: 1.6,
};

/**
 * score = freshness × (engagement + qualityFloor) × authorMultiplier
 *
 * The verified multiplier lives in Firestore config rather than here, so it can
 * be tuned after launch without a deploy. Start at 1.6 and watch the share of
 * unverified authors who post again within fourteen days: if the boost is too
 * strong, that number falls before anything else does.
 */
function scoreOf(data: FirebaseFirestore.DocumentData, verifiedMultiplier: number) {
  const stats = data.stats ?? {};
  const publishedAt: FirebaseFirestore.Timestamp | undefined =
    data.publishedAt ?? data.createdAt;
  const hours = publishedAt
    ? (Date.now() - publishedAt.toMillis()) / 3_600_000
    : 0;

  const freshness = 1 / Math.pow(hours + 6, 0.6);

  const engagement =
    WEIGHTS.saves * (stats.saves ?? 0) +
    WEIGHTS.cooked * (stats.cooked ?? 0) +
    WEIGHTS.comments * (stats.comments ?? 0) +
    WEIGHTS.likes * (stats.likes ?? 0) +
    WEIGHTS.uniqueViewers * (stats.uniqueViewers ?? 0);

  // A recipe with its own photo and real steps outranks an empty one even with
  // no engagement yet, so a good first post is not invisible.
  const hasOwnPhoto = typeof data.coverUrl === 'string' && data.coverUrl.length > 0;
  const enoughSteps = Array.isArray(data.steps) && data.steps.length >= 3;
  const qualityFloor = hasOwnPhoto && enoughSteps ? WEIGHTS.qualityFloor : 0;

  const multiplier = data.author?.verified === true ? verifiedMultiplier : 1;

  return freshness * (engagement + qualityFloor) * multiplier;
}

/**
 * Nightly: recount from the subcollections, then rescore.
 *
 * The recount matters because the incremental counters in counters.ts are
 * at-least-once and can drift. The documents are the truth; the counters are a
 * cache that gets rebuilt here, so drift heals within a day rather than
 * accumulating forever.
 */
export const nightlyRankAndReconcile = onSchedule(
  { schedule: '0 3 * * *', timeZone: 'Asia/Baghdad', timeoutSeconds: 540, region: REGION },
  async () => {
    const firestore = db();

    const config = await firestore.doc('config/app').get();
    const verifiedMultiplier =
      (config.get('rankingWeights.verifiedMultiplier') as number | undefined) ??
      WEIGHTS.verifiedMultiplier;

    const recipes = await firestore
      .collection('recipes')
      .where('status', '==', 'published')
      .get();

    let updated = 0;

    for (const doc of recipes.docs) {
      // Saves live under each user rather than under the recipe, so the
      // recount is a collection-group query. That needs `recipeId` as a field
      // on the save document — a subcollection cannot be filtered by its own
      // document id from a collection group.
      const [likes, saves, cooked, comments, viewers] = await Promise.all([
        doc.ref.collection('likes').count().get(),
        firestore
          .collectionGroup('saved')
          .where('recipeId', '==', doc.id)
          .count()
          .get(),
        doc.ref.collection('cooked').count().get(),
        doc.ref.collection('comments').count().get(),
        doc.ref.collection('viewers').count().get(),
      ]);

      const stats = {
        ...(doc.get('stats') ?? {}),
        likes: likes.data().count,
        saves: saves.data().count,
        cooked: cooked.data().count,
        comments: comments.data().count,
        uniqueViewers: viewers.data().count,
      };

      await doc.ref.update({
        stats,
        score: scoreOf({ ...doc.data(), stats }, verifiedMultiplier),
      });
      updated += 1;
    }

    logger.info('Nightly rank and reconcile complete', { recipes: updated });
  },
);

/**
 * Scores a recipe the moment it is published, so a new post is rankable
 * immediately rather than invisible until 3am.
 */
export async function scoreOnPublish(
  ref: FirebaseFirestore.DocumentReference,
  data: FirebaseFirestore.DocumentData,
) {
  await ref.update({ score: scoreOf(data, WEIGHTS.verifiedMultiplier) });
}
