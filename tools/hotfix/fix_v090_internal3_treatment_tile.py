from pathlib import Path

path = Path('wellmate/lib/screens/treatments/treatments_screen.dart')
text = path.read_text(encoding='utf-8')
old = '''                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          plan['status'] == 'active' ? 'فعال' : 'متوقف',
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 18),
                    ],
                  ),'''
new = '''                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          plan['status'] == 'active' ? 'فعال' : 'متوقف',
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded, size: 18),
                    ],
                  ),'''
if old in text:
    path.write_text(text.replace(old, new, 1), encoding='utf-8')
elif new not in text:
    raise RuntimeError('Expected WellMate treatment ListTile trailing block was not found')
print('Treatment tile overflow fix applied.')
