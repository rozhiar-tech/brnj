import 'package:brnj/data/models/community.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Community make({
    String createdBy = 'owner1',
    List<String> moderators = const [],
    JoinPolicy joinPolicy = JoinPolicy.open,
    CommunityPrivacy privacy = CommunityPrivacy.public,
    int memberCount = 40,
    int postCount = 12,
  }) => Community(
    id: 'c1',
    name: '  مطابخ بغداد  ',
    createdBy: createdBy,
    description: ' من الكرادة إلى الأعظمية ',
    category: CommunityCategory.regional,
    privacy: privacy,
    joinPolicy: joinPolicy,
    rules: const ['بدون إعلانات'],
    moderators: moderators,
    memberCount: memberCount,
    postCount: postCount,
  );

  group('toMap', () {
    test('omits the counters the security rules refuse on create', () {
      // Not cosmetic: the create rule rejects any document arriving with
      // memberCount or postCount, so a model that serialised them would make
      // creating a community impossible.
      final map = make().toMap();

      expect(map.containsKey('memberCount'), isFalse);
      expect(map.containsKey('postCount'), isFalse);
    });

    test('trims the name and description', () {
      final map = make().toMap();

      expect(map['name'], 'مطابخ بغداد');
      expect(map['description'], 'من الكرادة إلى الأعظمية');
    });

    test('writes a lowercased searchName for the prefix query', () {
      final map = const Community(
        id: 'c1',
        name: '  Baghdad Kitchens ',
        createdBy: 'owner1',
      ).toMap();

      expect(map['searchName'], 'baghdad kitchens');
    });

    test('serialises enums by name, which is what the rules compare against', () {
      final map = make(
        joinPolicy: JoinPolicy.approval,
        privacy: CommunityPrivacy.private,
      ).toMap();

      expect(map['joinPolicy'], 'approval');
      expect(map['privacy'], 'private');
      expect(map['category'], 'regional');
    });

    test('leaves out an absent description rather than writing null', () {
      final map = const Community(id: 'c1', name: 'X', createdBy: 'o').toMap();

      expect(map.containsKey('description'), isFalse);
      expect(map.containsKey('region'), isFalse);
    });
  });

  group('moderatedBy', () {
    test('is true for the creator', () {
      expect(make().moderatedBy('owner1'), isTrue);
    });

    test('is true for an appointed moderator', () {
      expect(make(moderators: ['mod1']).moderatedBy('mod1'), isTrue);
    });

    test('is false for a plain member', () {
      expect(make(moderators: ['mod1']).moderatedBy('member1'), isFalse);
    });

    test('is false for a signed-out viewer', () {
      // Guests read null from currentUidProvider, and a null that slipped
      // through would hand moderator controls to everyone browsing.
      expect(make().moderatedBy(null), isFalse);
    });
  });

  group('reading a stored community', () {
    test('falls back to safe defaults when fields are missing', () {
      // A community written by an older build, or one whose optional fields
      // were never set. Defaulting privacy to private or joinPolicy to open
      // are both wrong in different directions; public/open matches what the
      // form writes, and the counters read zero rather than throwing.
      const community = Community(id: 'c1', name: 'X', createdBy: 'o');

      expect(community.privacy, CommunityPrivacy.public);
      expect(community.joinPolicy, JoinPolicy.open);
      expect(community.category, CommunityCategory.other);
      expect(community.memberCount, 0);
      expect(community.isPrivate, isFalse);
      expect(community.needsApproval, isFalse);
    });

    test('needsApproval follows the join policy', () {
      expect(make(joinPolicy: JoinPolicy.approval).needsApproval, isTrue);
    });
  });

  group('copyWith', () {
    test('keeps the counters and ownership it is not allowed to change', () {
      final edited = make(
        moderators: ['mod1'],
      ).copyWith(name: 'Renamed', privacy: CommunityPrivacy.private);

      expect(edited.name, 'Renamed');
      expect(edited.privacy, CommunityPrivacy.private);
      // The settings form round-trips through copyWith, and dropping these
      // would show every community as empty the moment anyone edited it.
      expect(edited.memberCount, 40);
      expect(edited.postCount, 12);
      expect(edited.createdBy, 'owner1');
      expect(edited.moderators, ['mod1']);
    });
  });
}
