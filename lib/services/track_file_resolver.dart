class TrackResolutionException implements Exception {
  const TrackResolutionException(this.cause);

  final Object cause;

  @override
  String toString() => 'Could not retrieve track: $cause';
}

abstract interface class TrackFileResolver {
  bool supports(String trackPath);

  Future<String> resolveLocalPath(String trackPath, {bool preloading = false});

  void pin(String trackPath);

  void unpin(String trackPath);
}
