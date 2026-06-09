import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path/path.dart' as p;

import '../models/spectrum_settings.dart';
import '../models/supported_extensions.dart';
import 'audio_transport.dart';
import 'soloud_spectrum_provider.dart';

/// Thin SoLoud-backed AudioTransport — no queue management, no skip logic.
class SoLoudTransport implements AudioTransport {
  /// On Android, supply [readAndroidAudioBytes] so shared-storage tracks load
  /// via a MediaStore content URI (scoped storage blocks raw-path access). When
  /// null, or when it returns null, [_openSource] falls back to a direct file
  /// load (desktop, or app-private paths).
  SoLoudTransport({this.readBytes, this.openFd, this.closeFd});

  int _lastValidatedGeneration = 0;
  bool _isValidGeneration(int? gen) => gen == null || gen >= _lastValidatedGeneration;

  Future<void>? _activeLoadCompleterFuture;

  /// Resolves a track path to playable bytes (e.g. via a content:// URI).
  /// Returns null to fall back to a direct file load.
  final Future<Uint8List?> Function(String path)? readBytes;

  /// B-049 spike: resolves a path to a `/proc/self/fd/N` string (content-URI fd)
  /// so `loadFile` reads+decodes it in the compute isolate — no UI-isolate byte
  /// marshal. Returns null to fall back to [readBytes]. [closeFd] releases it.
  final Future<String?> Function(String path)? openFd;
  final Future<void> Function(String fdPath)? closeFd;

  static const Set<String> supportedExtensions =
      SupportedExtensions.supportedExtensions;
  static const Duration _endTolerance = Duration(milliseconds: 120);

    @visibleForTesting
    static bool shouldPreloadPath(String path) =>
      p.extension(path).toLowerCase() != '.opus';

  static Future<bool> probeAvailable() async {
    try {
      final soloud = SoLoud.instance;
      await soloud.init();
      if (soloud.isInitialized) soloud.deinit();
      return true;
    } catch (e) {
      debugPrint('[SoLoudTransport] probe failed: $e');
      return false;
    }
  }

  late final SoLoud _soloud = SoLoud.instance;
  final StreamController<TransportEvent> _eventController =
      StreamController<TransportEvent>.broadcast();
  final StreamController<List<double>> _spectrumController =
      StreamController<List<double>>.broadcast();

  SoundHandle? _currentHandle;
  AudioSource? _currentSource;
  Timer? _positionTimer;
  String? _currentPath;
  String? _endedEmittedForPath;
  bool _suppressEndedEvent = false;
  bool _isPreparing = false;
  Duration _pausedPosition = Duration.zero;

  // B-037: at most one preloaded look-ahead source for a gapless in-memory swap.
  AudioSource? _preloadedSource;
  String? _preloadedPath;

  // B-011: cache session + active flag to skip redundant setActive(true)
  // (Android audio-focus IPC, ~100 ms on emulator) when already active.
  AudioSession? _cachedSession;
  bool _audioSessionActive = false;
  Future<void>? _playerInit;

  SpectrumProvider? _spectrumProvider;
  StreamSubscription<List<double>>? _spectrumSub;
  StreamSubscription<StreamSoundEvent>? _soundEventsSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  SpectrumSettings _settings = const SpectrumSettings();
  bool _captureEnabled = true;

  @override
  Stream<TransportEvent> get eventStream => _eventController.stream;

  @override
  Stream<List<double>> get spectrumStream => _spectrumController.stream;

  @override
  Future<Duration> get position async {
    final handle = _currentHandle;
    if (handle == null) return Duration.zero;
    try {
      return _soloud.getPosition(handle);
    } catch (e) {
      return Duration.zero;
    }
  }

  @override
  Future<Duration> get duration async {
    final source = _currentSource;
    if (source == null) return Duration.zero;
    try {
      return _soloud.getLength(source);
    } catch (e) {
      return Duration.zero;
    }
  }

  @override
  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _cachedSession = session;

