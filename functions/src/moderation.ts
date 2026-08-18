import { onDocumentCreated, onDocumentWritten } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

import { REGION } from './config';
import { keywordsForRecipe } from './search';

const db = () => getFirestore();

/**
 * Recomputes `keywords` server-side on every recipe write.
 *
 * The client computes them too, but two hand-written copies of a normaliser
 * drift, and anything written outside the app — the seed importer, a future
 * admin tool — has no Dart to run. Making the server authoritative means a
 * recipe is searchable no matter what wrote it.
 */
export const keywordsOnRecipeWrite = onDocumentWritten(
  { document: 'recipes/{recipeId}', region: REGION },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;

    const data = after.data()!;
    const expected = keywordsForRecipe(data);
    const current: string[] = Array.isArray(data.keywords) ? data.keywords : [];

    // Compare before writing: this trigger fires on its own write, and an
    // unconditional update would recurse until the retry budget ran out.
    const same =
      current.length === expected.length &&
      expected.every((k, i) => current[i] === k);
    if (same) return;

    await after.ref.update({ keywords: expected });
  },
);

/**
 * Auto-hides content once enough distinct people have reported it.
 *
 * Moderation here is human and slow — automated classifiers do not work on
 * Iraqi dialect or Kurdish — so the queue can take a day. This is the part
 * that has to be fast: a threshold of unique reporters takes something out of
 * circulation while it waits for a person, and hiding is reversible where
 * deleting is not.
 */
const HIDE_THRESHOLD = 3;

export const onReportCreated = onDocumentCreated(
  { document: 'reports/{reportId}', region: REGION },
  async (event) => {
    const report = event.data?.data();
    if (!report) return;

    const { targetType, targetId } = report as {
      targetType?: string;
      targetId?: string;
    };
    if (!targetType || !targetId) return;

    const firestore = db();

    const siblings = await firestore
      .collection('reports')
      .where('targetId', '==', targetId)
      .where('status', '==', 'open')
      .get();

    // Distinct reporters, not distinct reports: one person filing five times
    // is one person with an opinion, not five.
    const reporters = new Set(
      siblings.docs.map((d) => d.get('reporterId') as string).filter(Boolean),
    );

    if (reporters.size < HIDE_THRESHOLD) return;

    const collection =
      targetType === 'plan' ? 'plans' : targetType === 'recipe' ? 'recipes' : null;
    if (!collection) return;

    await firestore
      .doc(`${collection}/${targetId}`)
      .set(
        { status: 'hidden', hiddenBy: 'auto', hiddenAt: FieldValue.serverTimestamp() },
        { merge: true },
      )
      .catch(() => undefined);

    logger.warn('Auto-hid reported content', {
      targetType,
      targetId,
      reporters: reporters.size,
    });
  },
);
