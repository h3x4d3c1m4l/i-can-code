import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:i_can_code/app_info.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/licenses/license_catalog.dart';
import 'package:i_can_code/views/base/screen_controller_base.dart';
import 'package:i_can_code/views/licenses_screen/licenses_screen_view_model.dart';
import 'package:url_launcher/url_launcher.dart';

class LicensesScreenController extends ScreenControllerBase<LicensesScreenViewModel> {

  bool _disposed = false;

  LicensesScreenController({required super.viewModel, required super.contextAccessor}) {
    unawaited(load());
  }

  /// Reads the registry. Run on arrival, and again from the retry button.
  ///
  /// Here and not on the initialization screen: Flutter's own NOTICES is over
  /// a megabyte, and a reader who never opens this screen must not wait for it.
  Future<void> load() async {
    viewModel.setLoading();

    try {
      final catalog = await LicenseCatalog.load();
      if (!_disposed) viewModel.setCatalog(catalog);
    } on Object {
      // Whatever it was, the screen says the same thing: an asset the build
      // should have carried is not there, and trying again is all there is.
      if (!_disposed) viewModel.setFailed();
    }
  }

  void pick(LicensedComponent component) => viewModel.pick(component);

  /// Back from one component to the list, where the two do not fit side by
  /// side.
  void showList() => viewModel.pick(null);

  void search(String query) => viewModel.setQuery(query);

  /// The app's source, in a new tab: the reader is not done with this one.
  Future<void> openSource() => launchUrl(Uri.parse(kSourceUrl));

  /// Back to the subject picker, which is the app's home.
  Future<void> goHome() async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([const SubjectsRoute()]);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

}
