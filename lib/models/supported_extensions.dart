/// Single source of truth for supported audio file extensions.
class SupportedExtensions {
  SupportedExtensions._();

  /// Supported extensions without dots (e.g., 'mp3', 'flac').
  static const Set<String> supportedExtensions = {
    'mp3',
    'm4a',
    'aac',
    'wav',
    'flac',
    'ogg',
    'opus',
  };

  /// Supported extensions with dots (e.g., '.mp3', '.flac').
  static const Set<String> supportedExtensionsWithDots = {
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.flac',
    '.ogg',
    '.opus',
  };

  /// Strips a trailing supported-audio extension from a display title.
  static String stripFromTitle(String title) {
    final dot = title.lastIndexOf('.');
    if (dot < 0) return title;
    final ext = title.substring(dot).toLowerCase();
    if (supportedExtensionsWithDots.contains(ext)) {
      return title.substring(0, dot);
    }
    return title;
  }
}