    // Invalidate the active flag on focus loss so the next play() re-requests
    // focus; PlaybackController owns resume-on-gain.
    _interruptionSub = session.interruptionEventStream.listen((event) {
      if (!event.begin) return;
      switch (event.type) {
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          _audioSessionActive = false;
        case AudioInterruptionType.duck:
          break;
      }
    });
  }

  Future<void> _ensurePlayerReady() async {
    if (_soloud.isInitialized) {
      _ensureSpectrumProvider();
      return;
    }
    final inFlight = _playerInit;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final init = _initPlayer();
    _playerInit = init;
    try {
      await init;
    } finally {
      if (identical(_playerInit, init)) _playerInit = null;
    }
  }

  Future<void> _initPlayer() async {
    await _soloud.init();
    _soloud.setVisualizationEnabled(true);
    _soloud.setFftSmoothing(_settings.decaySpeed.value.clamp(0.0, 1.0));
    _ensureSpectrumProvider();
    if (_captureEnabled) await _startSpectrum();
  }

  void _ensureSpectrumProvider() {
    _spectrumProvider ??= SoLoudSpectrumProvider(
      soloud: _soloud,
      handleProvider: () async => _currentHandle,
      initialSettings: _settings,
    );
    _spectrumSub ??= _spectrumProvider!.spectrumStream.listen(
      _spectrumController.add,
    );
  }

  void _startPositionTimer() {
    _positionTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _checkTrackEnded(),
    );
  }

  @override
  void updateSpectrumSettings(SpectrumSettings settings) {
    _settings = settings;
    _spectrumProvider?.updateSettings(settings);
    if (_soloud.isInitialized) {
      _soloud.setFftSmoothing(settings.decaySpeed.value.clamp(0.0, 1.0));
    }
  }

  @override
  void setCaptureEnabled(bool enabled) {
    _captureEnabled = enabled;
    enabled ? _startSpectrum() : _stopSpectrum();
  }

  @override
  void suspendTimers() {
    _positionTimer?.cancel();
    _positionTimer = null;
    // Release the audio session to free the AudioMix wake lock.
    _setSessionActive(false);
  }

  @override
  void resumeTimers() {
    if (_positionTimer != null || _currentHandle == null) return;
    _startPositionTimer();
    // Re-activate the audio session for playback readiness.
    _setSessionActive(true);
  }

  void _setSessionActive(bool active) {
    AudioSession.instance.then((s) {
      s.setActive(active);
      _audioSessionActive = active;
    });
  }

  Future<void> _setSessionActiveAwaited(bool active) async {
    final session = _cachedSession ?? await AudioSession.instance;
    _cachedSession ??= session;
    await session.setActive(active);
    _audioSessionActive = active;
  }

  Future<void> _startSpectrum() async {
    if (!_captureEnabled) return;
    await _spectrumProvider?.start();
  }

  Future<void> _stopSpectrum() async => _spectrumProvider?.stop();

  @override
  Future<void> dispose() async {
    _positionTimer?.cancel();
    await _stopSpectrum();
    await _spectrumSub?.cancel();
    await _soundEventsSub?.cancel();
    await _interruptionSub?.cancel();
    await _safeStop(_currentHandle);
    await _safeDispose(_currentSource);
    await _disposePreloaded();
    if (_soloud.isInitialized) {
      _soloud.deinit();
    }
    await _eventController.close();
    await _spectrumController.close();
  }

  /// Cleanup-only stop; swallows/logs errors and never throws.
  Future<void> _safeStop(SoundHandle? handle) async {
    if (handle == null || !_soloud.isInitialized) return;
    try {
      await _soloud.stop(handle);
    } catch (e) {
      debugPrint('Error stopping handle: $e');
    }
  }

  /// Cleanup-only dispose; swallows/logs errors and never throws.
  Future<void> _safeDispose(AudioSource? source, {String label = 'source'}) async {
    if (source == null || !_soloud.isInitialized) return;
    try {
      await _soloud.disposeSource(source);
    } catch (e) {
      debugPrint('Error disposing $label: $e');
    }
  }

  void _checkTrackEnded() {
    if (_isPreparing) return;
    final handle = _currentHandle;
    final source = _currentSource;
    if (handle == null || source == null) return;
    try {
      final position = _soloud.getPosition(handle);
      final duration = _soloud.getLength(source);
      final isPaused = _soloud.getPause(handle);

      _eventController.add(TransportPositionEvent(position: position));

      if (duration > Duration.zero) {
        final endThreshold =
            duration > _endTolerance ? duration - _endTolerance : duration;
        if (position >= endThreshold) {
          _emitEndedIfNeeded(); // Emit even if SoLoud auto-paused at the end.
        } else if (!isPaused) {
          _endedEmittedForPath = null; // Cleared once playback progresses.
        }
      }
    } catch (e) {
      // Handle may have been disposed.
    }
  }

  void _attachSoundEvents(AudioSource source) {
    _soundEventsSub?.cancel();
    _soundEventsSub = source.soundEvents.listen((event) {
      if (_suppressEndedEvent) return;
      if (event.sound != _currentSource) return;
      final handle = _currentHandle;
      if (handle == null || event.handle.id != handle.id) return;
      if (event.event == SoundEventType.handleIsNoMoreValid) {
        _emitEndedIfNeeded();
      }
    });
  }

  void _emitEndedIfNeeded() {
    if (_suppressEndedEvent) return;
    final path = _currentPath;
    if (path == null || _endedEmittedForPath == path) return;
    _endedEmittedForPath = path;
    _eventController.add(TransportEndedEvent(path: path));
  }

  @override
  Future<void> cancelGeneration(int generation) async {
    if (generation > _lastValidatedGeneration) {
      _lastValidatedGeneration = generation;
    }
  }

  @override
  Future<void> setPlaybackTarget(String path, {String? title, String? artist, int? generation}) async {
    if (!_isValidGeneration(generation)) return;
    await _ensurePlayerReady();
    if (!_isValidGeneration(generation)) return;

    while (_activeLoadCompleterFuture != null) {
      await _activeLoadCompleterFuture;
      if (!_isValidGeneration(generation)) return;
    }

    final completer = Completer<void>();
    _activeLoadCompleterFuture = completer.future;

    AudioSource? newSource;
    try {
      if (_preloadedSource != null && _preloadedPath == path) {
        newSource = _preloadedSource;
        _preloadedSource = null;
        _preloadedPath = null;
      } else {
        newSource = await _openSource(path);
      }

      if (!_isValidGeneration(generation)) {
        await _safeDispose(newSource);
        return;
      }

      _suppressEndedEvent = true;
      _endedEmittedForPath = null;
      _pausedPosition = Duration.zero;
      
      await _safeStop(_currentHandle);
      _currentHandle = null;
      await _safeDispose(_currentSource);
      
      _currentSource = newSource;
      _currentPath = path;

      if (_currentSource != null) _attachSoundEvents(_currentSource!);
      _suppressEndedEvent = false;
      _eventController.add(TransportLoadedEvent(path: path));
    } catch (e) {
      debugPrint('[SoLoudTransport] Error loading target $path: $e');
      _eventController.add(TransportErrorEvent(path: path, error: e));
      rethrow;
    } finally {
      completer.complete();
      if (_activeLoadCompleterFuture == completer.future) {
        _activeLoadCompleterFuture = null;
      }
    }
  }

  @override
  Future<void> setAudibleState(bool audible, {int? generation}) async {
    if (!_isValidGeneration(generation)) return;
    
    if (audible) {
      await _ensurePlayerReady();
      if (!_isValidGeneration(generation)) return;
      await _reloadCurrentSourceIfNeeded();
      if (!_isValidGeneration(generation)) return;
      
      final source = _currentSource!;
      if (!_audioSessionActive) {
        final session = _cachedSession ?? await AudioSession.instance;
        _cachedSession ??= session;
        await session.setActive(true);
        _audioSessionActive = true;
      }

      if (_currentHandle == null) {
        _currentHandle = _soloud.play(source, paused: false);
        if (_pausedPosition > Duration.zero) {
          _soloud.seek(_currentHandle!, _pausedPosition);
        }
      } else {
        _soloud.setPause(_currentHandle!, false);
      }
      _endedEmittedForPath = null;
    } else {
      final handle = _currentHandle;
      if (handle == null) return;
      try {
        _pausedPosition = _soloud.getPosition(handle);
      } catch (_) {
        _pausedPosition = Duration.zero;
      }
      _suppressEndedEvent = true;
      try {
        _soloud.setPause(handle, true);
        // We keep the handle alive instead of stopping it so play() later is resumed
        // Wait, handle hibernation? If we don't hibernate, we stay hot.
      } finally {
        _suppressEndedEvent = false;
      }
    }
  }

  @override
  Future<void> seekWithinCurrentTrack(Duration position, {int? generation}) async {
    if (!_isValidGeneration(generation)) return;
    final handle = _currentHandle;
    if (handle == null) {
      _pausedPosition = position;
      return;
    }
    _soloud.seek(handle, position);
    _pausedPosition = position;
  }

  @override
  @Deprecated('Use setPlaybackTarget and setAudibleState(true)')
  Future<void> load(String path, {String? title, String? artist}) async {
    await setPlaybackTarget(path, title: title, artist: artist);
  }

  @override
  Future<void> preload(String path) async {
    await _ensurePlayerReady();
    if (!shouldPreloadPath(path)) {
      await _disposePreloaded();
      debugPrint('[SoLoudTransport] skip preload for $path');
      return;
    }
    if (path == _currentPath) return;
    if (path == _preloadedPath && _preloadedSource != null) return;

    // Dispose any stale cache before decoding the new look-ahead target.
    await _disposePreloaded();

    try {
      final source = await _openSource(path);
      // A concurrent load()/preload() may have moved on while decoding; keep
      // the cache only if it's still wanted and nothing else claimed it.
      if (path == _currentPath || _preloadedSource != null) {
        await _soloud.disposeSource(source);
        return;
      }
      _preloadedSource = source;
      _preloadedPath = path;
    } catch (e) {
      // Best-effort: a failed preload is silent; the real load() surfaces it.
      debugPrint('[SoLoudTransport] preload failed for $path: $e');
      _preloadedSource = null;
      _preloadedPath = null;
    }
  }

  /// Decode [path] into a SoLoud [AudioSource] without playing it.
  ///
  /// When a [readBytes] resolver is supplied (Android) and yields bytes, the
  /// source is decoded from memory (off the UI isolate via SoLoud's `compute`)
  /// — this is how scoped-storage tracks reach the decoder, since their raw
  /// path isn't openable. Otherwise it loads directly from the filesystem.
  Future<AudioSource> _openSource(String path) async {
    // Opus now decodes natively inside loadFile/loadMem (forked flutter_soloud,
    // on the compute isolate) exactly like mp3 — no more UI-isolate buffer-stream
    // feed. So every format takes the same path here.
    final isOpus = p.extension(path).toLowerCase() == '.opus';
    final sw = isOpus ? (Stopwatch()..start()) : null;
    void perf(String mode) {
      if (sw != null) {
        debugPrint('[OPUS-PERF] mode=$mode total_ms=${sw.elapsedMilliseconds} '
            'file=${p.basename(path)}');
      }
    }

    _isPreparing = true;
    try {
      // Fast path first: load straight from the filesystem — no whole-file read or
      // platform-channel marshal. Works wherever the raw path is openable (desktop
      // and most Android devices), which is the common case.
      try {
        final source = await _soloud.loadFile(path);
        perf('loadFile');
        return source;
      } catch (e) {
        // Raw-path access is blocked on Android scoped storage (API 30+).
        // B-049: prefer the fd path (no UI-isolate byte marshal) — loadFile
        // reads+decodes /proc/self/fd/N in the compute isolate.
        if (openFd != null) {
          final fdPath = await openFd!(path);
          if (fdPath != null) {
            try {
              final source = await _soloud.loadFile(fdPath);
              perf('fd');
              return source;
            } finally {
              if (closeFd != null) unawaited(closeFd!(fdPath));
            }
          }
        }
        // Fall back to a MediaStore content-URI byte read when wired; else surface.
        if (readBytes == null) rethrow;
        final bytes = await readBytes!(path);
        if (bytes == null) rethrow;
        final source = await _soloud.loadMem(path, bytes);
        perf('loadMem');
        return source;
      }
    } finally {
      _isPreparing = false;
    }
  }

  Future<void> _disposePreloaded() async {
    final source = _preloadedSource;
    _preloadedSource = null;
    _preloadedPath = null;
    await _safeDispose(source, label: 'preloaded source');
  }

  Future<void> _reloadCurrentSourceIfNeeded() async {
    if (_currentSource != null) return;
    final path = _currentPath;
    if (path == null) {
      throw StateError('No source loaded. Call load() first.');
    }
    final source = await _openSource(path);
    _currentSource = source;
    _attachSoundEvents(source);
  }

  Future<void> _hibernatePausedPlayback() async {
    _currentHandle = null;
    await _safeDispose(_currentSource);
    _currentSource = null;
    await _disposePreloaded();
    await _stopSpectrum();
    await _soundEventsSub?.cancel();
    _soundEventsSub = null;
    if (_soloud.isInitialized) {
      _soloud.deinit();
    }
    await _setSessionActiveAwaited(false);
  }

  @override
  @Deprecated('Use setAudibleState(true) instead')
  Future<void> play() async {
    return setAudibleState(true);
  }

  @override
  @Deprecated('Use setAudibleState(false) instead')
  Future<void> pause() async {
    final handle = _currentHandle;
    if (handle == null) return;
    try {
      _pausedPosition = _soloud.getPosition(handle);
    } catch (_) {
      _pausedPosition = Duration.zero;
    }

    _suppressEndedEvent = true;
    try {
      await _soloud.stop(handle);
      _currentHandle = null;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _hibernatePausedPlayback();
      }
    } finally {
      _suppressEndedEvent = false;
    }
  }

  @override
  @Deprecated('Use seekWithinCurrentTrack instead')
  Future<void> seek(Duration position) async {
    return seekWithinCurrentTrack(position);
  }
}
