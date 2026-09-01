import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

void main() {
  test('legal/privacy feature catalog has exact Persian and English parity', () {
    expect(
      lifeMateLegalPrivacyEnglishMessages.keys.toSet(),
      lifeMateLegalPrivacyRequiredKeys,
    );
    expect(
      lifeMateLegalPrivacyPersianMessages.keys.toSet(),
      lifeMateLegalPrivacyRequiredKeys,
    );
    expect(
      lifeMateLegalPrivacyMessages.missingKeysFor(
        const Locale('en'),
        lifeMateLegalPrivacyRequiredKeys,
      ),
      isEmpty,
    );
    expect(
      lifeMateLegalPrivacyMessages.missingKeysFor(
        const Locale('fa'),
        lifeMateLegalPrivacyRequiredKeys,
      ),
      isEmpty,
    );
  });

  test('legal/privacy interpolation and fallback follow locale registry', () {
    expect(
      lifeMateLegalPrivacyMessages.text(
        'legal.registration.documentVersion',
        locale: const Locale('en'),
        params: const <String, Object?>{'version': 'v3'},
      ),
      'Version v3',
    );
    expect(
      lifeMateLegalPrivacyMessages.text(
        'legal.registration.documentVersion',
        locale: const Locale('fa'),
        params: const <String, Object?>{'version': 'v3'},
      ),
      'نسخه v3',
    );
    expect(
      lifeMateLegalPrivacyMessages.text(
        'legal.registration.title',
        locale: const Locale('de'),
      ),
      'Terms & Privacy',
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

  test('shared legal/privacy surface no longer branches on runtime locale', () {
    final source =
        File('lib/src/shared_legal_privacy.dart').readAsStringSync();

    expect(source, isNot(contains('LifeMateRuntimeLocale.select(')));
    expect(source, contains('context.lifeMateLocale.textDirection'));
    expect(source, contains('EdgeInsetsDirectional'));
    expect(source, contains("_errorKey = 'legal.registration.loadFailed'"));
    expect(source, contains("context.legalPrivacyTr(_errorKey!)"));
  });
}
