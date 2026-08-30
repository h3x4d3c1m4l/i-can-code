import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/routing/app_router.dart';
import 'package:i_can_code/services/locale_controller.dart';
import 'package:i_can_code/theme/theme.dart';

/// The app shell.
///
/// [WidgetsApp] rather than `MaterialApp`, so a stray Material widget looks
/// wrong instead of quietly theming itself. forui ships no app widget, so
/// [FTheme] goes inside as the `builder`.
class ICanCodeApp extends StatefulWidget {

  const ICanCodeApp({super.key});

  @override
  State<ICanCodeApp> createState() => _ICanCodeAppState();

}

class _ICanCodeAppState extends State<ICanCodeApp> {

  final AppRouter _router = GetIt.I<AppRouter>();
  final FThemeData _theme = buildAppTheme();

  @override
  Widget build(BuildContext context) {
    // Observed so the header's NL/EN toggle re-localizes the whole app at once.
    return Observer(
      builder: (context) => WidgetsApp.router(
        title: 'I Can Code',
        color: _theme.colors.primary,
        locale: GetIt.I<LocaleController>().locale,
        routerConfig: _router.config(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          // forui's own strings, for its date and time widgets.
          FLocalizations.delegate,
        ],
        supportedLocales: LocaleControllerBase.supported,
        builder: (context, child) => FTheme(data: _theme, child: child ?? const SizedBox.shrink()),
      ),
    );
  }

}
