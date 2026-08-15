import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

import { REGION } from './config';

const db = () => getFirestore();

/// How many events one run drains. Firestore batches cap at 500 writes and a
/// single event can cost three (counter, viewer doc, delete), so this stays
/// well under.
const BATCH_LIMIT = 120;

type ViewEvent = {
  uid: string;
  targetType: 'recipe' | 'plan' | 'post';
  targetId: string;
  anonymous?: boolean;
  action?: string;
};

const collectionFor = (type: ViewEvent['targetType']) =>
  type === 'plan' ? 'plans' : type === 'post' ? 'posts' : 'recipes';

/**
 * Drains the viewEvents queue into counters.
 *
 * The client appends events and never touches a counter — a client that can
 * write its own view count will write its own view count. Aggregating on a
 * schedule rather than per-event is what keeps this cheap: a trending recipe
 * gets one write per run instead of one per viewer, which also keeps it under
 * Firestore's ~1 write/second per-document ceiling.
 */
export const aggregateViewEvents = onSchedule(
  { schedule: 'every 5 minutes', timeoutSeconds: 300, region: REGION },
  async () => {
    const firestore = db();
    const snapshot = await firestore
      .collection('viewEvents')
      .orderBy('at')
      .limit(BATCH_LIMIT)
      .get();

    if (snapshot.empty) return;

    // Group first so a hot recipe costs one increment rather than fifty.
    const views = new Map<string, number>();
    const copies = new Map<string, number>();
    const viewers = new Map<string, Set<string>>();

    for (const doc of snapshot.docs) {
      const event = doc.data() as ViewEvent;
      if (!event.targetId || !event.targetType) continue;

      const path = `${collectionFor(event.targetType)}/${event.targetId}`;

      if (event.action === 'copy') {
        copies.set(path, (copies.get(path) ?? 0) + 1);
        continue;
      }

      views.set(path, (views.get(path) ?? 0) + 1);

      // Guests raise the count but never join the viewer list.
      if (!event.anonymous && event.uid) {
        if (!viewers.has(path)) viewers.set(path, new Set());
        viewers.get(path)!.add(event.uid);
      }
    }

    // Incognito is checked here rather than trusted from the client flag, so
    // toggling it takes effect on the queue that is already in flight.
    const candidates = [...new Set([...viewers.values()].flatMap((s) => [...s]))];
    const hidden = await incognitoUids(candidates);

    const batch = firestore.batch();

    for (const [path, count] of views) {
      batch.set(
        firestore.doc(path),
        { stats: { views: FieldValue.increment(count) } },
        { merge: true },
      );
    }

    for (const [path, count] of copies) {
      batch.set(
        firestore.doc(path),
        { stats: { copies: FieldValue.increment(count) } },
        { merge: true },
      );
    }

    for (const [path, uids] of viewers) {
      for (const uid of uids) {
        if (hidden.has(uid)) continue;
        // One document per person per item, ever — not one per view. The
        // uniqueViewers counter is maintained by onViewerCreated below.
        batch.set(
          firestore.doc(`${path}/viewers/${uid}`),
          {
            firstAt: FieldValue.serverTimestamp(),
            lastAt: FieldValue.serverTimestamp(),
            count: FieldValue.increment(1),
          },
          { merge: true },
        );
      }
    }

    for (const doc of snapshot.docs) batch.delete(doc.ref);

    await batch.commit();
    logger.info('Aggregated view events', {
      events: snapshot.size,
      targets: views.size,
    });
  },
);

async function incognitoUids(uids: string[]): Promise<Set<string>> {
  const hidden = new Set<string>();
  if (uids.length === 0) return hidden;

  const firestore = db();
  const refs = uids.map((uid) => firestore.doc(`users/${uid}`));
  const docs = await firestore.getAll(...refs);

  for (const doc of docs) {
    if (doc.get('privacy.incognito') === true) hidden.add(doc.id);
  }
  return hidden;
}
