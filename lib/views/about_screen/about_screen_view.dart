import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/app_info.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/microbit/microbit_firmware.dart';
import 'package:i_can_code/services/vm/vm_image.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/about_screen/about_screen_controller.dart';
import 'package:i_can_code/views/about_screen/about_screen_view_model.dart';
import 'package:i_can_code/views/about_screen/components/about_card.dart';
import 'package:i_can_code/views/base/screen_view_base.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/components/app_header_publisher.dart';
import 'package:i_can_code/views/components/text_link.dart';

class AboutScreenView extends ScreenViewBase<AboutScreenViewModel, AboutScreenController> {

  /// Wide enough for a nightly's `rustc -V` on one line beside its name.
  static const double _maxWidth = 760;

  const AboutScreenView({required super.viewModel, required super.controller, required super.contextAccessor});

  @override
  Widget get body {
    return AppHeaderPublisher(builder: _buildHeader, child: Observer(builder: _buildContent));
  }

  AppHeaderConfig _buildHeader(BuildContext context) {
    return AppHeaderConfig(
      onTapHome: controller.goHome,
      crumbs: [AppCrumb(context.localizations.aboutScreen_title)],
    );
  }

  Widget _buildContent(BuildContext context) {
    final l10n = context.localizations;
    final muted = context.theme.colors.mutedForeground;

    // A version that has to be asked for: loading, then the answer or unknown.
    Widget asked(String? version, {required bool loaded}) => switch ((version, loaded)) {
      (final version?, _) => Text(version),
      (null, false) => Text(l10n.aboutScreen_loading, style: TextStyle(color: muted)),
      (null, true) => Text(l10n.aboutScreen_unknown, style: TextStyle(color: muted)),
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, AppHeader.height + 40, 32, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 32,
            children: [
              Text(l10n.aboutScreen_title, style: context.appTheme.text.h1.copyWith(fontSize: 42)),
              AboutCard(
                title: l10n.aboutScreen_appHeading,
                children: [
                  AboutRow(label: l10n.aboutScreen_version, value: asked(appVersion, loaded: true)),
                  Wrap(
                    spacing: 28,
                    runSpacing: 10,
                    children: [
                      TextLink(label: l10n.aboutScreen_source, onPress: controller.openSource, target: TextLinkTarget.tab),
                      TextLink(label: l10n.aboutScreen_licenses, onPress: controller.openLicenses),
                    ],
                  ),
                ],
              ),
              AboutCard(
                title: l10n.aboutScreen_builtWithHeading,
                children: [
                  AboutRow(label: 'Flutter', value: asked(_flutterVersion, loaded: true)),
                  AboutRow(label: 'Rust', value: asked(viewModel.rustc, loaded: viewModel.rustcLoaded)),
                  AboutRow(label: l10n.aboutScreen_compiledTo, value: const Text(kIsWasm ? 'WebAssembly' : 'JavaScript')),
                ],
              ),
              AboutCard(
                title: 'Python',
                children: [
                  AboutRow(
                    label: l10n.aboutScreen_pythonBrowser,
                    value: asked(viewModel.python, loaded: viewModel.pythonLoaded),
                  ),
                  if (vmImageIncluded)
                    AboutRow(
                      label: l10n.aboutScreen_pythonTkinter,
                      value: asked(viewModel.tkinter, loaded: viewModel.tkinterLoaded),
                    ),
                  AboutRow(
                    label: l10n.aboutScreen_pythonMicrobit,
                    value: Text(l10n.aboutScreen_microbitFirmware(kMicrobitFirmwareVersion)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "3.47.4 (stable) · Dart 3.13.3", or null in a build the flutter tool did
  /// not make, which is the only one that leaves these defines out.
  String? get _flutterVersion {
    final flutter = FlutterVersion.version;
    if (flutter == null) return null;

    final channel = FlutterVersion.channel;
    final dart = FlutterVersion.dartVersion;
    return [
      if (channel == null) flutter else '$flutter ($channel)',
      if (dart != null) 'Dart $dart',
    ].join(' · ');
  }

}
