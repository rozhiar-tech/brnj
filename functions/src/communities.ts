import {
  onDocumentCreated,
  onDocumentDeleted,
} from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

import { REGION } from './config';
import { notify } from './notifications';

const db = () => getFirestore();

/**
 * Community counters and the two notifications worth sending.
 *
 * `memberCount` and `postCount` are flat fields rather than nested under
 * `stats`, so these do not reuse the nested `bump` from counters.ts. Same
 * contract though: security rules refuse a client that writes either, these
 * are the only writer, and the delivery guarantee is at-least-once — a retried
 * event can double-count, which the nightly reconcile sweeps up.
 */
const bump = (cid: string, field: 'memberCount' | 'postCount', by: number) =>
  db()
    .doc(`communities/${cid}`)
    .set({ [field]: FieldValue.increment(by) }, { merge: true })
    .catch(() => undefined); // Community deleted; nothing left to count.

export const onMemberJoined = onDocumentCreated(
  { document: 'communities/{cid}/members/{uid}', region: REGION },
  (event) => bump(event.params.cid, 'memberCount', 1),
);

export const onMemberLeft = onDocumentDeleted(
  { document: 'communities/{cid}/members/{uid}', region: REGION },
  (event) => bump(event.params.cid, 'memberCount', -1),
);

export const onCommunityPostCreated = onDocumentCreated(
  { document: 'communities/{cid}/posts/{postId}', region: REGION },
  (event) => bump(event.params.cid, 'postCount', 1),
);

export const onCommunityPostDeleted = onDocumentDeleted(
  { document: 'communities/{cid}/posts/{postId}', region: REGION },
  (event) => bump(event.params.cid, 'postCount', -1),
);

const bumpPostComments = (cid: string, postId: string, by: number) =>
  db()
    .doc(`communities/${cid}/posts/${postId}`)
    .set({ commentCount: FieldValue.increment(by) }, { merge: true })
    .catch(() => undefined);

export const onCommunityPostCommentCreated = onDocumentCreated(
  {
    document: 'communities/{cid}/posts/{postId}/comments/{commentId}',
    region: REGION,
  },
  (event) => bumpPostComments(event.params.cid, event.params.postId, 1),
);

export const onCommunityPostCommentDeleted = onDocumentDeleted(
  {
    document: 'communities/{cid}/posts/{postId}/comments/{commentId}',
    region: REGION,
  },
  (event) => bumpPostComments(event.params.cid, event.params.postId, -1),
);

/**
 * Somebody is waiting at the door.
 *
 * Without this, an approval-gated community only works if a moderator thinks
 * to go and look — which they will do twice and then stop, and the queue
 * becomes a place requests go to die. Every moderator is told, because a
 * community whose one active moderator is asleep still needs to let people in.
 */
export const notifyOnJoinRequest = onDocumentCreated(
  { document: 'communities/{cid}/requests/{uid}', region: REGION },
  async (event) => {
    const { cid, uid } = event.params;
    const request = event.data?.data();

    const community = await db().doc(`communities/${cid}`).get();
    if (!community.exists) return;

    const data = community.data() ?? {};
    const recipients: string[] = [
      data.createdBy,
      ...((data.moderators as string[]) ?? []),
    ].filter(Boolean);

    await Promise.all(
      // Deduplicated: the owner is usually also in `moderators` once they have
      // promoted anyone, and telling them twice about one request is a bug
      // people notice.
      [...new Set(recipients)].map((moderatorUid) =>
        notify(moderatorUid, {
          type: 'communityJoinRequest',
          actorUid: uid,
          actorName: request?.author?.name,
          targetId: cid,
          body: data.name,
        }),
      ),
    );
  },
);

/**
 * Approved.
 *
 * Fires on the member document rather than on the request being deleted: the
 * approve path writes both in one batch, and the member document is the one
 * that means the person is actually in. Only approval-gated communities send
 * it — in an open one the person joined themselves a moment ago and does not
 * need telling.
 */
export const notifyOnMemberApproved = onDocumentCreated(
  { document: 'communities/{cid}/members/{uid}', region: REGION },
  async (event) => {
    const { cid, uid } = event.params;

    const community = await db().doc(`communities/${cid}`).get();
    if (!community.exists) return;

    const data = community.data() ?? {};
    if (data.joinPolicy !== 'approval') return;

    await notify(uid, {
      type: 'communityApproved',
      // The actor is the community itself as far as the person cares. Using
      // its creator keeps notify()'s "don't tell someone about their own
      // action" check meaningful — a creator adding themselves stays silent.
      actorUid: data.createdBy ?? '',
      actorName: data.name,
      targetId: cid,
      body: data.name,
    });
  },
);

/**
 * Cascade delete.
 *
 * Firestore does not remove subcollections when their parent document goes, so
 * without this a deleted community leaves its members, posts, and every
 * comment under them orphaned — invisible, unreachable, and still billed for.
 *
 * `recursiveDelete` is the Admin SDK's own batched traversal; it handles the
 * paging that made the naive version time out on anything with real history.
 */
export const onCommunityDeleted = onDocumentDeleted(
  { document: 'communities/{cid}', region: REGION, timeoutSeconds: 540 },
  async (event) => {
    const { cid } = event.params;
    try {
      await db().recursiveDelete(db().doc(`communities/${cid}`));
    } catch (error) {
      // Logged rather than rethrown: a retry re-runs a delete that has already
      // removed most of the tree, and the leftovers are invisible either way.
      logger.error('community cleanup failed', { cid, error });
    }
  },
);
