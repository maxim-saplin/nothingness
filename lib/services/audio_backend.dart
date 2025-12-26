import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/audio_track.dart';
import '../models/song_info.dart';
import '../models/spectrum_settings.dart';

abstract class AudioBackend {
  ValueNotifier<List<AudioTrack>> get queueNotifier;
  ValueNotifier<int?> get currentIndexNotifier;
  ValueNotifier<bool> get shuffleNotifier;
  ValueNotifier<SongInfo?> get songInfoNotifier;
  ValueNotifier<bool> get isPlayingNotifier;
  Stream<List<double>> get spectrumStream;

  Future<void> init();
  Future<void> dispose();

  Future<void> setQueue(
    List<AudioTrack> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  });

  Future<void> addTracks(List<AudioTrack> tracks, {bool play = false});

  Future<void> playPause();
  Future<void> next();
  Future<void> previous();
  Future<void> playFromQueueIndex(int orderIndex);
  Future<void> seek(Duration position);
  Future<void> shuffleQueue();
  Future<void> disableShuffle();

  void setCaptureEnabled(bool enabled);
  void updateSpectrumSettings(SpectrumSettings settings);
  
  Future<int> playlistSizeBytes();

  Future<List<AudioTrack>> scanFolder(String rootPath);
}
