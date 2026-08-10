from pathlib import Path

path = Path('tools/hotfix/apply_wellmate_health_hub.py')
source = path.read_text(encoding='utf-8')

old_nav = '''value = replace_once(value, "              index: 4,\\n", "              index: 5,\\n", "home nav index")'''
new_nav = '''value = replace_once(
    value,
    "            _buildNavItem(\\n              icon: Icons.home_rounded,\\n              label: loc['nav_home'],\\n              index: 4,\\n              fontFamily: fontFamily,\\n            ),\\n",
    "            _buildNavItem(\\n              icon: Icons.home_rounded,\\n              label: loc['nav_home'],\\n              index: 5,\\n              fontFamily: fontFamily,\\n            ),\\n",
    "home nav index",
)'''
if old_nav not in source:
    raise RuntimeError('Expected bottom-nav patch line was not found.')
source = source.replace(old_nav, new_nav, 1)

old_treatment = '''value = replace_once(
    value,
    "      _currentIndex = 4;\\n",
    "      _currentIndex = 5;\\n",
    "post treatment home",
)'''
new_treatment = '''value = replace_once(
    value,
    "  void _treatmentCreated() {\\n    setState(() {\\n      _calendarRevision++;\\n      _treatmentsRevision++;\\n      _homeRevision++;\\n      _currentIndex = 4;\\n    });\\n  }\\n",
    "  void _treatmentCreated() {\\n    setState(() {\\n      _calendarRevision++;\\n      _treatmentsRevision++;\\n      _healthRevision++;\\n      _homeRevision++;\\n      _currentIndex = 5;\\n    });\\n  }\\n",
    "post treatment home",
)'''
if old_treatment not in source:
    raise RuntimeError('Expected treatment-created patch line was not found.')
source = source.replace(old_treatment, new_treatment, 1)

exec(compile(source, str(path), 'exec'))


def replace_file_once(file_path: str, old: str, new: str, label: str) -> None:
    target = Path(file_path)
    value = target.read_text(encoding='utf-8')
    count = value.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected one match, found {count}')
    target.write_text(value.replace(old, new, 1), encoding='utf-8')


# Keep the conditional women tab on its new index and return Home when disabled.
replace_file_once(
    'wellmate/lib/screens/home/home_screen.dart',
    '        if (!enabled && _currentIndex == 3) _currentIndex = 4;\n',
    '        if (!enabled && _currentIndex == 4) _currentIndex = 5;\n',
    'women runtime index',
)

# Update source-contract regression after Home moved to index 5.
replace_file_once(
    'wellmate/test/ui_regression_test.dart',
    "expect(source, contains('final Set<int> _visitedTabs = <int>{4}'));",
    "expect(source, contains('final Set<int> _visitedTabs = <int>{5}'));",
    'lazy tab regression contract',
)

# Health is always index 3; women is conditional index 4; Home is index 5.
replace_file_once(
    'wellmate/test/women_calendar_navigation_test.dart',
    '''    expect(find.byKey(const ValueKey('wellmate-nav-3')), findsNothing);
    expect(find.bySemanticsLabel('تقویم بانوان'), findsNothing);
    expect(find.byKey(const ValueKey('wellmate-nav-4')), findsOneWidget);
''',
    '''    expect(find.byKey(const ValueKey('wellmate-nav-3')), findsOneWidget);
    expect(find.bySemanticsLabel('سلامت'), findsOneWidget);
    expect(find.bySemanticsLabel('تقویم بانوان'), findsNothing);
    expect(find.byKey(const ValueKey('wellmate-nav-4')), findsNothing);
    expect(find.byKey(const ValueKey('wellmate-nav-5')), findsOneWidget);
''',
    'women disabled nav assertions',
)
replace_file_once(
    'wellmate/test/women_calendar_navigation_test.dart',
    '''    expect(find.byKey(const ValueKey('wellmate-nav-3')), findsOneWidget);
    expect(find.bySemanticsLabel('تقویم بانوان'), findsOneWidget);
    expect(find.byKey(const ValueKey('wellmate-nav-4')), findsOneWidget);
''',
    '''    expect(find.byKey(const ValueKey('wellmate-nav-3')), findsOneWidget);
    expect(find.bySemanticsLabel('سلامت'), findsOneWidget);
    expect(find.bySemanticsLabel('تقویم بانوان'), findsOneWidget);
    expect(find.byKey(const ValueKey('wellmate-nav-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('wellmate-nav-5')), findsOneWidget);
''',
    'women enabled nav assertions',
)
replace_file_once(
    'wellmate/test/women_calendar_navigation_test.dart',
    '          currentIndex: 4,\n',
    '          currentIndex: 5,\n',
    'women navigation home index',
)

# Scroll lazy ListView sections into view before asserting/tapping them.
replace_file_once(
    'wellmate/test/health_screen_test.dart',
    '''    expect(find.byKey(const ValueKey('health-title')), findsOneWidget);
    expect(find.text('سلامت من'), findsOneWidget);
    expect(find.byKey(const ValueKey('health-quick-log')), findsOneWidget);
    expect(find.text('ثبت سریع'), findsOneWidget);
    expect(find.byKey(const ValueKey('health-calendar-history')), findsOneWidget);
    expect(find.text('تاریخچه سلامت'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, -1600));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('health-gadgets-coming-soon')), findsOneWidget);
    expect(find.text('به‌زودی'), findsOneWidget);
''',
    '''    expect(find.byKey(const ValueKey('health-title')), findsOneWidget);
    expect(find.text('سلامت من'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('health-quick-log')),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('health-quick-log')), findsOneWidget);
    expect(find.text('ثبت سریع'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('health-calendar-history')),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('health-calendar-history')), findsOneWidget);
    expect(find.text('تاریخچه سلامت'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('health-gadgets-coming-soon')),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('health-gadgets-coming-soon')), findsOneWidget);
    expect(find.text('به‌زودی'), findsOneWidget);
''',
    'health screen lazy sections test',
)
replace_file_once(
    'wellmate/test/health_screen_test.dart',
    '''    await tester.pumpAndSettle();

    await tester.tap(find.text('یادداشت').last);
''',
    '''    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('health-quick-log')),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('یادداشت').last);
''',
    'health quick note lazy test',
)
