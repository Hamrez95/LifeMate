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
    'packages/lifemate_ui/lib/src/localization.dart',
    'packages/lifemate_ui/lib/src/locales/fa.dart',
}

# #674 is an incremental migration. These are real runner-derived baselines
# captured after the repository became public and the verifier finally ran
# against the complete checkout. Every migration must ratchet these downward;
# new debt is not allowed to grow any category.
LEGACY_LOCALE_BRANCH_FILE_BUDGET = 85
FIXED_RTL_OVERRIDE_BUDGET = 2
PERSIAN_RUNTIME_LITERAL_BUDGET = 321
NUMERIC_INPUT_VIOLATION_BUDGET = 4

MIGRATED_CATALOG_FILES = {
    'packages/lifemate_ui/lib/src/remote_config_gate.dart',
    'packages/lifemate_ui/lib/src/shared_account_onboarding.dart',
    'packages/lifemate_ui/lib/src/shared_profile_with_privacy.dart',
    'packages/lifemate_ui/lib/src/shared_legal_privacy.dart',
    'packages/lifemate_ui/lib/src/demographics_experience.dart',
    'wellmate/lib/screens/women_calendar/women_daily_log_launcher.dart',
    'wellmate/lib/screens/women_calendar/women_companion_people_hero.dart',
    'wellmate/lib/screens/women_calendar/women_health_entry_screen.dart',
    'wellmate/lib/screens/women_calendar/women_health_activation_v3_screen.dart',
    'wellmate/lib/screens/treatments/medication_schedule_preferences_screen.dart',
    'wellmate/lib/screens/treatments/medication_plan_timing_screen.dart',
    'wellmate/lib/screens/treatments/nearby_dose_optimization_screen.dart',
    'wellmate/lib/screens/treatments/grouped_medication_checklist_screen.dart',
}

# These surfaces have completed the stronger migration: user-facing copy must
# come from a message catalog, not from per-screen FA/EN branches. Keeping this
# list explicit makes the migration monotonic without pretending the whole app
# is catalog-only before #674 finishes.
CATALOG_ONLY_FILES = {
    'packages/lifemate_ui/lib/src/shared_legal_privacy.dart',
    'packages/lifemate_ui/lib/src/demographics_experience.dart',
    'wellmate/lib/screens/treatments/medication_schedule_preferences_screen.dart',
    'wellmate/lib/screens/treatments/medication_plan_timing_screen.dart',
    'wellmate/lib/screens/treatments/nearby_dose_optimization_screen.dart',
    'wellmate/lib/screens/treatments/grouped_medication_checklist_screen.dart',
}

errors: list[str] = []
metrics: dict[str, int] = {}


def fail(message: str) -> None:
    errors.append(message)


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding='utf-8')


def runtime_dart_files():
    for root in RUNTIME_DART_ROOTS:
        yield from root.rglob('*.dart')


def is_message_catalog_data(rel: str, text: str) -> bool:
    """Return true only for structured shared UI catalog data modules.

    Locale catalog files intentionally contain Persian literals as data. They
    are not runtime UI copy debt, but an arbitrary *_locales.dart file must not
    become a bypass: it must live in the shared localization package and expose
    a LifeMateMessageCatalog backed by string maps.
    """
    return (
        rel.startswith('packages/lifemate_ui/lib/src/')
        and rel.endswith('_locales.dart')
        and 'LifeMateMessageCatalog' in text
        and 'Map<String, String>' in text
    )


def ratchet(name: str, actual: int, budget: int, details: list[str]) -> None:
    metrics[name] = actual
    if actual <= budget:
        return
    sample = details[:12]
    suffix = '' if len(details) <= len(sample) else f' (+{len(details) - len(sample)} more)'
    fail(
        f'{name} grew beyond #674 baseline: {actual} > {budget}; '
        f'sample={sample}{suffix}'
    )


def check_root_direction(rel: str) -> None:
    text = read(rel)
    if 'TextDirection.rtl' not in text or 'TextDirection.ltr' not in text:
        fail(f'{rel}: root app must contain explicit RTL and LTR branches')
    if "languageCode == 'fa'" not in text:
        fail(f'{rel}: root direction must be driven by locale languageCode')


