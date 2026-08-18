import {
  onDocumentCreated,
  onDocumentDeleted,
} from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

import { REGION } from './config';
import { push } from './notifications';

const db = () => getFirestore();

/**
 * What a message does to the conversation it lands in.
 *
 * Three things at once, and they are one function because they are one write:
 * the inbox row's preview line, the ordering timestamp the inbox sorts on, and
 * everyone else's unread count. Splitting them would mean three triggers on the
 * same document racing each other.
 *
 * `updatedAt` is written here rather than by the client for the same reason
 * `unread` is: it decides inbox order, and a client that sets its own would be
 * a client that can pin itself to the top of everyone's list.
 */
export const onMessageSent = onDocumentCreated(
  { document: 'chats/{chatId}/messages/{messageId}', region: REGION },
  async (event) => {
    const { chatId } = event.params;
    const message = event.data?.data();
    if (!message) return;

    const chatRef = db().doc(`chats/${chatId}`);
    const chat = await chatRef.get();
    if (!chat.exists) return;

    const data = chat.data() ?? {};
    const senderUid = message.author?.uid as string | undefined;
    const memberIds = (data.memberIds as string[]) ?? [];

    // Everyone but the sender. A sender who increments their own count sees a
    // badge on a conversation they are looking at.
    const recipients = memberIds.filter((uid) => uid !== senderUid);

    const preview = previewOf(message);

    await chatRef.set(
      {
        lastMessage: {
          text: preview,
          senderUid: senderUid ?? '',
          senderName: message.author?.name ?? '',
          kind: message.kind ?? 'text',
          at: message.at ?? FieldValue.serverTimestamp(),
        },
        updatedAt: FieldValue.serverTimestamp(),
        unread: Object.fromEntries(
          recipients.map((uid) => [uid, FieldValue.increment(1)]),
        ),
      },
      { merge: true },
    );

    // A pending request is deliberately quiet. Someone who has not accepted a
    // conversation has not agreed to be interrupted by it — the request sits in
    // their Requests tab, and that is the whole point of the gate.
    const acceptedBy = (data.acceptedBy as string[]) ?? [];
    const title =
      data.kind === 'dm'
        ? (message.author?.name ?? 'Brnj')
        : `${message.author?.name ?? ''} · ${data.title ?? ''}`;

    await Promise.all(
      recipients
        .filter((uid) => acceptedBy.includes(uid))
        .map((uid) =>
          push(uid, {
            title,
            body: preview,
            data: { type: 'message', targetId: chatId },
          }).catch(() => undefined),
        ),
    );
  },
);

/**
 * What the inbox row shows.
 *
 * A photo or a voice note has no words, and the alternative — an empty preview
 * line — reads as a bug. The label is English here because Functions have no
 * locale; the client swaps it for a translated one when it recognises the kind,
 * and falls back to this only for a kind it does not know.
 */
function previewOf(message: FirebaseFirestore.DocumentData): string {
  switch (message.kind) {
    case 'image':
      return 'Photo';
    case 'voice':
      return 'Voice note';
    case 'recipe':
      return 'Recipe';
    default:
      return (message.text as string) ?? '';
  }
}

/**
 * Cascade delete.
 *
 * Firestore does not remove a subcollection when its parent goes, so a declined
 * request would otherwise leave its messages behind — unreachable, invisible,
 * and still stored. That is the case this exists for: declining is the most
 * common way a chat document is ever deleted.
 */
export const onChatDeleted = onDocumentDeleted(
  { document: 'chats/{chatId}', region: REGION, timeoutSeconds: 540 },
  async (event) => {
    const { chatId } = event.params;
    try {
      await db().recursiveDelete(db().doc(`chats/${chatId}`));
    } catch (error) {
      logger.error('chat cleanup failed', { chatId, error });
    }
  },
);
