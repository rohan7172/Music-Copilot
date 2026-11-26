import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'launcher.dart';

/// Only the desktop builds start the backend themselves; on a phone it
/// runs on another machine.
bool get canLaunchBackend =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// Where Homebrew and friends put python3.11 and ffmpeg. A macOS app opened
/// from Finder or the Dock gets a bare PATH without them, so they're added
/// to the backend's PATH and searched for Python.
const _extraUnixPaths = ['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin'];

/// Starts `backend/serve.py`, which sets up the backend's venv if needed
/// and runs the server on [port]. Every line it prints goes to [onLine].
Future<RunningBackend> launchBackend({
  required int port,
  required void Function(String line) onLine,
}) async {
  final backend = findBackendDir();
  if (backend == null) {
    throw BackendLaunchError(
      'Couldn’t find the backend folder. Run the app from inside the '
      'Music Copilot repository, or set MUSIC_COPILOT_BACKEND to the path '
      'of its backend folder.',
    );
  }
  final python = _findPython(backend);
  if (python == null) {
    throw BackendLaunchError(
      'Python 3.11 isn’t installed, and the backend needs it the first '
      'time it sets itself up. On a Mac: brew install python@3.11',
    );
  }

  final environment = Map<String, String>.of(Platform.environment);
  if (!Platform.isWindows) {
    final path = environment['PATH'] ?? '';
    final parts = path.split(':').where((p) => p.isNotEmpty).toList();
    for (final extra in _extraUnixPaths) {
      if (!parts.contains(extra)) parts.add(extra);
    }
    environment['PATH'] = parts.join(':');
  }
  environment['PYTHONUNBUFFERED'] = '1';

  onLine('serve: using ${backend.path}');
  final process = await Process.start(
    python.executable,
    [...python.arguments, 'serve.py', '--port', '$port', '--exit-with-stdin'],
    workingDirectory: backend.path,
    environment: environment,
    includeParentEnvironment: false,
  );
  for (final stream in [process.stdout, process.stderr]) {
    stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine, onError: (_) {});
  }
  return _ProcessBackend(process);
}

/// The repository's `backend` folder: from MUSIC_COPILOT_BACKEND (an
/// environment variable or a --dart-define), else the first ancestor of
/// the working directory or of the app's executable that holds one. A
/// `flutter run -d macos` build lives under app/build/, inside the repo.
Directory? findBackendDir() {
  const defined = String.fromEnvironment('MUSIC_COPILOT_BACKEND');
  final configured = Platform.environment['MUSIC_COPILOT_BACKEND'] ?? defined;
  if (configured.isNotEmpty) {
    final dir = Directory(configured);
    return _isBackend(dir) ? dir : null;
  }
  final starts = [Directory.current, File(Platform.resolvedExecutable).parent];
  for (final start in starts) {
    Directory? dir = start.absolute;
    while (dir != null) {
      final candidate = Directory(
        '${dir.path}${Platform.pathSeparator}backend',
      );
      if (_isBackend(candidate)) return candidate;
      if (_isBackend(dir)) return dir;
      final parent = dir.parent;
      dir = parent.path == dir.path ? null : parent;
    }
  }
  return null;
}

bool _isBackend(Directory dir) {
  final sep = Platform.pathSeparator;
  return File('${dir.path}${sep}serve.py').existsSync() &&
      File('${dir.path}${sep}app${sep}main.py').existsSync();
}

class _Python {
  const _Python(this.executable, [this.arguments = const []]);

  final String executable;
  final List<String> arguments;
}

/// The backend's own venv Python once it exists; before that, a Python
/// 3.11 to create the venv with.
_Python? _findPython(Directory backend) {
  final sep = Platform.pathSeparator;
  final venv = Platform.isWindows
      ? '${backend.path}${sep}venv${sep}Scripts${sep}python.exe'
      : '${backend.path}${sep}venv${sep}bin${sep}python';
  if (File(venv).existsSync()) return _Python(venv);

  final override = Platform.environment['MUSIC_COPILOT_PYTHON'];
  if (override != null && override.isNotEmpty) return _Python(override);

  if (Platform.isWindows) {
    // The Python launcher picks an installed 3.11 by version.
    if (_runs('py', ['-3.11', '--version'])) {
      return const _Python('py', ['-3.11']);
    }
    if (_runs('python', ['--version'])) return const _Python('python');
    return null;
  }
  final path = (Platform.environment['PATH'] ?? '').split(':');
  for (final dir in [...path, ..._extraUnixPaths]) {
    if (dir.isEmpty) continue;
    final candidate = '$dir/python3.11';
    if (File(candidate).existsSync()) return _Python(candidate);
  }
  return null;
}

bool _runs(String executable, List<String> arguments) {
  try {
    return Process.runSync(executable, arguments).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

class _ProcessBackend implements RunningBackend {
  _ProcessBackend(this._process);

  final Process _process;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<void> stop() async {
    // serve.py stops the server when its stdin closes; that also covers
    // the app being force-quit, when this never runs.
    try {
      await _process.stdin.close();
    } catch (_) {}
    final exited = await _process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
    if (exited == -1) _process.kill(ProcessSignal.sigkill);
  }
}
