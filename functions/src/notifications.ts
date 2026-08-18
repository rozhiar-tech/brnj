import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';

import { REGION } from './config';

const db = () => getFirestore();

type Notification = {
  type:
    | 'like'
    | 'cooked'
    | 'comment'
    | 'follow'
    | 'planCopied'
    | 'communityJoinRequest'
    | 'communityApproved'
    | 'communityPost';
  actorUid: string;
  actorName?: string;
  targetId?: string;
  body?: string;
};

/**
 * Writes the notification document and pushes it.
 *
 * A client cannot send FCM — that needs a private key, and a key shipped inside
 * a Flutter app is a public key. This is the reason the project needs Cloud
 * Functions at all.
 *
 * The document is written even when there is no token to push to: the in-app
 * list is the durable record, and push is a courtesy on top of it.
 */
export async function notify(uid: string, notification: Notification) {
  // Nobody needs telling about their own actions.
  if (uid === notification.actorUid) return;

  const firestore = db();

  await firestore.collection(`users/${uid}/notifications`).add({
    ...notification,
    read: false,
    at: FieldValue.serverTimestamp(),
  });

  const tokens = await firestore.collection(`users/${uid}/tokens`).get();
  if (tokens.empty) return;

  const response = await getMessaging().sendEachForMulticast({
    tokens: tokens.docs.map((d) => d.id),
    notification: {
      title: notification.actorName ?? 'Brnj',
      body: notification.body ?? '',
    },
    data: {
      type: notification.type,
      targetId: notification.targetId ?? '',
    },
  });

  // A token that fails permanently belongs to an app that was uninstalled or a
  // device that rotated it. Left in place they accumulate forever and every
  // send pays for them.
  const stale: string[] = [];
  response.responses.forEach((result, i) => {
    const code = result.error?.code;
    if (
      code === 'messaging/registration-token-not-registered' ||
      code === 'messaging/invalid-registration-token'
    ) {
      stale.push(tokens.docs[i].id);
    }
  });

  await Promise.all(
    stale.map((token) =>
      firestore.doc(`users/${uid}/tokens/${token}`).delete().catch(() => undefined),
    ),
  );

  if (stale.length > 0) {
    logger.info('Pruned stale tokens', { uid, count: stale.length });
  }
}

const authorOf = async (recipeId: string) => {
  const doc = await db().doc(`recipes/${recipeId}`).get();
  return {
    uid: doc.get('author.uid') as string | undefined,
    title: doc.get('title') as string | undefined,
  };
};

const nameOf = async (uid: string) =>
  ((await db().doc(`users/${uid}`).get()).get('displayName') as string) ?? '';

export const notifyOnLike = onDocumentCreated(
  { document: 'recipes/{recipeId}/likes/{uid}', region: REGION },
  async (event) => {
    const { recipeId, uid } = event.params;
    const { uid: author, title } = await authorOf(recipeId);
    if (!author) return;

    await notify(author, {
      type: 'like',
      actorUid: uid,
      actorName: await nameOf(uid),
      targetId: recipeId,
      body: title,
    });
  },
);

/// "I cooked this" is the one worth interrupting someone for — it is the
/// strongest signal in the app, and the reply it invites is what pulls the
/// author back in.
export const notifyOnCooked = onDocumentCreated(
  { document: 'recipes/{recipeId}/cooked/{uid}', region: REGION },
  async (event) => {
    const { recipeId, uid } = event.params;
    const { uid: author, title } = await authorOf(recipeId);
    if (!author) return;

    await notify(author, {
      type: 'cooked',
      actorUid: uid,
      actorName: await nameOf(uid),
      targetId: recipeId,
      body: title,
    });
  },
);

export const notifyOnComment = onDocumentCreated(
  { document: 'recipes/{recipeId}/comments/{commentId}', region: REGION },
  async (event) => {
    const { recipeId } = event.params;
    const comment = event.data?.data();
    const actorUid = comment?.author?.uid as string | undefined;
    if (!actorUid) return;

    const { uid: author } = await authorOf(recipeId);
    if (!author) return;

    await notify(author, {
      type: 'comment',
      actorUid,
      actorName: comment?.author?.name,
      targetId: recipeId,
      body: comment?.text,
    });
  },
);

export const notifyOnFollow = onDocumentCreated(
  { document: 'users/{uid}/following/{targetUid}', region: REGION },
  async (event) => {
    const { uid, targetUid } = event.params;
    await notify(targetUid, {
      type: 'follow',
      actorUid: uid,
      actorName: await nameOf(uid),
      targetId: uid,
    });
  },
);
