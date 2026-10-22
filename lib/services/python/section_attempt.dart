import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';

/// How [PythonAttemptRunner] runs a section's code. One place, so the lesson
/// screen, `tool/try_lesson.dart` and the tests run a step the same way.
extension SectionAttempt on LessonSection {

  PythonRunMode get runMode => switch (run) {
    SectionRun.script => PythonRunMode.script,
    SectionRun.pytest => PythonRunMode.pytest,
  };

}
