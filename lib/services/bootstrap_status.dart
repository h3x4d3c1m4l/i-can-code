/// Whether the app has finished its one-time startup work. Every screen past
/// [InitializationScreen] assumes the course is loaded, so the router gates on
/// this.
///
/// A flag rather than a probe like `GetIt.isRegistered<Course>()`, which would
/// let routes through half way through the bootstrap.
class BootstrapStatus {

  bool _completed = false;

  bool get completed => _completed;

  void markCompleted() => _completed = true;

}
