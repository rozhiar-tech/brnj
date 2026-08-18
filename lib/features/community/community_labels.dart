import '../../data/models/community.dart';
import '../../l10n/gen/app_localizations.dart';

/// Enum → translated string.
///
/// Kept out of the model so the model stays free of Flutter, and out of the
/// widgets so four screens can't drift into four different words for the same
/// category.
String categoryLabel(AppLocalizations l10n, CommunityCategory category) =>
    switch (category) {
      CommunityCategory.regional => l10n.communityCategoryRegional,
      CommunityCategory.everyday => l10n.communityCategoryEveryday,
      CommunityCategory.baking => l10n.communityCategoryBaking,
      CommunityCategory.occasions => l10n.communityCategoryOccasions,
      CommunityCategory.health => l10n.communityCategoryHealth,
      CommunityCategory.budget => l10n.communityCategoryBudget,
      CommunityCategory.beginners => l10n.communityCategoryBeginners,
      CommunityCategory.other => l10n.communityCategoryOther,
    };

String privacyLabel(AppLocalizations l10n, CommunityPrivacy privacy) =>
    switch (privacy) {
      CommunityPrivacy.public => l10n.communityPrivacyPublic,
      CommunityPrivacy.private => l10n.communityPrivacyPrivate,
    };

String joinPolicyLabel(AppLocalizations l10n, JoinPolicy policy) =>
    switch (policy) {
      JoinPolicy.open => l10n.communityJoinOpen,
      JoinPolicy.approval => l10n.communityJoinApproval,
    };

String postTypeLabel(AppLocalizations l10n, PostType type) => switch (type) {
  PostType.text => l10n.postTypeText,
  PostType.photo => l10n.postTypePhoto,
  PostType.recipe => l10n.postTypeRecipe,
  PostType.question => l10n.postTypeQuestion,
};

/// Owner and moderator get a label; a plain member does not. A badge everyone
/// wears is not a badge.
String? roleLabel(AppLocalizations l10n, MemberRole role) => switch (role) {
  MemberRole.owner => l10n.communityRoleOwner,
  MemberRole.moderator => l10n.communityRoleModerator,
  MemberRole.member => null,
};
