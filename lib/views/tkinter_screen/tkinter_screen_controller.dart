import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/editor_settings.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
import 'package:i_can_code/services/vm/vm_image.dart';
import 'package:i_can_code/services/vm/vm_runtime.dart';
import 'package:i_can_code/views/base/screen_controller_base.dart';
import 'package:i_can_code/views/components/vm/vm_session_controller.dart';
import 'package:i_can_code/views/tkinter_screen/tkinter_screen_view_model.dart';

class TkinterScreenController extends ScreenControllerBase<TkinterScreenViewModel> {

  final CodeDraftStore _drafts;

  /// The machine half of the page: the download, the runs and what they report.
  late final VmSessionController machine;

  bool _disposed = false;

  /// Writes the draft out when the app is hidden. That is also the last moment
  /// before ChromeOS discards a tab this heavy, which reloads it empty.
  late final AppLifecycleListener _lifecycle;

  /// [createRuntime], [drafts], [settings] and [imageIncluded] are for tests;
  /// the page makes its own, and takes the last from the build
  /// ([vmImageIncluded]).
  TkinterScreenController({
    required super.viewModel,
    required super.contextAccessor,
    VmRuntime Function()? createRuntime,
    CodeDraftStore? drafts,
    EditorSettings? settings,
    bool imageIncluded = vmImageIncluded,
  }) : _drafts = drafts ?? GetIt.I<CodeDraftStore>() {
    final draft = _drafts.pageCodeFor(viewModel.draftPage);
    if (draft != null) viewModel.machine.code.text = draft;
    viewModel.machine.code.addListener(_keepDraft);
    _lifecycle = AppLifecycleListener(onHide: () => unawaited(_drafts.flush()));
    machine = VmSessionController(
      viewModel: viewModel.machine,
      contextAccessor: contextAccessor,
      createRuntime: createRuntime,
      settings: settings,
      imageIncluded: imageIncluded,
    );
  }

  /// Runs what is in the editor, and writes it out at once: a tab discarded
  /// while the program runs reloads with that program in the editor.
  void run() {
    if (_disposed || !viewModel.machine.canRun) return;
    unawaited(_drafts.flush());
    machine.run();
  }

  /// The sample is not a draft, so going back to it forgets the one there was.
  void _keepDraft() {
    final code = viewModel.machine.code.text;
    if (code == TkinterScreenViewModelBase.sample) {
      _drafts.forgetPage(viewModel.draftPage);
    } else {
      _drafts.keepPage(viewModel.draftPage, code);
    }
  }

  /// Back to the subject picker, which is the app's home.
  Future<void> goHome() async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([const SubjectsRoute()]);
  }

  /// The catalog this page belongs to.
  Future<void> goToCatalog() async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([
      const SubjectsRoute(),
      CatalogRoute(subjectSlug: subjectSlug(viewModel.subject)),
    ]);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    viewModel.machine.code.removeListener(_keepDraft);
    // Whatever was typed since the last pause, before the editor goes.
    unawaited(_drafts.flush());
    _lifecycle.dispose();
    machine.dispose();
    super.dispose();
  }

}
