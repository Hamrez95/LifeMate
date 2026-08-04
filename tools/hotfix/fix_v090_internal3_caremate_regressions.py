from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text(encoding='utf-8')
    if old in text:
        target.write_text(text.replace(old, new, 1), encoding='utf-8')
        return
    if new not in text:
        raise RuntimeError(f'Expected block not found in {path}: {old[:160]!r}')


replace(
    'caremate/lib/screens/calendar/calendar_view.dart',
    '''          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 0.92,
          ),''',
    '''          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 42,
          ),''',
)

replace(
    'caremate/lib/screens/calendar/calendar_screen.dart',
    "import '../../core/utils/string_extensions.dart';\n",
    '',
)

replace(
    'caremate/lib/screens/calendar/calendar_screen.dart',
    '''                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
                              itemCount: eventsForSelectedDay.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (_, index) => ScheduleCard(
                                event: eventsForSelectedDay[index],
                                font: font,
                                isPersian: isPersian,
                              ),
                            ),''',
    '''                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
                              children: [
                                for (var index = 0;
                                    index < eventsForSelectedDay.length;
                                    index++) ...[
                                  if (index > 0) const SizedBox(height: 12),
                                  ScheduleCard(
                                    event: eventsForSelectedDay[index],
                                    font: font,
                                    isPersian: isPersian,
                                  ),
                                ],
                              ],
                            ),''',
)

for test_path in (
    'caremate/test/calendar_care_events_test.dart',
    'caremate/test/care_event_management_accessibility_test.dart',
):
    target = Path(test_path)
    text = target.read_text(encoding='utf-8')
    text = text.replace("find.text('ویتامین B12'", "find.text('ویتامین B۱۲'")
    target.write_text(text, encoding='utf-8')

print('CareMate Jalali layout and Persian-digit test regressions fixed.')
