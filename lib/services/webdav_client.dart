import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/webdav_source.dart';

class WebDavException implements Exception {
  const WebDavException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      statusCode == null ? message : '$message (HTTP $statusCode)';
}

/// Small authenticated WebDAV client for Nextcloud file/folder operations.
class WebDavClient {
  WebDavClient({
    required this.accountRoot,
    required this.username,
    required String password,
    required http.Client client,
  }) : _password = password,
       _client = client;

  static const _davNamespace = 'DAV:';
  static const _propfindBody = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:resourcetype/><d:getcontentlength/><d:getlastmodified/><d:getetag/><d:getcontenttype/></d:prop></d:propfind>''';

  final Uri accountRoot;
  final String username;
  final String _password;
  final http.Client _client;

  Uri uriFor(String relativePath) {
    final segments = relativePath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    return Uri(
      scheme: accountRoot.scheme,
      host: accountRoot.host,
      port: accountRoot.hasPort ? accountRoot.port : null,
      pathSegments: [...accountRoot.pathSegments, ...segments],
    );
  }

  Future<WebDavDirectoryListing> listDirectory(String relativePath) async {
    final response = await _propfind(relativePath, depth: '1');
    if (response.statusCode != 207) {
      throw WebDavException(
        'Could not list WebDAV folder',
        statusCode: response.statusCode,
      );
    }
    final listing = _parseListing(
      await response.stream.bytesToString(),
      relativePath,
    );
    if (!listing.isDirectory) {
      throw const WebDavException('WebDAV path is not a folder.');
    }
    return listing;
  }

  Future<String?> directoryEtag(String relativePath) async {
    final response = await _propfind(relativePath, depth: '0');
    if (response.statusCode != 207) {
      throw WebDavException(
        'Could not inspect WebDAV folder',
        statusCode: response.statusCode,
      );
    }
    return _parseListing(
      await response.stream.bytesToString(),
      relativePath,
    ).etag;
  }

  Future<http.StreamedResponse> openFile(String relativePath, {String? etag}) {
    final headers = <String, String>{};
    if (etag != null && etag.isNotEmpty) headers['If-Match'] = etag;
    return _send('GET', relativePath, headers: headers);
  }

  Future<http.StreamedResponse> _propfind(
    String relativePath, {
    required String depth,
  }) => _send(
    'PROPFIND',
    relativePath,
    headers: {'Depth': depth, 'Content-Type': 'application/xml; charset=utf-8'},
    body: _propfindBody,
  );

  Future<http.StreamedResponse> _send(
    String method,
    String relativePath, {
    Map<String, String> headers = const {},
    String? body,
  }) {
    final request = http.Request(method, uriFor(relativePath))
      ..followRedirects = false
      ..headers.addAll({
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$username:$_password'))}',
        'User-Agent': 'Nothingness-WebDAV/1.0',
        ...headers,
      });
    if (body != null) request.body = body;
    return _client.send(request);
  }

  WebDavDirectoryListing _parseListing(String xml, String requestedPath) {
    final document = XmlDocument.parse(xml);
    final requestedSegments = _segments(requestedPath);
    String? directoryEtag;
    var selfIsDirectory = false;
    final entries = <WebDavEntry>[];

    for (final response in document.findAllElements(
      'response',
      namespaceUri: _davNamespace,
    )) {
      final props = <String, XmlElement>{};
      for (final propstat in response.findElements(
        'propstat',
        namespaceUri: _davNamespace,
      )) {
        final status = propstat
            .getElement('status', namespaceUri: _davNamespace)
            ?.innerText;
        if (status != null && !status.contains(' 200 ')) continue;
        final prop = propstat.getElement('prop', namespaceUri: _davNamespace);
        if (prop == null) continue;
        for (final element in prop.childElements) {
          props['${element.name.namespaceUri}|${element.name.local}'] = element;
        }
      }

      final href = response
          .getElement('href', namespaceUri: _davNamespace)
          ?.innerText;
      if (href == null) continue;
      final returnedSegments = _segmentsFromHref(href);
      final isSelf = _sameSegments(returnedSegments, requestedSegments);
      final name = returnedSegments.isEmpty ? '' : returnedSegments.last;
      final resourceType = _prop(props, 'resourcetype');
      final isDirectory =
          resourceType
              ?.findElements('collection', namespaceUri: _davNamespace)
              .isNotEmpty ==
          true;
      final etag = _prop(props, 'getetag')?.innerText;

      if (isSelf) {
        directoryEtag = etag;
        selfIsDirectory = isDirectory;
        continue;
      }

      final relativePath = [...requestedSegments, name].join('/');
      final sizeText = _prop(props, 'getcontentlength')?.innerText;
      final size = sizeText == null || sizeText.isEmpty
          ? null
          : int.tryParse(sizeText);
      final modifiedText = _prop(props, 'getlastmodified')?.innerText;
      DateTime? lastModified;
      if (modifiedText != null && modifiedText.isNotEmpty) {
        try {
          lastModified = HttpDate.parse(modifiedText).toUtc();
        } on FormatException {
          lastModified = DateTime.tryParse(modifiedText)?.toUtc();
        }
      }

      entries.add(
        WebDavEntry(
          name: name,
          relativePath: relativePath,
          isDirectory: isDirectory,
          size: size,
          etag: etag,
          lastModified: lastModified,
          contentType: _prop(props, 'getcontenttype')?.innerText,
        ),
      );
    }

    return WebDavDirectoryListing(
      etag: directoryEtag,
      isDirectory: selfIsDirectory,
      entries: entries,
    );
  }

  XmlElement? _prop(Map<String, XmlElement> props, String localName) =>
      props['$_davNamespace|$localName'];

  List<String> _segmentsFromHref(String href) {
    final resolved = accountRoot.resolve(href);
    if (resolved.origin != accountRoot.origin) return const [];
    final allSegments = resolved.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final baseSegments = accountRoot.pathSegments;
    final startsWithBase =
        allSegments.length >= baseSegments.length &&
        List.generate(
          baseSegments.length,
          (i) => allSegments[i] == baseSegments[i],
        ).every((matches) => matches);
    return startsWithBase
        ? allSegments.skip(baseSegments.length).toList(growable: false)
        : allSegments;
  }

  List<String> _segments(String path) => path
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);

  bool _sameSegments(List<String> a, List<String> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((same) => same);
}
