import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import 'localization.dart';
import 'router.dart';
import 'settings.dart';
import 'theme/brnj_theme.dart';

class BrnjApp extends ConsumerStatefulWidget {
  const BrnjApp({super.key});

  @override
  ConsumerState<BrnjApp> createState() => _BrnjAppState();
}

class _BrnjAppState extends ConsumerState<BrnjApp> {
  late final _router = createRouter();

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeLocaleProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,

      theme: BrnjTheme.light(),
      darkTheme: BrnjTheme.dark(),
      // Dark mode from day one — people cook and scroll at night.
      themeMode: ThemeMode.system,

      locale: active.locale,
      supportedLocales: AppLocale.supported,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        // Must come before the Global* delegates: they reject ckb and kmr.
        ...kurdishFallbackDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeListResolutionCallback: resolveLocale,

      routerConfig: _router,

      builder: (context, child) {
        // Three of the four locales are RTL, so direction is derived from the
        // active locale rather than left to chance. Widgets below must use
        // start/end and EdgeInsetsDirectional — never left/right.
        return Directionality(
          textDirection: active.textDirection,
          // Cap text scaling: recipe steps and ingredient rows have to stay
          // laid out at accessibility sizes, and unbounded scaling breaks them.
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: 0.8,
            maxScaleFactor: 1.6,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
