from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Expected block not found in {path}: {old[:120]!r}")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.write_text(content.rstrip() + "\n", encoding="utf-8")


# Keep section headings within a 320px screen at large text scale.
replace(
    "wellmate/lib/screens/treatments/add_treatment_screen.dart",
    """          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppColors.darkBlue,
                ),
              ),
            ],
          ),""",
    """          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.darkBlue,
                  ),
                ),
              ),
            ],
          ),""",
)

write(
    "wellmate/test/add_treatment_accessibility_test.dart",
    r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/screens/treatments/add_treatment_screen.dart';

void main() {
  testWidgets(
    'single-page treatment form remains scrollable above bottom navigation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        Provider<LifeMateApiClient>.value(
          value: _ProfileTimeZoneApiClient(),
          child: MaterialApp(
            locale: const Locale('fa'),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.45),
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Scaffold(
                    body: TabbedAddTreatmentScreen(onCreated: () {}),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final form = find.byKey(
        const ValueKey('wellmate-treatment-single-page-form'),
      );
      expect(form, findsOneWidget);
      expect(find.text('افزودن درمان'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final scrollable = find.descendant(
        of: form,
        matching: find.byType(Scrollable),
        skipOffstage: false,
      );
      final addTime = find.byKey(
        const Key('add-treatment-time'),
        skipOffstage: false,
      );
      await tester.scrollUntilVisible(
        addTime,
        240,
        scrollable: scrollable,
      );
      expect(addTime, findsOneWidget);
      expect(find.text('منطقه زمانی', skipOffstage: false), findsOneWidget);
      expect(find.text('Europe/Berlin', skipOffstage: false), findsOneWidget);

      final submit = find.byKey(
        const Key('submit-treatment'),
        skipOffstage: false,
      );
      await tester.scrollUntilVisible(
        submit,
        260,
        scrollable: scrollable,
      );
      expect(submit, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _ProfileTimeZoneApiClient extends LifeMateApiClient {
  _ProfileTimeZoneApiClient()
      : super(
          baseUri: Uri.parse('https://example.invalid'),
          accessToken: () => 'test-token',
        );

  @override
  Future<Map<String, dynamic>> getCurrentUser() async => {
        'user': {'id': 'patient-1', 'email': 'patient@example.com'},
        'profile': {
          'displayName': 'بیمار تست',
          'locale': 'fa',
          'timeZone': 'Europe/Berlin',
        },
      };
}
''',
)

replace(
    "wellmate/test/ui_regression_test.dart",
    """  testWidgets('add treatment retains medicine schedule and review tabs',
      (WidgetTester tester) async {
    final api = _FakeWellMateApiClient();

    await tester.pumpWidget(
      Provider<LifeMateApiClient>.value(
        value: api,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: TabbedAddTreatmentScreen(onCreated: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('دارو'), findsOneWidget);
    expect(find.text('برنامه'), findsOneWidget);
    expect(find.text('مرور'), findsOneWidget);
    expect(find.text('افزودن دارو و برنامه درمان'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });""",
    """  testWidgets('add treatment uses one scrollable form without inner tabs',
      (WidgetTester tester) async {
    final api = _FakeWellMateApiClient();

    await tester.pumpWidget(
      Provider<LifeMateApiClient>.value(
        value: api,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: TabbedAddTreatmentScreen(onCreated: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('wellmate-treatment-single-page-form')),
      findsOneWidget,
    );
    expect(find.text('افزودن درمان'), findsOneWidget);
    expect(find.text('همه اطلاعات دارو و برنامه مصرف را در همین صفحه وارد کنید.'),
        findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    expect(tester.takeException(), isNull);
  });""",
)

replace(
    "wellmate/test/care_plan_hub_accessibility_test.dart",
    "      expect(find.text('افزودن دارو و برنامه درمان'), findsOneWidget);",
    "      expect(find.text('افزودن درمان'), findsOneWidget);",
)

print("WellMate feedback hotfix small-screen and regression fixes prepared.")
