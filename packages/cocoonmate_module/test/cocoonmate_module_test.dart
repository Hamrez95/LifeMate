import 'package:cocoonmate_module/cocoonmate_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeHost implements CocoonHostContract {
  FakeHost(this.entryState, this.locale);

  @override
  CocoonEntryState entryState;
  @override
  Locale locale;
  @override
  String? personId = 'synthetic-person';

  @override
  Future<void> beginPregnancySetup() async {}
  @override
  Future<void> openCommerce() async {}
  @override
  Future<void> openGlobalProfile() async {}
  @override
  Future<void> openLogin() async {}
  @override
  Future<void> refresh() async {}
  @override
  void recordSafeEvent(String name) {}
}

Widget appFor(FakeHost host) => MaterialApp(
      theme: CocoonTheme.light(),
      home: CocoonMateModule(config: CocoonModuleConfig(host: host)),
    );

void main() {
  testWidgets('module mounts under a host and uses Persian RTL',
      (tester) async {
    final host = FakeHost(CocoonEntryState.activePregnancy, const Locale('fa'));
    await tester.pumpWidget(appFor(host));

    expect(find.text('خانه'), findsNWidgets(2));
    final directionality = tester.widget<Directionality>(
      find
          .descendant(
            of: find.byType(CocoonMateModule),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
  });

  testWidgets('English LTR entitlement gate is deterministic', (tester) async {
    final host = FakeHost(CocoonEntryState.notEntitled, const Locale('en'));
    await tester.pumpWidget(appFor(host));

    expect(find.text('Choose access to CocoonMate'), findsOneWidget);
    expect(find.text('View options'), findsOneWidget);
  });

  testWidgets('large text does not require root navigator ownership',
      (tester) async {
    final host = FakeHost(CocoonEntryState.noPregnancy, const Locale('en'));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
        child: appFor(host),
      ),
    );
    expect(find.text('No active pregnancy yet'), findsOneWidget);
  });
}
