import 'package:cocoonmate/app/cocoon_standalone_app.dart';
import 'package:cocoonmate_module/cocoonmate_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('standalone host mounts reusable Cocoon module', (tester) async {
    await tester.pumpWidget(const CocoonStandaloneApp());
    expect(find.byType(CocoonMateModule), findsOneWidget);
  });
}
