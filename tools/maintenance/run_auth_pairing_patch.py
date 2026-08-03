from pathlib import Path

source_path = Path('tools/maintenance/auth_pairing_patch.py')
source = source_path.read_text()
old = '''def replace_once(path: str, old: str, new: str, label: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one target in {path}, found {count}")
    file.write_text(text.replace(old, new, 1))
'''
new = '''def replace_once(path: str, old: str, new: str, label: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if label == "manual invitation shared accept" and count == 2:
        index = text.rfind(old)
        file.write_text(text[:index] + new + text[index + len(old):])
        return
    if count != 1:
        raise SystemExit(f"{label}: expected one target in {path}, found {count}")
    file.write_text(text.replace(old, new, 1))
'''
if source.count(old) != 1:
    raise SystemExit('Patch helper target was not found exactly once.')
exec(compile(source.replace(old, new, 1), str(source_path), 'exec'))
