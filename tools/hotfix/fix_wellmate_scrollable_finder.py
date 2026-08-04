from pathlib import Path

path = Path(__file__).resolve().parents[2] / "wellmate/test/add_treatment_accessibility_test.dart"
text = path.read_text(encoding="utf-8")
expected = "scrollable: scrollable,"
if text.count(expected) != 2:
    raise RuntimeError("Expected exactly two treatment test scrollable arguments")
path.write_text(text.replace(expected, "scrollable: scrollable.first,"), encoding="utf-8")
print("WellMate treatment accessibility test uses the form's first scrollable.")
