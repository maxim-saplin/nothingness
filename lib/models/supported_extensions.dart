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
}

