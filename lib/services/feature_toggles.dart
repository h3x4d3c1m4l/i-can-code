import 'package:get_it/get_it.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'feature_toggles.g.dart';

class FeatureToggles = FeatureTogglesBase with _$FeatureToggles;

/// A feature toggle declared in code: a **static** one, for a part of the app
/// that is not ready to be shown, such as a new runtime. Its counterpart is the
/// **dynamic** toggle a lesson or a group names in the course.
///
/// Both kinds share one set of names, so a lesson that says `feature: <name>`
/// is hidden by the same switch as the part of the app it is about.
class StaticFeatureToggle {

  /// MUST be spelled like a group id: lower case, digits and dashes.
  final String name;

  /// What it hides, in a few words, for the debug menu.
  final String description;

  const StaticFeatureToggle(this.name, {required this.description});

}

/// Every static toggle the app declares, which the debug menu offers whether or
/// not the course names it too. Empty until a feature needs one.
const List<StaticFeatureToggle> kStaticFeatureToggles = [];

/// Every toggle the debug menu offers: [statics] and the names [course] uses,
/// once each and sorted. [course] is null before the course is read.
List<String> featureToggleNames({Course? course, List<StaticFeatureToggle> statics = kStaticFeatureToggles}) =>
    {...statics.map((toggle) => toggle.name), ...?course?.features}.toList()..sort();

/// Which feature toggles are on, switched in the debug menu.
///
/// A toggle hides whatever names it until it is turned on: a lesson that says
/// `feature:` in its metadata, a group that says `feature=` in its contents file
/// (both dynamic, see `docs/lesson-format.md`), or a part of the app wrapped in
/// a `FeatureGate` for a [StaticFeatureToggle].
///
/// It hides and keeps nothing secret. A hidden lesson is in the bundle like any
/// other, and its address still opens it.
///
/// Persisted **per browser** like the theme mode, and every read and write
/// swallows its own failure. Clearing progress does not clear it.
abstract class FeatureTogglesBase with Store {

  static const String storageKey = 'features.enabled';

  final SharedPreferencesAsync _preferences;

  final ObservableSet<String> _enabled = ObservableSet<String>();

  FeatureTogglesBase({SharedPreferencesAsync? preferences}) : _preferences = preferences ?? SharedPreferencesAsync();

  /// Whether [feature] is on. Tracked when an observer reads it.
  bool isOn(String feature) => _enabled.contains(feature);

  /// Whether any toggle is on, a name the course no longer uses included.
  bool get anyOn => _enabled.isNotEmpty;

  /// Reads what was saved. Called once, by the initialization screen, so the
  /// first catalog is already the right one.
  Future<void> load() async {
    try {
      final stored = await _preferences.getStringList(storageKey);
      if (stored != null) _replace(stored);
    } on Object {
      // Treated as "everything off".
    }
  }

  /// Turns [feature] on or off, for this session at once and in storage when
  /// the write lands.
  Future<void> set(String feature, {required bool on}) async {
    if (isOn(feature) == on) return;
    _switch(feature, on: on);
    await _save();
  }

  /// Turns every toggle off, in storage as well as in memory.
  Future<void> clear() async {
    _replace(const []);

    try {
      await _preferences.remove(storageKey);
    } on Object {
      // Off for this session either way.
    }
  }

  @action
  void _switch(String feature, {required bool on}) => on ? _enabled.add(feature) : _enabled.remove(feature);

  @action
  void _replace(Iterable<String> features) => _enabled
    ..clear()
    ..addAll(features);

  Future<void> _save() async {
    try {
      await _preferences.setStringList(storageKey, _enabled.toList()..sort());
    } on Object {
      // Stands for this session either way.
    }
  }

}

/// The [Course] in GetIt without what a toggle that is off hides: what the
/// subject picker and the catalog list.
///
/// Read inside an `Observer` it tracks the toggles, so a switch in the debug
/// menu redraws the screen under it.
Course get visibleCourse => GetIt.I<Course>().visibleWith(GetIt.I<FeatureToggles>().isOn);

/// The lesson "Volgende les" opens after [lesson]: the next one in its subject
/// that is not hidden, whether or not [lesson] itself is.
CourseLesson? visibleLessonAfter(CourseLesson lesson) =>
    GetIt.I<Course>().lessonAfter(lesson, isOn: GetIt.I<FeatureToggles>().isOn);
