import 'dart:async';
import 'dart:io';

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
  static const Set<String> supportedExtensions =
      SupportedExtensions.supportedExtensions;
  static const Duration _endTolerance = Duration(milliseconds: 120);

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

  // B-037: at most one preloaded look-ahead source for a gapless in-memory swap.
  AudioSource? _preloadedSource;
  String? _preloadedPath;

  // B-011: cache session + active flag to skip redundant setActive(true)
  // (Android audio-focus IPC, ~100 ms on emulator) when already active.
  AudioSession? _cachedSession;
  bool _audioSessionActive = false;

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
    await session.setActive(true);
    _cachedSession = session;
    _audioSessionActive = true;

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

    await _soloud.init();
    _soloud.setVisualizationEnabled(true);

    _spectrumProvider = SoLoudSpectrumProvider(
      soloud: _soloud,
      handleProvider: () async => _currentHandle,
      initialSettings: _settings,
    );
    _spectrumSub = _spectrumProvider!.spectrumStream.listen(
      _spectrumController.add,
    );

    _startPositionTimer();
    if (_captureEnabled) _startSpectrum();
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
    _soloud.setFftSmoothing(settings.decaySpeed.value.clamp(0.0, 1.0));
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
    if (_positionTimer != null) return;
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
    await _eventController.close();
    await _spectrumController.close();
  }

  /// Cleanup-only stop; swallows/logs errors and never throws.
  Future<void> _safeStop(SoundHandle? handle) async {
    if (handle == null) return;
    try {
      await _soloud.stop(handle);
    } catch (e) {
      debugPrint('Error stopping handle: $e');
    }
  }

  /// Cleanup-only dispose; swallows/logs errors and never throws.
  Future<void> _safeDispose(AudioSource? source, {String label = 'source'}) async {
    if (source == null) return;
    try {
      await _soloud.disposeSource(source);
    } catch (e) {
      debugPrint('Error disposing $label: $e');
    }
  }

  void _checkTrackEnded() {
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
  Future<void> load(String path, {String? title, String? artist}) async {
    _suppressEndedEvent = true;
    _endedEmittedForPath = null;
    await _safeStop(_currentHandle);
    _currentHandle = null;
    await _safeDispose(_currentSource);
    _currentSource = null;
    _currentPath = path;

    try {
      if (_preloadedSource != null && _preloadedPath == path) {
        // B-037 gapless promotion: adopt the already-decoded preload directly.
        _currentSource = _preloadedSource;
        _preloadedSource = null;
        _preloadedPath = null;
      } else {
        // Path differs from the preload; drop the stale cache so it can't leak.
        await _disposePreloaded();
        _currentSource = await _openSource(path);
      }

      if (_currentSource != null) _attachSoundEvents(_currentSource!);
      _suppressEndedEvent = false;
      _eventController.add(TransportLoadedEvent(path: path));
    } catch (e) {
      debugPrint('[SoLoudTransport] Error loading $path: $e');
      _eventController.add(TransportErrorEvent(path: path, error: e));
      _suppressEndedEvent = false;
      rethrow;
    }
  }

  @override
  Future<void> preload(String path) async {
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
  Future<AudioSource> _openSource(String path) async {
    if (p.extension(path).toLowerCase() == '.opus') {
      final bytes = await File(path).readAsBytes();
      final source = _soloud.setBufferStream(
        bufferingType: BufferingType.preserved,
        format: BufferType.auto,
        channels: Channels.stereo,
        sampleRate: 44100,
      );
      _soloud.addAudioDataStream(source, bytes);
      _soloud.setDataIsEnded(source);
      return source;
    }
    return _soloud.loadFile(path);
  }

  Future<void> _disposePreloaded() async {
    final source = _preloadedSource;
    _preloadedSource = null;
    _preloadedPath = null;
    await _safeDispose(source, label: 'preloaded source');
  }

  @override
  Future<void> play() async {
    final source = _currentSource;
    if (source == null) {
      throw StateError('No source loaded. Call load() first.');
    }

    // B-011: skip the redundant audio-focus IPC when already active.
    if (!_audioSessionActive) {
      final session = _cachedSession ?? await AudioSession.instance;
      _cachedSession ??= session;
      await session.setActive(true);
      _audioSessionActive = true;
    }

    if (_currentHandle == null) {
      _currentHandle = _soloud.play(source, paused: false);
    } else {
      _soloud.setPause(_currentHandle!, false);
    }
    _endedEmittedForPath = null;
  }

  @override
  Future<void> pause() async {
    final handle = _currentHandle;
    if (handle == null) return;
    _soloud.setPause(handle, true);
  }

  @override
  Future<void> seek(Duration position) async {
    final handle = _currentHandle;
    if (handle == null) return;
    _soloud.seek(handle, position);
  }
}
