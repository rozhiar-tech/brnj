import 'package:brnj/data/models/chat.dart';
import 'package:brnj/data/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const me = AuthorStub(uid: 'aaa', name: 'أم علي');
  const them = AuthorStub(uid: 'zzz', name: 'ژیان', verified: true);

  Chat dm({List<String> acceptedBy = const ['aaa']}) => Chat(
    id: Chat.dmId(me.uid, them.uid),
    kind: ChatKind.dm,
    memberIds: [me.uid, them.uid],
    members: {me.uid: me, them.uid: them},
    acceptedBy: acceptedBy,
    createdBy: me.uid,
  );

  group('dmId', () {
    test('is the same string whichever side computes it', () {
      // The whole design rests on this. If the two sides disagreed, both would
      // create a conversation and neither would see the other's messages.
      expect(Chat.dmId('aaa', 'zzz'), Chat.dmId('zzz', 'aaa'));
    });

    test('sorts the two uids', () {
      expect(Chat.dmId('zzz', 'aaa'), 'aaa_zzz');
    });

    test('matches what the security rule reconstructs', () {
      // The rule builds the id from the sorted memberIds and compares. A model
      // that formatted it differently would make every DM unwritable.
      const a = 'user1';
      const b = 'user2';
      final sorted = [a, b]..sort();
      expect(Chat.dmId(a, b), '${sorted[0]}_${sorted[1]}');
    });

    test('gives a community room a derivable id too', () {
      expect(Chat.communityRoomId('c1'), 'community_c1');
    });
  });

  group('toCreateMap', () {
    test('omits the three fields the rules refuse on create', () {
      // unread, lastMessage, and updatedAt are Function-owned. A model that
      // serialised any of them would make starting a conversation impossible.
      final map = dm().toCreateMap();

      expect(map.containsKey('unread'), isFalse);
      expect(map.containsKey('lastMessage'), isFalse);
      expect(map.containsKey('updatedAt'), isFalse);
    });

    test('carries only the initiator in acceptedBy', () {
      // Two entries here would put the conversation straight into the other
      // person's inbox — the request gate removed.
      final map = dm().toCreateMap();

      expect(map['acceptedBy'], ['aaa']);
    });

    test('writes memberIds as an array for the array-contains query', () {
      final map = dm().toCreateMap();

      expect(map['memberIds'], ['aaa', 'zzz']);
      expect((map['members'] as Map).keys.toSet(), {'aaa', 'zzz'});
    });
  });

  group('the other side of a DM', () {
    test('is whoever is not you', () {
      expect(dm().otherParty('aaa')?.uid, 'zzz');
      expect(dm().otherParty('zzz')?.uid, 'aaa');
    });

    test('is null in a group, which has no single other side', () {
      const group = Chat(
        id: 'g1',
        kind: ChatKind.group,
        memberIds: ['aaa', 'zzz'],
        members: {'aaa': me, 'zzz': them},
        createdBy: 'aaa',
        title: 'طبخات الجمعة',
      );

      expect(group.otherParty('aaa'), isNull);
      expect(group.displayTitle('aaa'), 'طبخات الجمعة');
    });

    test('a DM borrows the other person’s name for its title', () {
      expect(dm().displayTitle('aaa'), 'ژیان');
    });

    test('survives the other side having deleted their account', () {
      // The member map loses its entry; the id list may not. Returning an
      // empty title beats throwing on a row in the inbox.
      final orphan = Chat(
        id: Chat.dmId('aaa', 'zzz'),
        kind: ChatKind.dm,
        memberIds: const ['aaa', 'zzz'],
        members: const {'aaa': me},
        createdBy: 'aaa',
      );

      expect(orphan.otherParty('aaa'), isNull);
      expect(orphan.displayTitle('aaa'), '');
    });
  });

  group('membership and badges', () {
    test('hasAccepted tells a request from a conversation', () {
      expect(dm().hasAccepted('aaa'), isTrue);
      expect(dm().hasAccepted('zzz'), isFalse);
      expect(dm(acceptedBy: const ['aaa', 'zzz']).hasAccepted('zzz'), isTrue);
    });

    test('a guest with no uid is never a member', () {
      expect(dm().isMember(null), isFalse);
      expect(dm().hasAccepted(null), isFalse);
      expect(dm().isAdmin(null), isFalse);
    });

    test('unreadFor reads zero rather than throwing on a missing key', () {
      expect(dm().unreadFor('zzz'), 0);
      expect(dm().unreadFor(null), 0);
    });

    test('a DM creator is not an admin of it', () {
      // Treating them as one let whoever sent the first message accept the
      // conversation on the other person's behalf and delete their replies.
      // The rules were fixed; this pins the model to the same answer.
      expect(dm().createdBy, 'aaa');
      expect(dm().isAdmin('aaa'), isFalse);
    });

    test('a group creator is', () {
      const group = Chat(
        id: 'g1',
        kind: ChatKind.group,
        memberIds: ['aaa', 'zzz'],
        members: {'aaa': me, 'zzz': them},
        createdBy: 'aaa',
        admins: ['aaa'],
        title: 'x',
      );

      expect(group.isAdmin('aaa'), isTrue);
      expect(group.isAdmin('zzz'), isFalse);
    });
  });
}
