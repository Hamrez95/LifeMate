#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / 'tools' / 'localization'
sys.path.insert(0, str(TOOLS))
from dart_string_scanner import scan_dart_string_literals  # noqa: E402

PERSIAN_RE = re.compile(r'[\u0600-\u06ff\u0750-\u077f\u08a0-\u08ff\ufb50-\ufdff\ufe70-\ufeff]')
RUNTIME_DART_ROOTS = [
    ROOT / 'wellmate' / 'lib',
    ROOT / 'caremate' / 'lib',
    ROOT / 'packages' / 'lifemate_client' / 'lib',
    ROOT / 'packages' / 'lifemate_ui' / 'lib',
]
PERSIAN_IMPLEMENTATION_FILES = {
    'wellmate/lib/core/utils/persian_date_utils.dart',
    'caremate/lib/core/utils/persian_date_utils.dart',
    'wellmate/lib/core/utils/string_extensions.dart',
    'caremate/lib/core/utils/string_extensions.dart',
    'packages/lifemate_client/lib/src/presentation_numbers.dart',
    'packages/lifemate_client/lib/src/runtime_locale.dart',
}

errors: list[str] = []


def fail(message: str) -> None:
    errors.append(message)


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding='utf-8')


def check_root_direction(rel: str) -> None:
    text = read(rel)
    if 'TextDirection.rtl' not in text or 'TextDirection.ltr' not in text:
        fail(f'{rel}: root app must contain explicit RTL and LTR branches')
    if "languageCode == 'fa'" not in text:
        fail(f'{rel}: root direction must be driven by locale languageCode')


def check_no_fixed_rtl() -> None:
    needle = 'textDirection: TextDirection.rtl,'
    for root in RUNTIME_DART_ROOTS:
        for path in root.rglob('*.dart'):
            text = path.read_text(encoding='utf-8')
            if needle in text:
                rel = path.relative_to(ROOT).as_posix()
                fail(f'{rel}: fixed RTL override can reverse English UI')


def check_persian_literals_are_guarded() -> None:
    for root in RUNTIME_DART_ROOTS:
        for path in root.rglob('*.dart'):
            rel = path.relative_to(ROOT).as_posix()
            if rel in PERSIAN_IMPLEMENTATION_FILES:
                continue
            text = path.read_text(encoding='utf-8')
            for literal in scan_dart_string_literals(text):
                if not PERSIAN_RE.search(literal.body):
                    continue
                lo = max(0, literal.start - 500)
                hi = min(len(text), literal.end + 500)
                context = text[lo:hi]
                guarded_select = (
                    'LifeMateRuntimeLocale.select' in context and 'en:' in context
                )
                guarded_ternary = (
                    re.search(r'isPersian\s*\?', context) is not None
                    and re.search(r"\:\s*['\"]", context) is not None
                )
                guarded_branch = (
                    re.search(r'if\s*\(\s*!persian\s*\)', context) is not None
                )
                if not guarded_select and not guarded_ternary and not guarded_branch:
                    fail(
                        f'{rel}:{literal.line}: Persian runtime literal has no nearby English locale branch: '
                        f'{literal.body[:80]!r}'
                    )


def check_gregorian_english_contract() -> None:
    for rel in (
        'wellmate/lib/core/utils/persian_date_utils.dart',
        'caremate/lib/core/utils/persian_date_utils.dart',
    ):
        text = read(rel)
        required = (
            'if (!usesPersianCalendar(context))',
            'MaterialLocalizations.of(context).formatMediumDate(date)',
            'MaterialLocalizations.of(context).formatMonthYear(date)',
        )
        for token in required:
            if token not in text:
                fail(f'{rel}: missing Gregorian English date path: {token}')

    calendars = {
        'wellmate/lib/screens/calendar/custom_table_calendar.dart': "locale: 'en_US'",
        'caremate/lib/screens/calendar/calendar_view.dart': "locale: 'en_US'",
    }
    for rel, token in calendars.items():
        if token not in read(rel):
            fail(f'{rel}: English calendar must use Gregorian en_US TableCalendar')


def check_numeric_inputs() -> None:
    keyboard_re = re.compile(r'keyboardType:\s*TextInputType\.(?:number(?:WithOptions\([^)]*\))?|phone)')
    helper_declarations = ('Widget _textField(', 'class _Input ', 'class _ProfileField ')
    formatter_token = 'LifeMateLocaleDigitInputFormatter'

    for root in RUNTIME_DART_ROOTS:
        for path in root.rglob('*.dart'):
            text = path.read_text(encoding='utf-8')
            helper_is_digit_safe = (
                formatter_token in text
                and any(declaration in text for declaration in helper_declarations)
            )
            for match in keyboard_re.finditer(text):
                lo = max(0, match.start() - 500)
                hi = min(len(text), match.end() + 650)
                context = text[lo:hi]
                if formatter_token in context or helper_is_digit_safe:
                    continue
                line = text.count('\n', 0, match.start()) + 1
                fail(
                    f'{path.relative_to(ROOT).as_posix()}:{line}: numeric/phone input '
                    'must normalize digits in English mode'
                )


def check_android_widget() -> None:
    default_strings = read('wellmate/android/app/src/main/res/values/strings.xml')
    if PERSIAN_RE.search(default_strings):
        fail('WellMate default Android strings contain Persian copy; Persian belongs in values-fa')
    layout = read('wellmate/android/app/src/main/res/layout/wellmate_medication_widget.xml')
    if PERSIAN_RE.search(layout):
        fail('WellMate default widget layout contains Persian copy')
    if 'android:layoutDirection="rtl"' in layout:
        fail('WellMate default widget layout is hard-coded RTL')
    if 'android:textLocale="en-US"' not in layout:
        fail('WellMate widget lacks an explicit English chronometer locale')
    kotlin = read('wellmate/android/app/src/main/kotlin/com/lifemate/wellmate/MedicationWidgetProvider.kt')
    for token in ('LANGUAGE_CODE', 'bindLocale(', 'localizeDigits(', '"en"'):
        if token not in kotlin:
            fail(f'WellMate native widget missing locale contract token: {token}')


def main() -> int:
    check_root_direction('wellmate/lib/main.dart')
    check_root_direction('caremate/lib/main.dart')
    check_no_fixed_rtl()
    check_persian_literals_are_guarded()
    check_gregorian_english_contract()
    check_numeric_inputs()
    check_android_widget()

    if errors:
        print(f'English localization contract FAILED with {len(errors)} issue(s):')
        for error in errors:
            print(f'- {error}')
        return 1
    print('English localization contract passed: copy, LTR, Gregorian dates, Latin digits, and native widget checks are green.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
