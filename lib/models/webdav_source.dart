class WebDavSource {
  const WebDavSource({
    required this.id,
    required this.name,
    required this.serverUrl,
    required this.username,
    required this.folderPath,
    this.lastSyncedAtMs,
  });

  final String id;
  final String name;
  final String serverUrl;
  final String username;
  final String folderPath;
  final int? lastSyncedAtMs;

  WebDavSource copyWith({int? lastSyncedAtMs}) => WebDavSource(
    id: id,
    name: name,
    serverUrl: serverUrl,
    username: username,
    folderPath: folderPath,
    lastSyncedAtMs: lastSyncedAtMs ?? this.lastSyncedAtMs,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'serverUrl': serverUrl,
    'username': username,
    'folderPath': folderPath,
    'lastSyncedAtMs': lastSyncedAtMs,
  };

  factory WebDavSource.fromJson(Map<dynamic, dynamic> json) => WebDavSource(
    id: json['id'] as String,
    name: json['name'] as String,
    serverUrl: json['serverUrl'] as String,
    username: json['username'] as String,
    folderPath: json['folderPath'] as String,
    lastSyncedAtMs: json['lastSyncedAtMs'] as int?,
  );
}

class WebDavEntry {
  const WebDavEntry({
    required this.name,
    required this.relativePath,
    required this.isDirectory,
    this.size,
    this.etag,
    this.lastModified,
    this.contentType,
  });

  final String name;
  final String relativePath;
  final bool isDirectory;
  final int? size;
  final String? etag;
  final DateTime? lastModified;
  final String? contentType;

  Map<String, Object?> toJson() => {
    'name': name,
    'relativePath': relativePath,
    'isDirectory': isDirectory,
    'size': size,
    'etag': etag,
    'lastModifiedMs': lastModified?.millisecondsSinceEpoch,
    'contentType': contentType,
  };

  factory WebDavEntry.fromJson(Map<dynamic, dynamic> json) => WebDavEntry(
    name: json['name'] as String,
    relativePath: json['relativePath'] as String,
    isDirectory: json['isDirectory'] as bool,
    size: json['size'] as int?,
    etag: json['etag'] as String?,
    lastModified: (json['lastModifiedMs'] as int?) == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            json['lastModifiedMs'] as int,
            isUtc: true,
          ),
    contentType: json['contentType'] as String?,
  );
}

class WebDavDirectoryListing {
  const WebDavDirectoryListing({
    required this.etag,
    required this.isDirectory,
    required this.entries,
  });

  final String? etag;
  final bool isDirectory;
  final List<WebDavEntry> entries;
}

class WebDavSyncProgress {
  const WebDavSyncProgress({
    required this.sourceId,
    required this.foldersScanned,
    required this.tracksIndexed,
    required this.isComplete,
    this.error,
  });

  final String sourceId;
  final int foldersScanned;
  final int tracksIndexed;
  final bool isComplete;
  final String? error;
}

class WebDavTransferProgress {
  const WebDavTransferProgress({
    required this.trackPath,
    required this.bytesReceived,
    this.totalBytes,
    required this.isPreload,
  });

  final String trackPath;
  final int bytesReceived;
  final int? totalBytes;
  final bool isPreload;

  double? get fraction => totalBytes == null || totalBytes == 0
      ? null
      : (bytesReceived / totalBytes!).clamp(0.0, 1.0);
}
