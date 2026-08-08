class CarePairingQr {
  const CarePairingQr._();

  static const scheme = 'lifemate';
  static const host = 'care-invite';
  static const version = '1';

  static String encodeToken(String token) {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        token,
        'token',
        'Invitation token is required.',
      );
    }
    return Uri(
      scheme: scheme,
      host: host,
      queryParameters: {'v': version, 'token': normalized},
    ).toString();
  }

  static String? tryParseToken(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;

    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.scheme.toLowerCase() != scheme ||
        uri.host.toLowerCase() != host ||
        uri.queryParameters['v'] != version) {
      return null;
    }

    final token = uri.queryParameters['token']?.trim();
    if (token == null || token.length < 24 || token.length > 512) return null;
    return token;
  }
}
