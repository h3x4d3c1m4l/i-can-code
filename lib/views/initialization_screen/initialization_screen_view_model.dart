import 'package:i_can_code/views/base/screen_view_model_base.dart';
import 'package:mobx/mobx.dart';

part 'initialization_screen_view_model.g.dart';

/// What the bootstrap is doing. An identity rather than a message: the
/// controller has no [BuildContext] and so cannot localize.
enum InitializationStep { loadingCourse, startingRuntime }

class InitializationScreenViewModel = InitializationScreenViewModelBase with _$InitializationScreenViewModel;

abstract class InitializationScreenViewModelBase extends ScreenViewModelBase with Store {

  /// The bootstrap step in flight, or `null` before the first one reports in.
  @readonly
  InitializationStep? _step;

  /// How often the current step has been retried. 0 on the first attempt.
  @readonly
  int _retries = 0;

  /// Set when a step gave up, which stops the screen and offers a retry.
  @readonly
  String? _error;

  InitializationScreenViewModelBase({required super.contextAccessor});

  @action
  void setStep(InitializationStep step, {int retries = 0}) {
    _step = step;
    _retries = retries;
    _error = null;
  }

  @action
  void setError(String error) => _error = error;

  @action
  void reset() {
    _step = null;
    _retries = 0;
    _error = null;
  }

}
