import 'package:i_can_code/services/licenses/license_catalog.dart';
import 'package:i_can_code/views/base/screen_view_model_base.dart';
import 'package:mobx/mobx.dart';

part 'licenses_screen_view_model.g.dart';

class LicensesScreenViewModel = LicensesScreenViewModelBase with _$LicensesScreenViewModel;

abstract class LicensesScreenViewModelBase extends ScreenViewModelBase with Store {

  /// Null until the registry has been read, and after a read that failed.
  @readonly
  LicenseCatalog? _catalog;

  /// A read that failed. The screen then offers to try again.
  @readonly
  bool _failed = false;

  /// What the reader picked from the list, or null before they have.
  @readonly
  LicensedComponent? _picked;

  /// What the reader typed into the search field.
  @readonly
  String _query = '';

  LicensesScreenViewModelBase({required super.contextAccessor});

  /// What the wide layout shows beside the list: the reader's pick, or the
  /// first component while they have made none, so the pane is never empty.
  /// That first one is the app's own licence whenever the build carries it.
  @computed
  LicensedComponent? get shown => _picked ?? _catalog?.components.firstOrNull;

  @action
  void setCatalog(LicenseCatalog catalog) {
    _catalog = catalog;
    _failed = false;
  }

  @action
  void setFailed() {
    _catalog = null;
    _failed = true;
  }

  @action
  void setLoading() => _failed = false;

  @action
  void pick(LicensedComponent? component) => _picked = component;

  @action
  void setQuery(String query) => _query = query;

}
