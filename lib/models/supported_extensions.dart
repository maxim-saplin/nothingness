/// Centralized definition of supported audio file extensions.
/// 
/// This is the single source of truth for all supported audio formats
/// across the application. All services should reference these constants
/// rather than defining their own extension sets.
class SupportedExtensions {
  SupportedExtensions._();

  /// Supported extensions without dots (e.g., 'mp3', 'flac').
  /// Use this for extension matching when you've already stripped the dot.
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
  /// Use this for filename parsing and extension checking.
  static const Set<String> supportedExtensionsWithDots = {
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.flac',
    '.ogg',
    '.opus',
  };

  /// Strips a trailing supported-audio extension from a display title, e.g.
  /// "Nirvana - Smells like Teen Spirit.mp3" -> "Nirvana - Smells like Teen
  /// Spirit". MediaStore sometimes returns the on-disk filename verbatim when
  /// the file lacks a proper ID3 title tag — we never want to show ".mp3" or
  /// ".flac" to the user.
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



