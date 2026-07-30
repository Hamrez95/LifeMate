import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('configuration rejects missing values', () {
    const config = AppConfig(
      supabaseUrl: '',
      supabasePublishableKey: '',
      apiBaseUrl: '',
    );

    expect(config.isConfigured, isFalse);
    expect(
      config.missingOrInvalidValues,
      containsAll([
        'SUPABASE_URL',
        'SUPABASE_PUBLISHABLE_KEY',
        'LIFEMATE_API_BASE_URL',
      ]),
    );
  });

  test('configuration accepts https endpoints and publishable key', () {
    const config = AppConfig(
      supabaseUrl: 'https://example.supabase.co',
      supabasePublishableKey: 'sb_publishable_example',
      apiBaseUrl: 'https://api.example.com',
    );

    expect(config.isConfigured, isTrue);
    expect(config.apiBaseUri, Uri.parse('https://api.example.com'));
  });

  test('production API rejects insecure remote HTTP', () {
    const config = AppConfig(
      supabaseUrl: 'https://example.supabase.co',
      supabasePublishableKey: 'sb_publishable_example',
      apiBaseUrl: 'http://api.example.com',
    );

    expect(config.isConfigured, isFalse);
    expect(config.missingOrInvalidValues, contains('LIFEMATE_API_BASE_URL'));
  });
}
