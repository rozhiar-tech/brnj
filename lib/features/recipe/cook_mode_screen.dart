import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/settings.dart';
import '../../app/theme/brnj_theme.dart';
import '../../core/numerals.dart';
import '../../data/models/recipe.dart';
import '../../data/providers.dart';
import '../../l10n/gen/app_localizations.dart';

final _cookRecipeProvider = StreamProvider.family<Recipe?, String>(
  (ref, id) => ref.watch(recipeRepositoryProvider).watchRecipe(id),
);

/// Cook mode.
///
/// One step at a time, full screen, large type, and the screen kept awake. The
/// person using this has flour on their hands and is standing over a pot —
/// every assumption here follows from that: nothing small to tap, nothing that
/// needs scrolling to read, and no screen timeout mid-step.
class CookModeScreen extends ConsumerStatefulWidget {
  const CookModeScreen({required this.recipeId, super.key});

  final String recipeId;

  @override
  ConsumerState<CookModeScreen> createState() => _CookModeScreenState();
}

class _CookModeScreenState extends ConsumerState<CookModeScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    // The whole point. A screen that sleeps halfway through kneading is the
    // reason people prop a phone against a bag of flour and poke it.
    unawaited(WakelockPlus.enable());
  }

  @override
  void dispose() {
    unawaited(WakelockPlus.disable());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recipeAsync = ref.watch(_cookRecipeProvider(widget.recipeId));

    return Scaffold(
      body: recipeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.errorGeneric)),
        data: (recipe) {
          if (recipe == null || recipe.steps.isEmpty) {
            return Center(child: Text(l10n.errorGeneric));
          }

          return SafeArea(
            child: Column(
              children: [
                _CookHeader(
                  title: recipe.title,
                  step: _page + 1,
                  total: recipe.steps.length,
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: recipe.steps.length,
                    onPageChanged: (page) => setState(() => _page = page),
                    itemBuilder: (context, i) =>
                        _CookStep(step: recipe.steps[i], index: i),
                  ),
                ),
                _CookFooter(
                  page: _page,
                  total: recipe.steps.length,
                  onBack: () => _controller.previousPage(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  ),
                  onNext: () => _controller.nextPage(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  ),
                  onDone: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CookHeader extends ConsumerWidget {
  const _CookHeader({
    required this.title,
    required this.step,
    required this.total,
  });

  final String title;
  final int step;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final numerals = ref.watch(numeralStyleProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.sm, Gap.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '$step / $total'.toNumeralStyle(numerals),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            iconSize: 28,
          ),
        ],
      ),
    );
  }
}

class _CookStep extends StatelessWidget {
  const _CookStep({required this.step, required this.index});

  final RecipeStep step;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Gap.lg),
          if (step.imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CachedNetworkImage(
                imageUrl: step.imageUrl!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: Gap.xl),
          ],
          Text(
            step.text,
            // Roughly double body size. Readable at arm's length, which is
            // where the phone is when both hands are busy.
            style: theme.textTheme.headlineSmall?.copyWith(height: 1.4),
          ),
          if (step.timerSeconds != null) ...[
            const SizedBox(height: Gap.xxl),
            StepTimer(seconds: step.timerSeconds!),
          ],
          const SizedBox(height: Gap.xxl),
        ],
      ),
    );
  }
}

/// A live countdown for one step.
///
/// Runs in the screen rather than as a system alarm: the person is standing
/// here, and a countdown they can see beats a notification they have to unlock
/// the phone to read. Haptics fire at zero because a kitchen is loud.
class StepTimer extends ConsumerStatefulWidget {
  const StepTimer({required this.seconds, super.key});

  final int seconds;

  @override
  ConsumerState<StepTimer> createState() => _StepTimerState();
}

class _StepTimerState extends ConsumerState<StepTimer> {
  late int _remaining = widget.seconds;
  Timer? _ticker;
  bool _finished = false;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool get _running => _ticker?.isActive ?? false;

  void _toggle() {
    if (_running) {
      _ticker?.cancel();
      setState(() {});
      return;
    }

    if (_finished) {
      setState(() {
        _remaining = widget.seconds;
        _finished = false;
      });
    }

    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remaining <= 1) {
        timer.cancel();
        HapticFeedback.heavyImpact();
        setState(() {
          _remaining = 0;
          _finished = true;
        });
        return;
      }
      setState(() => _remaining -= 1);
    });
    setState(() {});
  }

  void _reset() {
    _ticker?.cancel();
    setState(() {
      _remaining = widget.seconds;
      _finished = false;
    });
  }

  String _format(NumeralStyle numerals) {
    final minutes = (_remaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_remaining % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds'.toNumeralStyle(numerals);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final numerals = ref.watch(numeralStyleProvider);
    final progress = widget.seconds == 0 ? 0.0 : _remaining / widget.seconds;

    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: _finished
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 4,
              backgroundColor: theme.colorScheme.outlineVariant,
            ),
          ),
          const SizedBox(width: Gap.lg),
          Expanded(
            child: Text(
              _format(numerals),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (_remaining != widget.seconds)
            IconButton(
              onPressed: _reset,
              icon: const Icon(Icons.replay),
              iconSize: 26,
            ),
          IconButton.filled(
            onPressed: _toggle,
            icon: Icon(_running ? Icons.pause : Icons.play_arrow),
            iconSize: 26,
          ),
        ],
      ),
    );
  }
}

class _CookFooter extends StatelessWidget {
  const _CookFooter({
    required this.page,
    required this.total,
    required this.onBack,
    required this.onNext,
    required this.onDone,
  });

  final int page;
  final int total;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLast = page == total - 1;

    return Padding(
      padding: const EdgeInsets.all(Gap.lg),
      child: Row(
        children: [
          // Big targets: this gets tapped with a knuckle or the side of a
          // thumb as often as a fingertip.
          if (page > 0)
            Expanded(
              child: SizedBox(
                height: 60,
                child: OutlinedButton(
                  onPressed: onBack,
                  child: Text(l10n.composerBack),
                ),
              ),
            ),
          if (page > 0) const SizedBox(width: Gap.md),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 60,
              child: FilledButton(
                onPressed: isLast ? onDone : onNext,
                child: Text(isLast ? l10n.cookModeDone : l10n.composerNext),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
