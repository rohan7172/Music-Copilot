import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api_service.dart';
import 'launcher.dart';
import 'launcher_stub.dart' if (dart.library.io) 'launcher_io.dart' as platform;

enum BackendStatus {
  /// Not started by the app: web, mobile, a remote API_BASE_URL, or a
  /// test. Requests just go to [ApiService.baseUrl].
  notManaged,

  /// Looking for a backend that's already running.
  checking,

  /// Creating the venv or installing packages (first run only).
  settingUp,

  /// The server is up and loading the model.
  starting,

  ready,
  failed,
}

/// The desktop app's own backend: started with the app (unless one is
/// already running, e.g. from ./dev.sh), stopped with it.
class LocalBackend extends ChangeNotifier {
  LocalBackend({String? baseUrl}) : baseUrl = baseUrl ?? ApiService().baseUrl;

  /// The one the app uses.
  static final instance = LocalBackend();

  final String baseUrl;

  BackendStatus status = BackendStatus.notManaged;

  /// What it's doing right now, in a few words, or why it failed.
  String? detail;

  /// True when an already-running backend was found, so this app didn't
  /// start it and won't stop it.
  bool adopted = false;

  /// The last lines it printed, for the error screen.
  final List<String> log = [];

  RunningBackend? _process;
  Completer<void> _ready = Completer<void>();
  bool _stopping = false;

  bool get isManaged => status != BackendStatus.notManaged;

  bool get isBusy =>
      status == BackendStatus.checking ||
      status == BackendStatus.settingUp ||
      status == BackendStatus.starting;

  /// Whether this platform starts its own backend, and the API is local.
  bool get canManage {
    if (!platform.canLaunchBackend) return false;
    final host = Uri.tryParse(baseUrl)?.host;
    return host == '127.0.0.1' || host == 'localhost';
  }

  int get _port => Uri.parse(baseUrl).port;

  /// Starts the backend if this platform runs its own and none is up.
  /// Safe to call again, e.g. to retry after a failure.
  Future<void> start() async {
    if (!canManage || isBusy || status == BackendStatus.ready) return;
    if (_ready.isCompleted) _ready = Completer<void>();
    log.clear();
    adopted = false;
    _set(BackendStatus.checking, 'looking for the analyzer');

    if (await _healthy()) {
      adopted = true;
      _set(BackendStatus.ready, 'already running');
      return;
    }

    final RunningBackend process;
    try {
      _set(BackendStatus.starting, 'starting the analyzer');
      process = await platform.launchBackend(port: _port, onLine: _onLine);
    } on BackendLaunchError catch (e) {
      _set(BackendStatus.failed, e.message);
      return;
    } catch (e) {
      _set(BackendStatus.failed, 'Couldn’t start the backend: $e');
      return;
    }
    _process = process;
    var exited = false;
    unawaited(
      process.exitCode.then((code) {
        exited = true;
        if (identical(_process, process)) _process = null;
        if (_stopping) return;
        final last = log.where((l) => l.trim().isNotEmpty).lastOrNull;
        _set(
          BackendStatus.failed,
          'The backend stopped (exit code $code)'
          '${last == null ? '' : ': $last'}',
        );
      }),
    );

    // First runs install TensorFlow and friends, which can take minutes.
    final deadline = DateTime.now().add(const Duration(minutes: 20));
    while (!exited && DateTime.now().isBefore(deadline)) {
      if (await _healthy()) {
        _set(BackendStatus.ready, 'running');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (!exited) {
      await process.stop();
      _set(BackendStatus.failed, 'The backend took too long to start.');
    }
  }

  /// Waits for a backend this app is starting. Returns at once when the
  /// app doesn't manage one, or when starting it failed.
  Future<void> untilReady() async {
    if (!isBusy) return;
    await _ready.future;
  }

  /// Stops the backend if this app started it.
  Future<void> stop() async {
    final process = _process;
    if (process == null) return;
    _stopping = true;
    _process = null;
    await process.stop();
    _stopping = false;
  }

  /// Tries again after a failure.
  Future<void> restart() async {
    await stop();
    status = BackendStatus.failed;
    await start();
  }

  void _onLine(String line) {
    log.add(line);
    if (log.length > 60) log.removeAt(0);
    debugPrint('[backend] $line');
    const prefix = 'serve: ';
    if (!line.startsWith(prefix)) return;
    final message = line.substring(prefix.length);
    if (message.startsWith('creating') || message.startsWith('installing')) {
      _set(BackendStatus.settingUp, message.split(' (').first);
    } else if (message.startsWith('starting')) {
      _set(BackendStatus.starting, 'loading the model');
    }
  }

  Future<bool> _healthy() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 1));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void _set(BackendStatus next, String? message) {
    status = next;
    detail = message;
    if (!isBusy && !_ready.isCompleted) _ready.complete();
    notifyListeners();
  }
}
