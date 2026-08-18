import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A person's picture, or their initial.
///
/// The initial is not a placeholder for a missing photo — plenty of people
/// here will never upload a face, and the lettered circle has to look like a
/// deliberate avatar at every size it appears in.
///
/// Which is why the type scales with the radius. It used to be a fixed
/// headline size, so at the 12pt radius the comment list uses, the glyph was
/// larger than the circle containing it and sat visibly off-centre.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.photoUrl,
    required this.name,
    this.radius = 44,
    super.key,
  });

  final String? photoUrl;
  final String name;
  final double radius;

  /// Latin initials read better capitalised; Arabic and Kurdish have no case,
  /// and toUpperCase leaves them alone.
  String get _initial =>
      name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: photoUrl!,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          placeholder: (_, _) => _Initial(radius: radius, letter: _initial),
          errorWidget: (_, _, _) => _Initial(radius: radius, letter: _initial),
        ),
      );
    }

    return _Initial(radius: radius, letter: _initial);
  }
}

/// Type size for an avatar of a given radius.
///
/// Roughly nine tenths of the radius: large enough to read at 12pt, small
/// enough that a tall Arabic ط or a Kurdish ڵ stays inside the circle. Exposed
/// so the relationship can be tested rather than eyeballed.
double fontSizeFor(double radius) => radius * 0.9;

class _Initial extends StatelessWidget {
  const _Initial({required this.radius, required this.letter});

  final double radius;
  final String letter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      // The size is computed rather than fitted. FittedBox would also stop
      // the glyph spilling, but it does so by scaling after layout — which
      // makes the mistake invisible to a test, since the measured size is
      // clamped either way. An explicit size can be asserted.
      child: Text(
        letter,
        maxLines: 1,
        style: TextStyle(
          fontSize: fontSizeFor(radius),
          // height: 1 removes the font's leading. Without it the glyph sits
          // low in the circle, which is what "a bit out of place" was.
          height: 1,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
