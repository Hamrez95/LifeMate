import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

void main() {
  test('supported locales define direction centrally', () {
    expect(LifeMateLocaleRegistry.resolve(const Locale('fa')).textDirection, TextDirection.rtl);
    expect(LifeMateLocaleRegistry.resolve(const Locale('en')).textDirection, TextDirection.ltr);
    expect(LifeMateLocaleRegistry.resolve(const Locale('de')).languageCode, 'en');
  });

  test('canonical shared keys are complete in Persian and English', () {
    const required = <String>{
      'common.cancel','common.save','common.saved','common.retry','common.close',
      'common.loading','common.notEnoughInformation','common.edit','common.update',
      'common.later','common.checkAgain',
      'runtimeConfig.offline','runtimeConfig.softUpdate','runtimeConfig.force.title',
      'runtimeConfig.force.security','runtimeConfig.force.incompatible',
      'runtimeConfig.force.updateLifeMate',
      'profile.companionGuidance.semantic','profile.companionGuidance.label',
      'profile.feedback.semantic','profile.feedback.label',
      'profile.demographics.title','profile.demographics.semantic',
      'profile.demographics.gender','profile.demographics.sexAtBirth',
      'profile.demographics.notCollected','profile.demographics.woman',
      'profile.demographics.man','profile.demographics.nonBinary',
      'profile.demographics.selfDescribe','profile.demographics.preferNotToSay',
      'profile.demographics.female','profile.demographics.male',
      'profile.demographics.intersex','profile.privacy.semantic','profile.privacy.label',
      'women.dailyLog.title','women.dailyLog.logToday','women.analytics.title',
      'women.analytics.full','women.circle.create','women.circle.noSharing',
      'women.insights.settings',
    };
    for (final key in required) {
      expect(lifeMateMessages.hasCompleteKey(key), isTrue, reason: key);
    }
    expect(lifeMateMessages.missingKeysFor(const Locale('en'), required), isEmpty);
    expect(lifeMateMessages.missingKeysFor(const Locale('fa'), required), isEmpty);
  });

  test('migrated shared surfaces do not use legacy locale branching', () {
    for (final path in <String>[
      'lib/src/shared_profile_with_privacy.dart',
      'lib/src/remote_config_gate.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('LifeMateRuntimeLocale.select(')), reason: path);
    }
    final remote = File('lib/src/remote_config_gate.dart').readAsStringSync();
    expect(remote, contains("context.tr('runtimeConfig.force.title')"));
    expect(remote, contains('PositionedDirectional('));
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
