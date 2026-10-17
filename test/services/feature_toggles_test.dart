import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/feature_toggles.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  test('starts with every toggle off', () {
    final toggles = FeatureToggles();

    expect(toggles.isOn('files'), isFalse);
    expect(toggles.anyOn, isFalse);
  });

  test('remembers what was turned on, across a reload', () async {
    await FeatureToggles().set('files', on: true);

    final reloaded = FeatureToggles();
    expect(reloaded.isOn('files'), isFalse, reason: 'nothing is read before load');

    await reloaded.load();
    expect(reloaded.isOn('files'), isTrue);
    expect(reloaded.isOn('csv'), isFalse);
  });

  test('turning one off leaves the others on', () async {
    final toggles = FeatureToggles();
    await toggles.set('files', on: true);
    await toggles.set('csv', on: true);
    await toggles.set('files', on: false);

    final reloaded = FeatureToggles();
    await reloaded.load();
    expect(reloaded.isOn('files'), isFalse);
    expect(reloaded.isOn('csv'), isTrue);
  });

  test('all off is all off, in storage too', () async {
    final toggles = FeatureToggles();
    await toggles.set('files', on: true);
    await toggles.clear();

    expect(toggles.anyOn, isFalse);

    final reloaded = FeatureToggles();
    await reloaded.load();
    expect(reloaded.anyOn, isFalse);
  });

  group('static toggles', () {
    test('are spelled like a group id, and declared once each', () {
      final names = kStaticFeatureToggles.map((toggle) => toggle.name).toList();

      for (final name in names) {
        expect(name, matches(RegExp(r'^[a-z0-9-]+$')));
      }
      expect(names.toSet(), hasLength(names.length));
    });

    test('share their names with the course\'s, so one switch covers both', () {
      const statics = [
        StaticFeatureToggle('tkinter', description: 'The Tkinter environment'),
        StaticFeatureToggle('beta', description: 'Something new'),
      ];
      const course = Course(
        lessons: [
          CourseLesson(
            entry: LessonEntry(subject: 'python', order: 1, paths: {'nl': 'x'}),
            translations: {'nl': Lesson(id: 'window', title: 'Window', feature: 'tkinter', sections: [])},
          ),
          CourseLesson(
            entry: LessonEntry(subject: 'python', order: 2, paths: {'nl': 'x'}),
            translations: {'nl': Lesson(id: 'files', title: 'Files', feature: 'files', sections: [])},
          ),
        ],
      );

      expect(featureToggleNames(course: course, statics: statics), ['beta', 'files', 'tkinter']);
      expect(featureToggleNames(statics: statics), ['beta', 'tkinter'], reason: 'before the course is read');
    });
  });
}
