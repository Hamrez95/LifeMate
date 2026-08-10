from pathlib import Path

path = Path('tools/hotfix/apply_wellmate_health_hub.py')
source = path.read_text(encoding='utf-8')
old = '''value = replace_once(value, "              index: 4,\\n", "              index: 5,\\n", "home nav index")'''
new = '''value = replace_once(
    value,
    "            _buildNavItem(\\n              icon: Icons.home_rounded,\\n              label: loc['nav_home'],\\n              index: 4,\\n              fontFamily: fontFamily,\\n            ),\\n",
    "            _buildNavItem(\\n              icon: Icons.home_rounded,\\n              label: loc['nav_home'],\\n              index: 5,\\n              fontFamily: fontFamily,\\n            ),\\n",
    "home nav index",
)'''
if old not in source:
    raise RuntimeError('Expected bottom-nav patch line was not found.')
source = source.replace(old, new, 1)
exec(compile(source, str(path), 'exec'))
