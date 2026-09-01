import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

void main() {
  test('demographics catalog has exact Persian and English parity', () {
    expect(
      lifeMateDemographicsEnglishMessages.keys.toSet(),
      lifeMateDemographicsRequiredKeys,
    );
    expect(
      lifeMateDemographicsPersianMessages.keys.toSet(),
      lifeMateDemographicsRequiredKeys,
    );
    expect(
      lifeMateDemographicsMessages.missingKeysFor(
        const Locale('en'),
        lifeMateDemographicsRequiredKeys,
      ),
      isEmpty,
    );
    expect(
      lifeMateDemographicsMessages.missingKeysFor(
        const Locale('fa'),
        lifeMateDemographicsRequiredKeys,
      ),
      isEmpty,
    );
  });

  test('demographics fallback and direction use the shared locale registry', () {
    expect(
      lifeMateDemographicsMessages.text(
        'demographics.editorTitle',
        locale: const Locale('de'),
      ),
      'Gender & demographics',
    );
    expect(
      LifeMateLocaleRegistry.resolve(const Locale('fa')).textDirection,
      TextDirection.rtl,
    );
    expect(
      LifeMateLocaleRegistry.resolve(const Locale('en')).textDirection,
      TextDirection.ltr,
    );
  });

  test('demographics surfaces no longer branch on runtime locale', () {
    final source =
        File('lib/src/demographics_experience.dart').readAsStringSync();

    expect(source, isNot(contains('LifeMateRuntimeLocale.select(')));
    expect(source, isNot(contains('LifeMateRuntimeLocale.isPersian')));
    expect(source, contains('context.lifeMateLocale.textDirection'));
    expect(source, contains('EdgeInsetsDirectional'));
    expect(source, contains("_errorKey = 'demographics.loadFailed'"));
    expect(source, contains('context.demographicsTr(_errorKey!)'));
  });
}
