import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

import { REGION } from './config';

const db = () => getFirestore();

/**
 * Grants or revokes the verified mark.
 *
 * Verification is a curation tool, not a status game: a human decides, it
 * lapses on inactivity, and nothing here is self-serve. The flag is written in
 * two places on purpose — an Auth custom claim, which security rules can trust,
 * and a field on the user document, which clients can render and rank on
 * without reading the token.
 *
 * Both have to move together, and every piece of content carrying a
 * denormalised copy has to be backfilled, or the rules will start rejecting
 * that author's writes: creation checks that `author.verified` matches the
 * token exactly.
 */
export const setVerified = onCall<{ uid: string; verified: boolean }>(
  { region: REGION },
  async (request) => {
    if (request.auth?.token.moderator !== true && request.auth?.token.admin !== true) {
      throw new HttpsError('permission-denied', 'Moderators only');
    }

    const { uid, verified } = request.data;
    if (!uid) throw new HttpsError('invalid-argument', 'uid is required');

    const auth = getAuth();
    const existing = (await auth.getUser(uid)).customClaims ?? {};
    await auth.setCustomUserClaims(uid, { ...existing, verified });

    const firestore = db();
    await firestore.doc(`users/${uid}`).set(
      {
        verified,
        verifiedAt: verified ? FieldValue.serverTimestamp() : FieldValue.delete(),
      },
      { merge: true },
    );

    await backfillAuthorFlag(uid, verified);

    logger.info('Verification updated', { uid, verified, by: request.auth?.uid });
    return { ok: true };
  },
);

/**
 * Rewrites the denormalised `author.verified` / `owner.verified` copies.
 *
 * Without this, a newly verified author's next write is rejected: the create
 * rule requires the copy on the document to match the token, and their older
 * documents would disagree with their new status in every feed.
 */
async function backfillAuthorFlag(uid: string, verified: boolean) {
  const firestore = db();

  const recipes = await firestore
    .collection('recipes')
    .where('author.uid', '==', uid)
    .get();

  const plans = await firestore
    .collection('plans')
    .where('owner.uid', '==', uid)
    .get();

  // Chunked because a batch caps at 500 writes and a prolific author will
  // eventually exceed it.
  const docs = [
    ...recipes.docs.map((d) => ({ ref: d.ref, field: 'author.verified' })),
    ...plans.docs.map((d) => ({ ref: d.ref, field: 'owner.verified' })),
  ];

  for (let i = 0; i < docs.length; i += 400) {
    const batch = firestore.batch();
    for (const { ref, field } of docs.slice(i, i + 400)) {
      batch.update(ref, { [field]: verified });
    }
    await batch.commit();
  }

  logger.info('Backfilled verified flag', { uid, documents: docs.length });
}

/**
 * Grants or revokes the moderator claim. Same shape, no denormalised copies to
 * chase — moderation powers are never rendered in the UI.
 */
export const setModerator = onCall<{ uid: string; moderator: boolean }>(
  { region: REGION },
  async (request) => {
    if (request.auth?.token.admin !== true) {
      throw new HttpsError('permission-denied', 'Admins only');
    }

    const { uid, moderator } = request.data;
    if (!uid) throw new HttpsError('invalid-argument', 'uid is required');

    const auth = getAuth();
    const existing = (await auth.getUser(uid)).customClaims ?? {};
    await auth.setCustomUserClaims(uid, { ...existing, moderator });

    logger.info('Moderator updated', { uid, moderator, by: request.auth?.uid });
    return { ok: true };
  },
);
