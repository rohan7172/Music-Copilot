/// What a launched backend process looks like to [LocalBackend], whichever
/// platform started it.
abstract class RunningBackend {
  /// Completes when the process exits, with its exit code.
  Future<int> get exitCode;

  /// Asks the backend to shut down, and kills it if it doesn't.
  Future<void> stop();
}

/// Starting the backend failed before it could run: no backend folder or
/// no suitable Python. [message] is written for the person using the app.
class BackendLaunchError implements Exception {
  BackendLaunchError(this.message);

  final String message;

  @override
  String toString() => message;
}
