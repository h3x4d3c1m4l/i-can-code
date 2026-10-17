import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/catalog_screen/catalog_screen_controller.dart';
import 'package:i_can_code/views/catalog_screen/catalog_screen_view_model.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _Route extends Fake implements RouteData {

  @override
  final String name;

  _Route(this.name);

}

/// The router the catalog pushes onto. Like auto_route's own, a push lands on
/// the stack after the guards have answered, a microtask later, and resolves
/// only once the page is popped.
class _Router extends Fake with ChangeNotifier implements StackRouter {

  final List<RouteData> _stack = [];
  final List<PageRouteInfo> pushed = [];

  @override
  List<RouteData> get stackData => List.unmodifiable(_stack);

  @override
  Future<T?> push<T extends Object?>(PageRouteInfo route, {OnNavigationFailure? onFailure}) {
    pushed.add(route);
    scheduleMicrotask(() {
      _stack.add(_Route(route.routeName));
      notifyListeners();
    });
    return Completer<T?>().future;
  }

  /// What `replaceAll` does to a page above the catalog: gone, never popped.
  void removeTop() {
    _stack.removeLast();
    notifyListeners();
  }

}

void main() {
  late _Router router;
  late CatalogScreenController controller;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    GetIt.I.registerSingleton<ProgressStore>(ProgressStore());
    router = _Router();
  });

  tearDown(() async {
    router.dispose();
    await GetIt.I.reset();
  });

  Future<void> open(WidgetTester tester) async {
    final accessor = BuildContextAccessor();
    await tester.pumpWidget(
      StackRouterScope(
        controller: router,
        stateHash: 0,
        child: Builder(
          builder: (context) {
            accessor.buildContext = context;
            return const SizedBox();
          },
        ),
      ),
    );
    controller = CatalogScreenController(
      viewModel: CatalogScreenViewModel(contextAccessor: accessor, subjectSlug: 'learn-python'),
      contextAccessor: accessor,
    );
  }

  group('the Tkinter page', () {
    testWidgets('opens once for a double tap, before the first push has landed', (tester) async {
      await open(tester);

      unawaited(controller.openTkinter());
      unawaited(controller.openTkinter());
      await tester.pump();

      expect(router.pushed, hasLength(1), reason: 'a second page would destroy the first one\'s machine');
    });

    testWidgets('opens once while it is on the stack', (tester) async {
      await open(tester);

      unawaited(controller.openTkinter());
      await tester.pump();
      unawaited(controller.openTkinter());
      await tester.pump();

      expect(router.pushed, hasLength(1));
      expect(router.pushed.single.routeName, TkinterRoute.name);
    });

    testWidgets('opens again once it has gone, even though its push never resolved', (tester) async {
      await open(tester);
      unawaited(controller.openTkinter());
      await tester.pump();

      router.removeTop();
      unawaited(controller.openTkinter());
      await tester.pump();

      expect(router.pushed, hasLength(2));
    });
  });
}
