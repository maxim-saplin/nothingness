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
import 'spectrum_provider.dart';

/// Thin wrapper around SoLoud.
/// Implements AudioTransport interface - no queue management, no skip logic.
class SoLoudTransport implements AudioTransport {
  static const Set<String> supportedExtensions = SupportedExtensions.supportedExtensions;
  static const Duration _endTolerance = Duration(milliseconds: 120);
  static Future<bool> probeAvailable() async {
    try {
      final soloud = SoLoud.instance;
      await soloud.init();
      if (soloud.isInitialized) {
        soloud.deinit();
      }
      return true;
    } catch (e) {
      debugPrint('[SoLoudTransport] probe failed: $e');
      return false;
    }
  }
  late final SoLoud _soloud = SoLoud.instance;
  final StreamController<TransportEvent> _eventController =
      StreamController<TransportEvent>.broadcast();

  SoundHandle? _currentHandle;
  AudioSource? _currentSource;
  Timer? _positionTimer;
  String? _currentPath;
  String? _endedEmittedForPath;
  bool _suppressEndedEvent = false;
  
  SpectrumProvider? _spectrumProvider;
  StreamSubscription<List<double>>? _spectrumSub;
  StreamSubscription<StreamSoundEvent>? _soundEventsSub;
  final StreamController<List<double>> _spectrumController =
      StreamController<List<double>>.broadcast();
  SpectrumSettings _settings = const SpectrumSettings();
  bool _captureEnabled = true;

  @override
  Stream<TransportEvent> get eventStream => _eventController.stream;

  @override
  Future<Duration> get position async {
    if (_currentHandle == null) return Duration.zero;
    try {
      return _soloud.getPosition(_currentHandle!);
    } catch (e) {
      return Duration.zero;
    }
  }

  @override
  Future<Duration> get duration async {
    if (_currentSource == null) return Duration.zero;
    try {
      return _soloud.getLength(_currentSource!);
    } catch (e) {
      return Duration.zero;
    }
  }

  @override
  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await session.setActive(true);

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

    // Check for track ended periodically
    _positionTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _checkTrackEnded(),
    );

    if (_captureEnabled) {
      _startSpectrum();
    }
  }

  @override
  Stream<List<double>> get spectrumStream => _spectrumController.stream;

  @override
  void updateSpectrumSettings(SpectrumSettings settings) {
    _settings = settings;
    _spectrumProvider?.updateSettings(settings);
    _soloud.setFftSmoothing(settings.decaySpeed.value.clamp(0.0, 1.0));
  }

  @override
  void setCaptureEnabled(bool enabled) {
    _captureEnabled = enabled;
    if (enabled) {
      _startSpectrum();
    } else {
      _stopSpectrum();
    }
  }

  Future<void> _startSpectrum() async {
    if (!_captureEnabled) return;
    await _spectrumProvider?.start();
  }

  Future<void> _stopSpectrum() async {
    await _spectrumProvider?.stop();
  }

  @override
  Future<void> dispose() async {
    _positionTimer?.cancel();
    await _stopSpectrum();
    await _spectrumSub?.cancel();
    await _soundEventsSub?.cancel();
    if (_currentHandle != null) {
      try {
        await _soloud.stop(_currentHandle!);
      } catch (e) {
        debugPrint('Error stopping handle: $e');
      }
    }
    if (_currentSource != null) {
      try {
        await _soloud.disposeSource(_currentSource!);
      } catch (e) {
        debugPrint('Error disposing source: $e');
      }
    }
    await _eventController.close();
    await _spectrumController.close();
  }

  void _checkTrackEnded() {
    if (_currentHandle == null || _currentSource == null) return;

    try {
      final position = _soloud.getPosition(_currentHandle!);
      final duration = _soloud.getLength(_currentSource!);
      final isPaused = _soloud.getPause(_currentHandle!);

      // Emit position update
      _eventController.add(TransportPositionEvent(position: position));

      // Check if track ended
      if (duration > Duration.zero) {
        final endThreshold = duration > _endTolerance
            ? duration - _endTolerance
            : duration;
        if (position >= endThreshold) {
          // If SoLoud auto-pauses at the end, still emit ended.
          _emitEndedIfNeeded();
        } else if (!isPaused) {
          // Clear ended marker once playback progresses again.
          _endedEmittedForPath = null;
        }
      }
    } catch (e) {
      // Handle may have been disposed
    }
  }

  void _attachSoundEvents(AudioSource source) {
    _soundEventsSub?.cancel();
    _soundEventsSub = source.soundEvents.listen((event) {
      if (_suppressEndedEvent) return;
      if (event.sound != _currentSource) return;
      if (_currentHandle == null) return;
      if (event.handle.id != _currentHandle!.id) return;
      if (event.event == SoundEventType.handleIsNoMoreValid) {
        _emitEndedIfNeeded();
      }
    });
  }

  void _emitEndedIfNeeded() {
    if (_suppressEndedEvent) return;
    final path = _currentPath;
    if (path == null) return;
    if (_endedEmittedForPath == path) return;
    _endedEmittedForPath = path;
    _eventController.add(TransportEndedEvent(path: path));
  }

  @override
  Future<void> load(String path, {String? title, String? artist}) async {
    _suppressEndedEvent = true;
    _endedEmittedForPath = null;
    // Stop current playback
    if (_currentHandle != null) {
      try {
        await _soloud.stop(_currentHandle!);
      } catch (e) {
        debugPrint('Error stopping handle: $e');
      }
    }
    _currentHandle = null;

    if (_currentSource != null) {
      try {
        await _soloud.disposeSource(_currentSource!);
      } catch (e) {
        debugPrint('Error disposing source: $e');
      }
    }
    _currentSource = null;

    _currentPath = path;

    try {
      if (p.extension(path).toLowerCase() == '.opus') {
        final file = File(path);
        final bytes = await file.readAsBytes();

        _currentSource = _soloud.setBufferStream(
          bufferingType: BufferingType.preserved,
          format: BufferType.auto,
          channels: Channels.stereo,
          sampleRate: 44100,
        );

        _soloud.addAudioDataStream(_currentSource!, bytes);
        _soloud.setDataIsEnded(_currentSource!);
      } else {
        _currentSource = await _soloud.loadFile(path);
      }

      if (_currentSource != null) {
        _attachSoundEvents(_currentSource!);
      }
      _suppressEndedEvent = false;

      _eventController.add(TransportLoadedEvent(path: path));
    } catch (e) {
      debugPrint('[SoLoudTransport] Error loading $path: $e');
      _eventController.add(TransportErrorEvent(
        path: path,
        error: e,
      ));
      _suppressEndedEvent = false;
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    if (_currentSource == null) {
      throw StateError('No source loaded. Call load() first.');
    }

    final session = await AudioSession.instance;
    await session.setActive(true);

    if (_currentHandle == null) {
      _currentHandle = await _soloud.play(_currentSource!, paused: false);
    } else {
      _soloud.setPause(_currentHandle!, false);
    }

    _endedEmittedForPath = null;
  }

  @override
  Future<void> pause() async {
    if (_currentHandle == null) return;
    _soloud.setPause(_currentHandle!, true);
  }

  @override
  Future<void> seek(Duration position) async {
    if (_currentHandle == null) return;
    _soloud.seek(_currentHandle!, position);
  }
}

