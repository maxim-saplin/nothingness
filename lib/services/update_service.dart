import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'platform_channels.dart';

enum UpdatePhase { none, available, downloading, installing }

/// Android self-update from GitHub Releases. The APK only lives in the app
/// cache dir for one attempt: it is deleted once the install is committed or
/// has failed, and [sweep] clears any leftover at launch.
class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  static final Uri _latestRelease = Uri.parse(
    'https://api.github.com/repos/maxim-saplin/nothingness/releases/latest',
  );
  static const _checkInterval = Duration(hours: 1);
  static const _timeout = Duration(seconds: 30);

  final phase = ValueNotifier<UpdatePhase>(UpdatePhase.none);

  /// Download progress, whole percent. An int so the notifier only fires on
  /// visible changes instead of once per network chunk.
  final percent = ValueNotifier<int>(0);

  /// `3.15.0+83`, the version shown on the update chip.
  String version = '';

  Uri? _apkUrl;
  DateTime? _checkedAt;

  /// The newer release in a `releases/latest` payload, or null when the tag is
  /// malformed, the build is not newer, or no matching APK is attached.
  static ({String version, Uri url})? parseRelease(
    Map<String, dynamic> json,
    int currentBuild,
  ) {
    final tag = json['tag_name'] as String? ?? '';
    final build = int.tryParse(tag.split('+').last);
    if (build == null || build <= currentBuild) return null;
    final assets = json['assets'] as List<dynamic>? ?? const [];
    for (final asset in assets.cast<Map<String, dynamic>>()) {
      final name = asset['name'] as String;
      if (name.startsWith('nothingness-android-') && name.endsWith('.apk')) {
        return (
          version: tag.replaceFirst(RegExp('^v'), ''),
          url: Uri.parse(asset['browser_download_url'] as String),
        );
      }
    }
    return null;
  }

  /// Looks for a newer release. Never throws: offline or rate-limited simply
  /// means no chip. Throttled to one GitHub request per [_checkInterval].
  Future<void> check() async {
    if (phase.value != UpdatePhase.none) return;
    final last = _checkedAt;
    if (last != null && DateTime.now().difference(last) < _checkInterval) return;
    _checkedAt = DateTime.now();
    try {
      final info = await PackageInfo.fromPlatform();
      final response = await http.get(_latestRelease).timeout(_timeout);
      if (response.statusCode != 200) return;
      final release = parseRelease(
        jsonDecode(response.body) as Map<String, dynamic>,
        int.parse(info.buildNumber),
      );
      if (release == null) return;
      version = release.version;
      _apkUrl = release.url;
      phase.value = UpdatePhase.available;
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  }

  /// Downloads the available APK and commits it to the system installer, which
  /// then asks the user to confirm. Failures reset the chip so the user can retry.
  Future<void> start() async {
    final url = _apkUrl;
    if (phase.value != UpdatePhase.available || url == null) return;
    phase.value = UpdatePhase.downloading;
    percent.value = 0;
    try {
      if (!await PlatformChannels().ensureInstallPermission()) return;
      final dir = Directory(await _updateDir());
      await dir.create(recursive: true);
      final file = File('${dir.path}/update.apk');

      final client = http.Client();
      try {
        final response = await client
            .send(http.Request('GET', url))
            .timeout(_timeout);
        if (response.statusCode != 200) {
          throw HttpException('HTTP ${response.statusCode}', uri: url);
        }
        final total = response.contentLength ?? 0;
        var received = 0;
        await response.stream
            .timeout(_timeout)
            .map((chunk) {
              received += chunk.length;
              if (total > 0) percent.value = received * 100 ~/ total;
              return chunk;
            })
            .pipe(file.openWrite());
      } finally {
        client.close();
      }

      phase.value = UpdatePhase.installing;
      await PlatformChannels().installApk(file.path);
    } catch (e) {
      debugPrint('Update download/install failed: $e');
    } finally {
      phase.value = UpdatePhase.available;
      await _deleteDownload();
    }
  }

  /// Launch-time cleanup after a process was killed mid-attempt. Not called
  /// after an attempt: that could abandon a committed session the user is
  /// still confirming.
  Future<void> sweep() async {
    await PlatformChannels().abandonInstallSessions();
    await _deleteDownload();
  }

  Future<void> _deleteDownload() async {
    try {
      await Directory(await _updateDir()).delete(recursive: true);
    } on FileSystemException {
      // Nothing was downloaded: the directory is absent, which is the normal case.
    }
  }

  @visibleForTesting
  void reset() {
    phase.value = UpdatePhase.none;
    percent.value = 0;
    version = '';
    _apkUrl = null;
    _checkedAt = null;
  }

  Future<String> _updateDir() async =>
      '${(await getTemporaryDirectory()).path}/update';
}
