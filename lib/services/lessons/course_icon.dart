/// A picture from the app's own set: what a lesson names with `icon` in its
/// document-level `metadata`, and what stands for a subject on the home screen.
///
/// Each case is one file under `assets/icons/`, named by [key]. The set belongs
/// to the app rather than to a course, so a course can only pick from it; see
/// `docs/lesson-format.md`. Plain Dart, because the lesson parser runs on the
/// Dart VM as well.
enum CourseIcon {

  barChart('bar-chart'),
  branch('branch'),
  click('click'),
  cube('cube'),
  dice('dice'),
  form('form'),
  format('format'),
  function('function'),
  gear('gear'),
  hierarchy('hierarchy'),
  hourglass('hourglass'),
  // `index` is taken by Enum.
  indexing('index'),
  keyboard('keyboard'),
  kiosk('kiosk'),
  label('label'),
  ledScanner('led-scanner'),
  lifebuoy('lifebuoy'),
  lightbulb('lightbulb'),
  list('list'),
  lock('lock'),
  loop('loop'),
  magnifier('magnifier'),
  microbit('microbit'),
  mirror('mirror'),
  operators('operators'),
  output('output'),
  package('package'),
  scale('scale'),
  snake('snake'),
  sparkles('sparkles'),
  table('table'),
  tabs('tabs'),
  text('text'),
  trueFalse('true-false'),
  window('window');

  /// The name a lesson file uses, which is also the asset's file name.
  final String key;

  const CourseIcon(this.key);

  static CourseIcon parse(String value) {
    for (final icon in values) {
      if (icon.key == value) return icon;
    }

    throw FormatException('Unknown icon "$value". docs/lesson-format.md lists the ones there are.');
  }

}
