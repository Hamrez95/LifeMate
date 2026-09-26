import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/modules/module_registry.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  testWidgets('production modules expose their actions in the shared profile', (
    tester,
  ) async {
    final registry = LifeMateModuleRegistry.production();
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'test-token',
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ListView(
              children: [
                ...registry
                    .byId(LifeMateModuleId.wellMate)!
                    .profileSectionsBuilder!(context, api, false),
                ...registry
                    .byId(LifeMateModuleId.careMate)!
                    .profileSectionsBuilder!(context, api, false),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('WellMate health & care'), findsOneWidget);
    expect(find.text('Health documents'), findsOneWidget);
    expect(find.text('Caregiver access'), findsOneWidget);
    expect(find.text('CareMate caregiving'), findsOneWidget);
    expect(find.text('People under care'), findsOneWidget);
    expect(find.text('Access and consent'), findsOneWidget);
  });
}
