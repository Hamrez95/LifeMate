from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

path = ROOT / 'wellmate/lib/screens/women_calendar/women_calendar_screen.dart'
text = path.read_text(encoding='utf-8')
text = text.replace('_dateKey(', '_episodeDateKey(')
marker = '  void _replaceEpisodeLocally(\n'
helper = """  String _episodeDateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

"""
if helper not in text:
    if marker not in text:
        raise SystemExit('episode local helper marker missing')
    text = text.replace(marker, helper + marker, 1)
path.write_text(text, encoding='utf-8')
