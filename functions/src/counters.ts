import {
  onDocumentCreated,
  onDocumentDeleted,
} from 'firebase-functions/v2/firestore';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

import { REGION } from './config';

const db = () => getFirestore();

/**
 * Counter maintenance.
 *
 * Two things to know about these:
 *
 * 1. They are the *only* writer of `stats` and `counts`. Security rules reject
 *    a client that touches either, which is why every number in the app reads
 *    zero until these are deployed.
 *
 * 2. Firestore triggers are at-least-once, so a retried delivery can
 *    double-count. These stay fast and simple rather than storing processed
 *    event ids, and the nightly reconcile in ranking.ts recounts from the
 *    subcollections — the documents themselves are the truth, the counters are
 *    a cache. Drift heals within a day instead of accumulating forever.
 */

const bump = (path: string, field: string, by: number) =>
  db()
    .doc(path)
    .set({ [field.split('.')[0]]: { [field.split('.')[1]]: FieldValue.increment(by) } }, { merge: true })
    .catch(() => undefined); // The parent may have been deleted; nothing to fix.

// --- recipe engagement ---------------------------------------------------

export const onLikeCreated = onDocumentCreated(
  { document: 'recipes/{recipeId}/likes/{uid}', region: REGION },
  (event) => bump(`recipes/${event.params.recipeId}`, 'stats.likes', 1),
);

export const onLikeDeleted = onDocumentDeleted(
  { document: 'recipes/{recipeId}/likes/{uid}', region: REGION },
  (event) => bump(`recipes/${event.params.recipeId}`, 'stats.likes', -1),
);

export const onCookedCreated = onDocumentCreated(
  { document: 'recipes/{recipeId}/cooked/{uid}', region: REGION },
  (event) => bump(`recipes/${event.params.recipeId}`, 'stats.cooked', 1),
);

export const onCookedDeleted = onDocumentDeleted(
  { document: 'recipes/{recipeId}/cooked/{uid}', region: REGION },
  (event) => bump(`recipes/${event.params.recipeId}`, 'stats.cooked', -1),
);

export const onCommentCreated = onDocumentCreated(
  { document: 'recipes/{recipeId}/comments/{commentId}', region: REGION },
  (event) => bump(`recipes/${event.params.recipeId}`, 'stats.comments', 1),
);

export const onCommentDeleted = onDocumentDeleted(
  { document: 'recipes/{recipeId}/comments/{commentId}', region: REGION },
  (event) => bump(`recipes/${event.params.recipeId}`, 'stats.comments', -1),
);

/// Saves live under the user, because "my saved recipes" is the query that
/// actually runs — but the recipe still wants the count, since a save is the
/// strongest ranking signal short of cooking it.
export const onSaveCreated = onDocumentCreated(
  { document: 'users/{uid}/saved/{recipeId}', region: REGION },
  (event) => bump(`recipes/${event.params.recipeId}`, 'stats.saves', 1),
);

export const onSaveDeleted = onDocumentDeleted(
  { document: 'users/{uid}/saved/{recipeId}', region: REGION },
  (event) => bump(`recipes/${event.params.recipeId}`, 'stats.saves', -1),
);

// --- unique viewers ------------------------------------------------------

export const onRecipeViewerCreated = onDocumentCreated(
  { document: 'recipes/{recipeId}/viewers/{uid}', region: REGION },
  (event) => bump(`recipes/${event.params.recipeId}`, 'stats.uniqueViewers', 1),
);

export const onPlanViewerCreated = onDocumentCreated(
  { document: 'plans/{planId}/viewers/{uid}', region: REGION },
  (event) => bump(`plans/${event.params.planId}`, 'stats.uniqueViewers', 1),
);

// --- follow graph --------------------------------------------------------

/// The client writes only its own `following` edge. The mirrored `followers`
/// edge is written here, so nobody can add themselves to another person's
/// follower list.
export const onFollowCreated = onDocumentCreated(
  { document: 'users/{uid}/following/{targetUid}', region: REGION },
  async (event) => {
    const { uid, targetUid } = event.params;
    const firestore = db();
    await Promise.all([
      firestore.doc(`users/${targetUid}/followers/${uid}`).set({
        at: FieldValue.serverTimestamp(),
      }),
      bump(`users/${uid}`, 'counts.following', 1),
      bump(`users/${targetUid}`, 'counts.followers', 1),
    ]);
  },
);

export const onFollowDeleted = onDocumentDeleted(
  { document: 'users/{uid}/following/{targetUid}', region: REGION },
  async (event) => {
    const { uid, targetUid } = event.params;
    await Promise.all([
      db().doc(`users/${targetUid}/followers/${uid}`).delete().catch(() => undefined),
      bump(`users/${uid}`, 'counts.following', -1),
      bump(`users/${targetUid}`, 'counts.followers', -1),
    ]);
  },
);

// --- authored content ----------------------------------------------------

/// Drafts deliberately don't count — a profile that claims twelve recipes and
/// shows two is worse than one that claims two. The increment lives on the
/// draft → published transition in index.ts, so it fires once; this only has
/// to undo it.
export const onRecipeDeleted = onDocumentDeleted({ document: 'recipes/{recipeId}', region: REGION }, (event) => {
  const data = event.data?.data();
  if (!data || data.status !== 'published') return undefined;
  return bump(`users/${data.author?.uid}`, 'counts.recipes', -1);
});

export const onPlanDeleted = onDocumentDeleted({ document: 'plans/{planId}', region: REGION }, (event) => {
  const data = event.data?.data();
  if (!data?.publishedAt) return undefined;
  return bump(`users/${data.owner?.uid}`, 'counts.plans', -1);
});
