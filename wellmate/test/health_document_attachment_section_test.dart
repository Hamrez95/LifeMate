import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:wellmate/screens/treatments/health_document_attachment_section.dart';

void main() {
  testWidgets('attachment composer is clear, removable and accessible in English', (
    tester,
  ) async {
    LifeMateRuntimeLocale.setLanguageCode('en');
    addTearDown(() => LifeMateRuntimeLocale.setLanguageCode('fa'));
    var attachments = <HealthDocumentAttachmentDraft>[
      HealthDocumentAttachmentDraft(
        bytes: Uint8List(900 * 1024),
        contentType: 'application/pdf',
        category: LifeMateHealthDocumentCategory.prescription,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: StatefulBuilder(
          builder: (context, setState) => Directionality(
            textDirection: TextDirection.ltr,
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: HealthDocumentAttachmentSection(
                  category: LifeMateHealthDocumentCategory.prescription,
                  attachments: attachments,
                  onChanged: (value) => setState(() => attachments = value),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Related documents and files'), findsOneWidget);
    expect(find.text('1/10'), findsOneWidget);
    expect(find.byTooltip('Remove file'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove file'));
    await tester.pump();

    expect(find.text('1/10'), findsNothing);
    expect(find.text('0/10'), findsOneWidget);
    expect(
      find.text('Images are reduced to 2048px before upload; file names are not saved.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('attachment composer keeps its Persian copy usable at large text', (
    tester,
  ) async {
    LifeMateRuntimeLocale.setLanguageCode('fa');
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.35),
            ),
            child: const Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(12),
                  child: HealthDocumentAttachmentSection(
                    category: LifeMateHealthDocumentCategory.visit,
                    attachments: [],
                    onChanged: _ignoreAttachments,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('مدارک و فایل‌های مرتبط'), findsOneWidget);
    expect(find.text('افزودن فایل'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _ignoreAttachments(List<HealthDocumentAttachmentDraft> _) {}
