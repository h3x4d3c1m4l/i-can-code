import 'package:get_it/get_it.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/views/base/screen_view_model_base.dart';
import 'package:i_can_code/views/components/microbit/microbit_session_view_model.dart';
import 'package:mobx/mobx.dart';

part 'project_screen_view_model.g.dart';

class ProjectScreenViewModel = ProjectScreenViewModelBase with _$ProjectScreenViewModel;

abstract class ProjectScreenViewModelBase extends ScreenViewModelBase with Store {

  /// The project being built, in every locale it has.
  final CourseLesson lesson;

  /// The board, and the one program every task of the project shares.
  late final MicrobitSessionViewModel board;

  /// Sections the student has finished, as indices into the lesson: info they
  /// said they read, and tasks they said work. Seeded from [ProgressStore],
  /// which keys on section ids.
  @readonly
  Set<int> _passed = {};

  /// Optional sections passed over on this visit. Not stored, the way skipping
  /// a "Verdieping" stores nothing anywhere else: on the next visit it is
  /// offered again, unless a later section was finished since.
  @readonly
  Set<int> _skipped = {};

  /// The one section shown open, or null when the student closed it. Only one
  /// at a time, so opening an earlier section to read it again closes the one
  /// being worked on.
  @readonly
  int? _open;

  /// Whether the program was written to the board since the section in front
  /// of the student opened. Until it was, "it works" is a claim about a program
  /// the board has never run.
  @readonly
  bool _flashedHere = false;

  /// How many tasks were finished on this visit. Each one is a small burst,
  /// keyed on this count, so the next one fires again.
  @readonly
  int _passBursts = 0;

  /// This visit is what finished the project. See the lesson screen's field of
  /// the same name.
  @readonly
  bool _earnedCelebration = false;

  @readonly
  int _extraBursts = 0;

  ProjectScreenViewModelBase({
    required super.contextAccessor,
    required String subjectSlug,
    required String lessonId,
  }) : lesson = GetIt.I<Course>().lessons.firstWhere((l) => l.translations.values.first.id == lessonId) {
    board = MicrobitSessionViewModel(
      contextAccessor: contextAccessor,
      subjectSlug: subjectSlug,
      program: GetIt.I<CodeDraftStore>().workFor(lesson) ?? _starterOf(lesson.translations.values.first),
    );

    final finished = GetIt.I<ProgressStore>().finishedIn(lesson);
    _passed = {
      for (final (index, section) in _sections.indexed)
        if (finished.contains(section.id)) index,
    };
    _open = current;
  }

  /// What the editor opens with before the student changes anything: the
  /// first task's assignment block, or nothing.
  static String _starterOf(Lesson lesson) => lesson.sections.map((section) => section.starter).nonNulls.firstOrNull ?? '';

  /// The project's starter in every locale. An editor keeps its text across a
  /// change of language, so a program equal to any of them is untouched.
  Set<String> get starters => {for (final translation in lesson.translations.values) _starterOf(translation)};

  /// Read off any translation: `lesson_test.dart` holds every locale to the
  /// same sections.
  List<LessonSection> get _sections => lesson.translations.values.first.sections;

  /// The section in front of the student, as an index into the lesson. Null
  /// once every section is behind them, finished or skipped.
  ///
  /// The first one after the **last finished** section rather than the first
  /// one not finished: a Verdieping skipped on an earlier visit left no trace,
  /// and asking for it again would put it in front of work already done after
  /// it.
  @computed
  int? get current {
    final lastFinished = _passed.fold(-1, _max);

    for (var index = lastFinished + 1; index < _sections.length; index++) {
      if (!_skipped.contains(index)) return index;
    }
    return null;
  }

  /// Whether this subject has another lesson after this one.
  bool get hasNextLesson => GetIt.I<Course>().lessonAfter(lesson) != null;

  @action
  void noteFlashed() => _flashedHere = true;

  /// Opens [section] and closes whichever was open, or closes [section] when
  /// it was the open one. A section still ahead cannot be opened.
  @action
  void toggle(int section) {
    final reached = current;
    if (reached != null && section > reached) return;

    _open = _open == section ? null : section;
  }

  /// Marks [section] finished and opens the one after it.
  @action
  void finish(int section) {
    _passed = {..._passed, section};
    _flashedHere = false;
    if (_sections[section].kind == SectionKind.task) _passBursts++;
    _open = current;
  }

  @action
  void skip(int section) {
    _skipped = {..._skipped, section};
    _flashedHere = false;
    _open = current;
  }

  @action
  void noteProjectFinished() => _earnedCelebration = true;

  @action
  void addExtraBurst() => _extraBursts++;

  @override
  void dispose() {
    board
      ..code.dispose()
      ..dispose();
    super.dispose();
  }

}

int _max(int a, int b) => a > b ? a : b;
