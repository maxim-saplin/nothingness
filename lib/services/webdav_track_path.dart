class WebDavTrackPath {
  WebDavTrackPath._();

  static const scheme = 'webdav';

  static bool isRemote(String path) => Uri.tryParse(path)?.scheme == scheme;

  static String root(String sourceId) =>
      Uri(scheme: scheme, host: sourceId, path: '/').toString();

  static String encode(String sourceId, String relativePath) {
    final segments = _segments(relativePath);
    if (segments.isEmpty) return root(sourceId);
    return Uri(
      scheme: scheme,
      host: sourceId,
      pathSegments: segments,
    ).toString();
  }

  static String sourceId(String path) {
    final uri = Uri.parse(path);
    if (uri.scheme != scheme || uri.host.isEmpty) {
      throw FormatException('Not a WebDAV track path', path);
    }
    return uri.host;
  }

  static String relativePath(String path) {
    final uri = Uri.parse(path);
    if (uri.scheme != scheme || uri.host.isEmpty) {
      throw FormatException('Not a WebDAV track path', path);
    }
    return uri.pathSegments.join('/');
  }

  static String basename(String path) {
    final segments = Uri.parse(path).pathSegments;
    return segments.isEmpty ? '' : segments.last;
  }

  static String parent(String path) {
    final uri = Uri.parse(path);
    if (uri.scheme != scheme || uri.host.isEmpty) return '';
    final segments = uri.pathSegments;
    if (segments.length <= 1) return root(uri.host);
    return Uri(
      scheme: scheme,
      host: uri.host,
      pathSegments: segments.take(segments.length - 1),
    ).toString();
  }

  static String displayPath(String path, String sourceName) {
    final relative = relativePath(path);
    return relative.isEmpty ? sourceName : '$sourceName/$relative';
  }

  static List<String> _segments(String path) => path
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
}
