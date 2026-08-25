from pathlib import Path

p = Path('wellmate/lib/screens/treatments/care_event_form.dart')
s = p.read_text()

s = s.replace(
    "  String? _error;\n",
    "  String? _error;\n  List<LifeMateHistoryUsage> _historyUsages = const [];\n  bool _historyLoading = false;\n  bool _historyUnavailable = false;\n",
    1,
)
s = s.replace(
    "    _loadProfileTimeZone();\n",
    "    _title.addListener(_onHistoryQueryChanged);\n    _provider.addListener(_onHistoryQueryChanged);\n    _center.addListener(_onHistoryQueryChanged);\n    _loadProfileTimeZone();\n    _loadPersonalHistory();\n",
    1,
)
s = s.replace(
    "    _title.dispose();\n",
    "    _title.removeListener(_onHistoryQueryChanged);\n    _provider.removeListener(_onHistoryQueryChanged);\n    _center.removeListener(_onHistoryQueryChanged);\n    _title.dispose();\n",
    1,
)

anchor = "  Future<void> _loadProfileTimeZone() async {\n"
methods = '''  void _onHistoryQueryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPersonalHistory() async {
    if (_historyLoading) return;
    setState(() {
      _historyLoading = true;
      _historyUnavailable = false;
    });
    final usages = <LifeMateHistoryUsage>[];
    try {
      final api = context.read<LifeMateApiClient>();
      final now = DateTime.now();
      final eventsById = <String, Map<String, dynamic>>{};
      for (var window = 0; window < 6; window += 1) {
        final to = now.subtract(Duration(days: window * 30));
        final from = to.subtract(const Duration(days: 30));
        final events = await api.getCareEvents(fromDate: from, toDate: to);
        for (final event in events) {
          final id = event['id']?.toString() ?? event.toString();
          eventsById[id] = event;
        }
      }
      for (final event in eventsById.values) {
        final usedAt = DateTime.tryParse(event['updatedAtUtc']?.toString() ?? '') ??
            DateTime.tryParse(event['scheduledAtUtc']?.toString() ?? '') ??
            DateTime.tryParse(event['scheduledLocalDate']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final eventType = event['eventType']?.toString().toLowerCase();
        void add(LifeMateHistorySuggestionKind kind, dynamic raw, {String? context}) {
          final value = raw?.toString().trim() ?? '';
          if (value.isEmpty) return;
          usages.add(LifeMateHistoryUsage(
            kind: kind,
            value: value,
            usedAt: usedAt,
            context: context,
          ));
        }
        add(LifeMateHistorySuggestionKind.center, event['centerName']);
        if (eventType == 'appointment') {
          add(
            LifeMateHistorySuggestionKind.doctor,
            event['providerName'],
            context: event['specialty']?.toString(),
          );
          add(LifeMateHistorySuggestionKind.careAction, event['title']);
        } else if (eventType == 'injection') {
          add(
            LifeMateHistorySuggestionKind.injection,
            event['medicationName'] ?? event['title'],
            context: event['doseText']?.toString(),
          );
        }
      }
      final plans = await api.getTreatmentPlans();
      for (final plan in plans) {
        final medication = plan['medication'];
        if (medication is! Map) continue;
        final name = medication['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        usages.add(LifeMateHistoryUsage(
          kind: LifeMateHistorySuggestionKind.medication,
          value: name,
          usedAt: DateTime.tryParse(plan['updatedAtUtc']?.toString() ?? '') ??
              DateTime.tryParse(plan['startDate']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
          context: plan['doseText']?.toString(),
        ));
      }
      if (!mounted) return;
      setState(() => _historyUsages = List.unmodifiable(usages));
    } catch (error) {
      debugPrint('WellMate personal history suggestions unavailable: $error');
      if (mounted) setState(() => _historyUnavailable = true);
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  List<LifeMateHistorySuggestion> _historySuggestions(
    TextEditingController controller,
    LifeMateHistorySuggestionKind kind,
  ) => rankLifeMateHistorySuggestions(
    history: _historyUsages,
    query: controller.text,
    kind: kind,
  );

'''
assert anchor in s
s = s.replace(anchor, methods + anchor, 1)

