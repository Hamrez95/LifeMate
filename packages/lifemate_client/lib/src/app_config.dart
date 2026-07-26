class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.apiBaseUrl,
  });

  factory AppConfig.fromEnvironment() => const AppConfig(
        supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
        supabasePublishableKey:
            String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
        apiBaseUrl: String.fromEnvironment('LIFEMATE_API_BASE_URL'),
      );

  final String supabaseUrl;
  final String supabasePublishableKey;
  final String apiBaseUrl;

  bool get isConfigured =>
      _isHttpsUrl(supabaseUrl) &&
      supabasePublishableKey.startsWith('sb_publishable_') &&
      _isHttpUrl(apiBaseUrl);

  List<String> get missingOrInvalidValues => [
        if (!_isHttpsUrl(supabaseUrl)) 'SUPABASE_URL',
        if (!supabasePublishableKey.startsWith('sb_publishable_'))
          'SUPABASE_PUBLISHABLE_KEY',
        if (!_isHttpUrl(apiBaseUrl)) 'LIFEMATE_API_BASE_URL',
      ];

  Uri get apiBaseUri {
    if (!_isHttpUrl(apiBaseUrl)) {
      throw StateError('LifeMate API base URL is not configured.');
    }
    return Uri.parse(apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl);
  }

  static bool _isHttpsUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  static bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'https' ||
            (uri.scheme == 'http' &&
                (uri.host == 'localhost' || uri.host == '10.0.2.2'))) &&
        uri.host.isNotEmpty;
  }
}
