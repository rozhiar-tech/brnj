import '../../data/models/chat.dart';
import '../../l10n/gen/app_localizations.dart';

/// What a non-text message reads as in a list.
///
/// The Function writes an English fallback into `lastMessage.text` because it
/// has no locale to work with. The client knows the kind, so it replaces that
/// with a translated word and only ever falls back to what the server wrote
/// for a kind it does not recognise.
String messageKindLabel(AppLocalizations l10n, MessageKind kind) =>
    switch (kind) {
      MessageKind.image => l10n.chatMessagePhoto,
      MessageKind.voice => l10n.chatMessageVoice,
      MessageKind.recipe => l10n.chatMessageRecipe,
      MessageKind.text || MessageKind.system => '',
    };

/// The preview line for one conversation.
String chatPreview(AppLocalizations l10n, Chat chat) {
  final last = chat.lastMessage;
  if (last == null) return '';
  final label = messageKindLabel(l10n, last.kind);
  return label.isEmpty ? last.text : label;
}
