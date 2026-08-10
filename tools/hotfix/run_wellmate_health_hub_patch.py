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
