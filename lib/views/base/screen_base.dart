import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/base/screen_controller_base.dart';
import 'package:i_can_code/views/base/screen_view_base.dart';
import 'package:i_can_code/views/base/screen_view_model_base.dart';

abstract class ScreenBase<TViewModel extends ScreenViewModelBase, TController extends ScreenControllerBase<TViewModel>, TView extends ScreenViewBase<TViewModel, TController>> extends StatefulWidget {

  const ScreenBase({super.key});

  TController createController({required TViewModel viewModel, required BuildContextAccessor contextAccessor});

  TViewModel createViewModel({required BuildContextAccessor contextAccessor});

  TView createView({required TController controller, required TViewModel viewModel, required BuildContextAccessor contextAccessor});

  @override
  State<StatefulWidget> createState() => _ScreenBaseState();

}

class _ScreenBaseState<TViewModel extends ScreenViewModelBase, TController extends ScreenControllerBase<TViewModel>, TView extends ScreenViewBase<TViewModel, TController>> extends State<ScreenBase<TViewModel, TController, TView>> {

  late TController _controller;
  late TViewModel _viewModel;
  late TView _view;
  late BuildContextAccessor _contextAccessor;

  @override
  void initState() {
    _contextAccessor = BuildContextAccessor();
    _viewModel = widget.createViewModel(contextAccessor: _contextAccessor);
    _controller = widget.createController(viewModel: _viewModel, contextAccessor: _contextAccessor);
    _view = widget.createView(controller: _controller, viewModel: _viewModel, contextAccessor: _contextAccessor);

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    _contextAccessor.buildContext = context;
    return ColoredBox(
      color: context.theme.colors.background,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.paddingOf(context).top,
            child: Observer(
              builder: (context) {
                final topSafeAreaColor = _view.topSafeAreaColor(context);
                if (topSafeAreaColor == null) return const SizedBox.shrink();
                return ColoredBox(color: topSafeAreaColor);
              },
            ),
          ),
          // The bottom safe-area inset collapses when a keyboard opens. A
          // screen whose layout must not reflow behind one opts into
          // maintainBottomViewPadding via the view.
          SafeArea(
            bottom: _view.bottomSafeArea,
            maintainBottomViewPadding: _view.maintainBottomViewPadding,
            child: _view.body,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();

    _controller.dispose();
    _viewModel.dispose();
    _view.dispose();
  }

}
