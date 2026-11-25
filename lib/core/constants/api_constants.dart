class ApiConstants {
  ApiConstants._();

  static const String hostUrl = 'https://xfy.tn';
  static const String baseUrl = '$hostUrl/api';

  static String? resolveImageUrl(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('data:image')) {
      return null;
    }
    if (trimmed.startsWith('/')) {
      return '$hostUrl$trimmed';
    }
    return '$hostUrl/$trimmed';
  }
}