s = s.replace(
    "                          icon: Icons.event_note_rounded,\n                          required: true,\n",
    "                          icon: Icons.event_note_rounded,\n                          required: true,\n                          historyKind: _isAppointment\n                              ? LifeMateHistorySuggestionKind.careAction\n                              : LifeMateHistorySuggestionKind.injection,\n",
    1,
)
s = s.replace(
    "                            icon: Icons.person_rounded,\n                            required: true,\n",
    "                            icon: Icons.person_rounded,\n                            required: true,\n                            historyKind: LifeMateHistorySuggestionKind.doctor,\n",
    1,
)
target = "                icon: Icons.local_hospital_rounded,\n              ),\n"
assert target in s
s = s.replace(
    target,
    "                icon: Icons.local_hospital_rounded,\n                historyKind: LifeMateHistorySuggestionKind.center,\n              ),\n",
    1,
)

old_sig = "    TextInputType? keyboardType,\n    TextDirection? textDirection,\n  }) {\n"
new_sig = "    TextInputType? keyboardType,\n    TextDirection? textDirection,\n    LifeMateHistorySuggestionKind? historyKind,\n  }) {\n"
assert old_sig in s
s = s.replace(old_sig, new_sig, 1)

old_child = '''      child: TextFormField(
        controller: controller,
        enabled: !_busy,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: const [LifeMateLocaleDigitInputFormatter()],
        textDirection: textDirection,
        decoration: wellMateFieldDecoration(hint: hint),
        validator: required
            ? (value) => value == null || value.trim().isEmpty
                  ? LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: '$label را وارد کنید.',
                        en: "Enter $label.",
                      ),
                      en: "Enter $label.",
                    )
                  : null
            : null,
      ),
'''
new_child = '''      child: Builder(
        builder: (context) {
          final suggestions = historyKind == null
              ? const <LifeMateHistorySuggestion>[]
              : _historySuggestions(controller, historyKind);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: controller,
                enabled: !_busy,
                maxLines: maxLines,
                keyboardType: keyboardType,
                inputFormatters: const [LifeMateLocaleDigitInputFormatter()],
                textDirection: textDirection,
                decoration: wellMateFieldDecoration(hint: hint),
                validator: required
                    ? (value) => value == null || value.trim().isEmpty
                          ? LifeMateRuntimeLocale.select(
                              fa: '$label را وارد کنید.',
                              en: 'Enter $label.',
                            )
                          : null
                    : null,
              ),
              if (historyKind != null && _historyLoading) ...[
                SizedBox(height: 6),
                LinearProgressIndicator(minHeight: 2),
              ] else if (suggestions.isNotEmpty) ...[
                SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final suggestion in suggestions)
                      ActionChip(
                        key: ValueKey(
                          'history-suggestion-${historyKind.name}-${suggestion.value}',
                        ),
                        label: Text(
                          '${suggestion.value} · ${suggestion.usageCount}×',
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: _busy
                            ? null
                            : () {
                                controller.value = TextEditingValue(
                                  text: suggestion.value,
                                  selection: TextSelection.collapsed(
                                    offset: suggestion.value.length,
                                  ),
                                );
                              },
                      ),
                  ],
                ),
              ] else if (historyKind != null &&
                  _historyUnavailable &&
                  normalizeLifeMateHistoryText(controller.text).length >= 2) ...[
                SizedBox(height: 6),
                Text(
                  LifeMateRuntimeLocale.select(
                    fa: 'پیشنهادهای سوابق فعلاً در دسترس نیست؛ می‌توانید آزادانه تایپ کنید.',
                    en: 'History suggestions are unavailable; you can keep typing freely.',
                  ),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          );
        },
      ),
'''
assert old_child in s
s = s.replace(old_child, new_child, 1)
p.write_text(s)