def check_legacy_locale_branch_ratchet() -> None:
    legacy_files: list[str] = []
    needle = 'LifeMateRuntimeLocale.select('
    for path in runtime_dart_files():
        text = path.read_text(encoding='utf-8')
        if needle not in text:
            continue
        rel = path.relative_to(ROOT).as_posix()
        legacy_files.append(rel)
        if rel in MIGRATED_CATALOG_FILES:
            fail(f'{rel}: migrated catalog surface regressed to LifeMateRuntimeLocale.select')
    ratchet(
        'legacy locale-branch files',
        len(legacy_files),
        LEGACY_LOCALE_BRANCH_FILE_BUDGET,
        sorted(legacy_files),
    )


def check_catalog_only_surfaces() -> None:
    feature_catalog_consumer = re.compile(r'context\.\w+Tr\(')
    for rel in sorted(CATALOG_ONLY_FILES):
        text = read(rel)
        if 'LifeMateRuntimeLocale.select(' in text:
            fail(f'{rel}: catalog-only surface regressed to LifeMateRuntimeLocale.select')
        if re.search(r'\b_copy\s*\(', text):
            fail(f'{rel}: catalog-only surface regressed to a per-screen _copy FA/EN branch')
        for literal in scan_dart_string_literals(text):
            if PERSIAN_RE.search(literal.body):
                fail(
                    f'{rel}:{literal.line}: catalog-only surface contains inline Persian copy: '
                    f'{literal.body[:60]!r}'
                )
        if (
            'context.tr(' not in text
            and 'lifeMateMessages.text(' not in text
            and feature_catalog_consumer.search(text) is None
        ):
            fail(f'{rel}: catalog-only surface does not consume a message catalog')


def check_no_fixed_rtl() -> None:
    needle = 'textDirection: TextDirection.rtl,'
    violations: list[str] = []
    for path in runtime_dart_files():
        rel = path.relative_to(ROOT).as_posix()
        if rel == 'packages/lifemate_ui/lib/src/localization.dart':
            continue
        text = path.read_text(encoding='utf-8')
        if needle in text:
            violations.append(rel)
    ratchet(
        'fixed RTL overrides',
        len(violations),
        FIXED_RTL_OVERRIDE_BUDGET,
        sorted(violations),
    )


def check_persian_literals_are_guarded() -> None:
    violations: list[str] = []
    for path in runtime_dart_files():
        rel = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding='utf-8')
        if rel in PERSIAN_IMPLEMENTATION_FILES or is_message_catalog_data(rel, text):
            continue
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
                re.search(r'(?:isPersian|persian|\bfa\b|\brtl\b)\s*\?', context)
                is not None
                and re.search(r"\:\s*['\"]", context) is not None
            )
            guarded_branch = (
                re.search(r'if\s*\(\s*!?(?:isPersian|persian|fa|rtl)\s*\)', context)
                is not None
            )
            if guarded_select or guarded_ternary or guarded_branch:
                continue
            violations.append(
                f'{rel}:{literal.line}:{literal.body[:60]!r}'
            )
    ratchet(
        'unguarded Persian runtime literals',
        len(violations),
        PERSIAN_RUNTIME_LITERAL_BUDGET,
        violations,
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
    violations: list[str] = []

    for path in runtime_dart_files():
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
            violations.append(f'{path.relative_to(ROOT).as_posix()}:{line}')
    ratchet(
        'locale-unsafe numeric/phone inputs',
        len(violations),
        NUMERIC_INPUT_VIOLATION_BUDGET,
        violations,
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
    check_legacy_locale_branch_ratchet()
    check_catalog_only_surfaces()
    check_no_fixed_rtl()
    check_persian_literals_are_guarded()
    check_gregorian_english_contract()
    check_numeric_inputs()
    check_android_widget()

    print('Localization debt metrics:')
    for name, actual in metrics.items():
        print(f'- {name}: {actual}')

    if errors:
        print(f'English localization contract FAILED with {len(errors)} issue(s):')
        for error in errors:
            print(f'- {error}')
        return 1
    print(
        'English localization contract passed: existing debt did not grow; '
        'copy, LTR, Gregorian dates, Latin digits, and native widget ratchets are green.'
    )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
