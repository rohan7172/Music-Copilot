import 'launcher.dart';

/// Web and other platforms without processes: the backend is started
/// separately (./dev.sh), never by the app.
bool get canLaunchBackend => false;

Future<RunningBackend> launchBackend({
  required int port,
  required void Function(String line) onLine,
}) => throw UnsupportedError('This platform can’t start the backend.');
