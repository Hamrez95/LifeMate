from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    if old not in text:
        if new in text:
            return
        raise SystemExit(f"Expected snippet not found in {path}")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


path = "wellmate/lib/screens/profile/profile_screen.dart"
wrong_method = '''  Future<void> _openEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const EditableProfileScreen()),
    );
    if (!mounted) return;
    setState(() {
      _currentUser = context.read<LifeMateApiClient>().getCurrentUser();
    });
  }

'''

# The materialization patch originally used a generic build-method anchor. Remove
# the method if it landed in the top-level StatelessWidget and then add it to the
# state object that owns `_currentUser`.
target = ROOT / path
text = target.read_text(encoding="utf-8")
profile_class = text.find("class ProfileScreen extends StatelessWidget")
identity_class = text.find("class _CurrentUserIdentity extends StatefulWidget")
wrong_index = text.find(wrong_method)
if wrong_index >= 0 and profile_class <= wrong_index < identity_class:
    text = text[:wrong_index] + text[wrong_index + len(wrong_method):]
    target.write_text(text, encoding="utf-8")

replace_once(
    path,
    '''  @override
  void initState() {
    super.initState();
    _currentUser = context.read<LifeMateApiClient>().getCurrentUser();
  }

  @override
  Widget build(BuildContext context) {
''',
    '''  @override
  void initState() {
    super.initState();
    _currentUser = context.read<LifeMateApiClient>().getCurrentUser();
  }

  Future<void> _openEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const EditableProfileScreen()),
    );
    if (!mounted) return;
    setState(() {
      _currentUser = context.read<LifeMateApiClient>().getCurrentUser();
    });
  }

  @override
  Widget build(BuildContext context) {
''',
)
