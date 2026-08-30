import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

void main() {
  test('supported locales define direction centrally', () {
    expect(
      LifeMateLocaleRegistry.resolve(const Locale('fa')).textDirection,
      TextDirection.rtl,
    );
    expect(
      LifeMateLocaleRegistry.resolve(const Locale('en')).textDirection,
      TextDirection.ltr,
    );
    expect(
      LifeMateLocaleRegistry.resolve(const Locale('de')).languageCode,
      'en',
    );
  });

  test('canonical shared keys are complete in Persian and English', () {
    const required = <String>{
      'common.cancel',
      'common.save',
      'common.retry',
      'common.close',
      'common.loading',
      'common.notEnoughInformation',
      'common.edit',
      'profile.demographics.title',
      'profile.demographics.gender',
      'profile.demographics.sexAtBirth',
      'profile.demographics.notCollected',
      'profile.demographics.woman',
      'profile.demographics.man',
      'profile.demographics.nonBinary',
      'profile.demographics.selfDescribe',
      'profile.demographics.preferNotToSay',
      'profile.demographics.female',
      'profile.demographics.male',
      'profile.demographics.intersex',
      'women.dailyLog.title',
      'women.dailyLog.logToday',
      'women.analytics.title',
      'women.analytics.full',
      'women.circle.create',
      'women.circle.noSharing',
      'women.insights.settings',
    };

    for (final key in required) {
      expect(lifeMateMessages.hasCompleteKey(key), isTrue, reason: key);
    }
    expect(
      lifeMateMessages.missingKeysFor(const Locale('en'), required),
      isEmpty,
    );
    expect(
      lifeMateMessages.missingKeysFor(const Locale('fa'), required),
      isEmpty,
    );
  });

  testWidgets('mixed direction content can be isolated', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: LifeMateBidiText(
            'user@example.com',
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
    );

    final directionality = tester.widget<Directionality>(
      find.ancestor(
        of: find.text('user@example.com'),
        matching: find.byType(Directionality),
      ).first,
    );
    expect(directionality.textDirection, TextDirection.ltr);
  });
}
