import 'package:caremate/core/localization/locale_provider.dart';
import 'package:caremate/main.dart';
import 'package:caremate/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('profile route keeps LifeMateApiClient in scope',
      (WidgetTester tester) async {
    final api = _FakeCareMateApiClient();

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LocaleProvider(),
        child: CareMateApp(
          home: Provider<LifeMateApiClient>.value(
            value: api,
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      key: const Key('open-caremate-profile'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ProfileScreen(),
                        ),
                      ),
                      child: const Text('پروفایل'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-caremate-profile')));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('مراقب تست'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeCareMateApiClient extends LifeMateApiClient {
  _FakeCareMateApiClient()
      : super(
          baseUri: Uri.parse('https://example.invalid'),
          accessToken: () => 'test-token',
        );

  @override
  Future<Map<String, dynamic>> getCurrentUser() async => {
        'user': {
          'id': 'caregiver-1',
          'email': 'caregiver@example.com',
        },
        'profile': {
          'displayName': 'مراقب تست',
          'locale': 'fa',
          'timeZone': 'Asia/Tehran',
        },
      };
}
