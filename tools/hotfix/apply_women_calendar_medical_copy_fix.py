from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / 'wellmate/lib/screens/women_calendar/women_calendar_screen.dart'

old = (
    'این زمان‌بندی فقط یک تخمین بر اساس اطلاعات ثبت‌شده شماست و برای تشخیص، '
    'پیشگیری یا تعیین باروری استفاده نمی‌شود. در صورت خون‌ریزی غیرعادی، درد شدید '
    'یا نگرانی پزشکی با پزشک تماس بگیرید.'
)
new = (
    'تاریخ‌ها تخمینی هستند و جایگزین نظر پزشک نیستند. این زمان‌بندی فقط بر اساس '
    'اطلاعات ثبت‌شده شما محاسبه می‌شود و برای تشخیص، پیشگیری از بارداری یا تعیین '
    'باروری استفاده نمی‌شود. در صورت خون‌ریزی غیرعادی، درد شدید یا نگرانی پزشکی '
    'با پزشک تماس بگیرید.'
)

text = TARGET.read_text(encoding='utf-8')
if old not in text:
    if new in text:
        print('Women calendar medical disclaimer already current.')
        raise SystemExit(0)
    raise SystemExit('Expected women calendar medical disclaimer was not found.')

TARGET.write_text(text.replace(old, new, 1), encoding='utf-8')
print('Women calendar medical disclaimer patch applied.')
