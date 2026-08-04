from pathlib import Path

path = Path('caremate/lib/screens/calendar/calendar_screen.dart')
text = path.read_text(encoding='utf-8')
old = '''                            child: ListView(
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
                            ),'''
new = '''                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
                              child: Column(
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
                              ),
                            ),'''
if old in text:
    path.write_text(text.replace(old, new, 1), encoding='utf-8')
elif new not in text:
    raise RuntimeError('Expected CareMate daily event ListView block was not found')
print('CareMate daily event list is now eagerly rendered.')
