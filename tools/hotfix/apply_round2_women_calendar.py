from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding='utf-8')


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{path}: expected one match, found {count}: {old[:100]!r}')
    write(path, text.replace(old, new, 1))


def regex_once(path: str, pattern: str, replacement: str, flags=0) -> None:
    text = read(path)
    updated, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise RuntimeError(f'{path}: regex expected one match, found {count}: {pattern[:100]!r}')
    write(path, updated)


# ---------------------------------------------------------------------------
# Women month calendar: explicit selected-day model and interaction.
# ---------------------------------------------------------------------------
path = 'wellmate/lib/screens/women_calendar/women_calendar_month_card.dart'
replace_once(
    path,
    "    this.initialFocusedDate,\n  });\n\n  final List<Map<String, dynamic>> episodes;\n  final WomenCalendarEstimate? estimate;\n  final DateTime? initialFocusedDate;",
    "    this.initialFocusedDate,\n    this.selectedDate,\n    this.onDateSelected,\n  });\n\n  final List<Map<String, dynamic>> episodes;\n  final WomenCalendarEstimate? estimate;\n  final DateTime? initialFocusedDate;\n  final DateTime? selectedDate;\n  final ValueChanged<DateTime>? onDateSelected;",
)
replace_once(
    path,
    "              final isToday = _sameDay(date, DateTime.now());\n              final dayNumber = isPersian",
    "              final isToday = _sameDay(date, DateTime.now());\n              final isSelected = widget.selectedDate != null &&\n                  _sameDay(date, widget.selectedDate!);\n              final dayNumber = isPersian",
)
old_block = r'''              return Semantics(
                label: [
                  formatAppDate(context, date),
                  if (statusLabel.isNotEmpty) statusLabel,
                ].join('، '),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isToday ? const Color(0xFF20B98A) : Colors.white,
                      width: isToday ? 1.8 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        localizeDigits(context, dayNumber),
                        maxLines: 1,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _DayPhaseMarker(
                        phase: phase,
                        actualBleeding: actualBleeding,
                      ),
                    ],
                  ),
                ),
              );'''
new_block = r'''              return Semantics(
                button: widget.onDateSelected != null,
                selected: isSelected,
                label: [
                  formatAppDate(context, date),
                  if (isToday) isPersian ? 'امروز' : 'Today',
                  if (isSelected) isPersian ? 'انتخاب‌شده' : 'Selected',
                  if (statusLabel.isNotEmpty) statusLabel,
                ].join('، '),
                child: InkWell(
                  key: ValueKey('women-calendar-day-${date.year}-${date.month}-${date.day}'),
                  onTap: widget.onDateSelected == null
                      ? null
                      : () => widget.onDateSelected!(date),
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedScale(
                    scale: isSelected ? 1.07 : 1,
                    duration: const Duration(milliseconds: 170),
                    curve: Curves.easeOutCubic,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 190),
                      decoration: BoxDecoration(
                        color: background,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF9B68C7)
                              : isToday
                                  ? const Color(0xFF20B98A)
                                  : Colors.white,
                          width: isSelected ? 2.4 : isToday ? 1.8 : 1,
                        ),
                        boxShadow: isSelected
                            ? const [
                                BoxShadow(
                                  color: Color(0x249B68C7),
                                  blurRadius: 10,
                                  offset: Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            localizeDigits(context, dayNumber),
                            maxLines: 1,
                            style: TextStyle(
                              color: foreground,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _DayPhaseMarker(
                            phase: phase,
                            actualBleeding: actualBleeding,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );'''
replace_once(path, old_block, new_block)

# ---------------------------------------------------------------------------
# Companion dashboard: same canonical editor for today and selected dates.
# ---------------------------------------------------------------------------
path = 'wellmate/lib/screens/women_calendar/women_companion_screen.dart'
replace_once(
    path,
    "  List<Map<String, dynamic>> _relationships = const [];\n\n  bool get _enabled",
    "  List<Map<String, dynamic>> _relationships = const [];\n  DateTime _selectedDate = DateTime.now();\n\n  bool get _enabled",
)
replace_once(
    path,
    r'''  Map<String, dynamic>? get _todayLog {
    final today = _dateKey(DateTime.now());
    for (final log in _dailyLogs) {
      if (log['loggedOn']?.toString() == today) return log;
    }
    return null;
  }
''',
    r'''  Map<String, dynamic>? get _todayLog => _logForDate(DateTime.now());

  Map<String, dynamic>? _logForDate(DateTime date) {
    final key = _dateKey(date);
    for (final log in _dailyLogs) {
      if (log['loggedOn']?.toString() == key) return log;
    }
    return null;
  }

  bool _isRecordedBleedingDay(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    for (final episode in _episodes) {
      final start = DateTime.tryParse(episode['startedOn']?.toString() ?? '');
      if (start == null) continue;
      final parsedEnd = DateTime.tryParse(episode['endedOn']?.toString() ?? '');
      final startOnly = DateTime(start.year, start.month, start.day);
      final endValue = parsedEnd ?? todayOnly;
      final endOnly = DateTime(endValue.year, endValue.month, endValue.day);
      if (!day.isBefore(startOnly) && !day.isAfter(endOnly)) return true;
    }
    return false;
  }
''',
)
replace_once(
    path,
    "            title: const Text('تقویم و تنظیمات چرخه'),",
    "            title: const Text('تنظیمات و مدیریت ثبت‌ها'),",
)
regex_once(
    path,
    r"  Future<void> _editTodayLog\(\) async \{.*?\n  \}\n\n  @override\n  Widget build",
    r'''  Future<void> _editDailyLog(DateTime date) async {
    final current = _logForDate(date);
    final draft = await showModalBottomSheet<WomenDailyLogDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DailyCheckInSheet(existing: current),
    );
    if (draft == null || _saving) return;
    setState(() => _saving = true);
    try {
      await _companionApi.saveDailyLog(
        version: current?['version'] is int ? current!['version'] as int : 0,
        loggedOn: date,
        mood: draft.mood,
        energyLevel: draft.energyLevel,
        painLevel: draft.painLevel,
        symptoms: draft.symptoms,
        privateNotes: draft.privateNotes,
        shareSummaryWithCompanion: draft.shareWithCompanion,
      );
      if (!mounted) return;
      final isToday = _dateKey(date) == _dateKey(DateTime.now());
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: isToday ? 'حال امروز ثبت شد' : 'ثبت روز ذخیره شد',
        message: draft.shareWithCompanion
            ? 'فقط خلاصه‌ای که اجازه داده‌ای با همدمت به اشتراک گذاشته می‌شود.'
            : 'این ثبت به‌صورت خصوصی ذخیره شد.',
      );
      await _load();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.error,
        title: 'ثبت انجام نشد',
        message: error.code == 'stale_women_calendar_daily_log'
            ? 'این روز تغییر کرده بود؛ اطلاعات تازه شد و می‌توانی دوباره ویرایش کنی.'
            : 'اطلاعات این روز ذخیره نشد. دوباره تلاش کن.',
      );
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build''',
    flags=re.S,
)
replace_once(
    path,
    "              onEdit: _editTodayLog,",
    "              onEdit: () => _editDailyLog(DateTime.now()),",
)
replace_once(
    path,
    "            WomenCalendarMonthCard(episodes: _episodes, estimate: estimate),\n            const SizedBox(height: 14),\n            _FourteenDayStrip(estimate: estimate),",
    "            WomenCalendarMonthCard(\n              episodes: _episodes,\n              estimate: estimate,\n              selectedDate: _selectedDate,\n              onDateSelected: (date) => setState(() => _selectedDate = date),\n            ),\n            const SizedBox(height: 10),\n            _SelectedDaySummaryCard(\n              date: _selectedDate,\n              log: _logForDate(_selectedDate),\n              estimate: estimate,\n              recordedBleeding: _isRecordedBleedingDay(_selectedDate),\n              saving: _saving,\n              onEdit: () => _editDailyLog(_selectedDate),\n            ),\n            const SizedBox(height: 14),\n            _FourteenDayStrip(estimate: estimate),",
)

selected_card = r'''
class _SelectedDaySummaryCard extends StatelessWidget {
  const _SelectedDaySummaryCard({
    required this.date,
    required this.log,
    required this.estimate,
    required this.recordedBleeding,
    required this.saving,
    required this.onEdit,
  });

  final DateTime date;
  final Map<String, dynamic>? log;
  final WomenCalendarEstimate? estimate;
  final bool recordedBleeding;
  final bool saving;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final phase = estimate?.phaseForDate(date);
    final phaseValue = phaseVisual(phase);
    final mood = moodVisual(log?['mood']?.toString());
    final symptoms = (log?['symptoms'] as List<dynamic>? ?? const [])
        .map((item) => _selectedDaySymptomLabel(item.toString()))
        .toList(growable: false);
    return _PastelCard(
      key: const ValueKey('women-calendar-selected-day-summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatAppDate(context, date, includeWeekday: true),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      recordedBleeding
                          ? 'پریود ثبت‌شده'
                          : '${phaseValue.label} • تخمینی',
                      style: TextStyle(
                        color: recordedBleeding
                            ? const Color(0xFFD64A70)
                            : phaseValue.foreground,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                recordedBleeding ? Icons.water_drop_rounded : phaseValue.icon,
                color: recordedBleeding ? const Color(0xFFF15D7B) : phaseValue.color,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (log == null) ...[
            const Text(
              'برای این روز چیزی ثبت نشده',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey('women-calendar-selected-day-create'),
              onPressed: saving ? null : onEdit,
              icon: const Icon(Icons.add_rounded),
              label: const Text('ثبت حال این روز'),
            ),
          ] else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DayFact(icon: Icons.mood_rounded, label: 'حال', value: '${mood.emoji} ${mood.label}'),
                _DayFact(
                  icon: Icons.bolt_rounded,
                  label: 'انرژی',
                  value: '${localizeDigits(context, log!['energyLevel'] ?? '—')}/۵',
                ),
                _DayFact(
                  icon: Icons.monitor_heart_outlined,
                  label: 'درد',
                  value: '${localizeDigits(context, log!['painLevel'] ?? '—')}/۵',
                ),
                _DayFact(
                  icon: Icons.water_drop_outlined,
                  label: 'خونریزی',
                  value: recordedBleeding ? 'ثبت‌شده' : 'ثبت نشده',
                ),
              ],
            ),
            if (symptoms.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'نشانه‌ها: ${symptoms.join('، ')}',
                style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
              ),
            ],
            const SizedBox(height: 10),
            TextButton.icon(
              key: const ValueKey('women-calendar-selected-day-edit'),
              onPressed: saving ? null : onEdit,
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('ویرایش ثبت روز'),
            ),
          ],
        ],
      ),
    );
  }
}

class _DayFact extends StatelessWidget {
  const _DayFact({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: const Color(0xFF8A66A6)),
            const SizedBox(width: 5),
            Text('$label: ', style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
            Text(value, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
          ],
        ),
      );
}

String _selectedDaySymptomLabel(String raw) {
  return switch (raw.trim().toLowerCase()) {
    'cramps' => 'گرفتگی',
    'headache' => 'سردرد',
    'bloating' => 'نفخ',
    'fatigue' => 'خستگی',
    'breast_tenderness' || 'breasttenderness' => 'حساسیت سینه',
    'back_pain' || 'backpain' => 'کمردرد',
    'sleep_change' || 'sleepchange' => 'تغییر خواب',
    'appetite_change' || 'appetitechange' => 'تغییر اشتها',
    'no_symptom' || 'nosymptom' => 'بدون نشانه',
    _ => raw,
  };
}
'''
replace_once(path, "class _FourteenDayStrip extends StatelessWidget {", selected_card + "\nclass _FourteenDayStrip extends StatelessWidget {")

# ---------------------------------------------------------------------------
# Settings screen becomes configuration/history only. Remove daily editor state.
# ---------------------------------------------------------------------------
path = 'wellmate/lib/screens/women_calendar/women_calendar_screen.dart'
replace_once(path, "  final _dailyNoteController = TextEditingController();\n  final _monthKey = GlobalKey();\n\n", "")
replace_once(
    path,
    "  String _mood = 'neutral';\n  int _energy = 3;\n  Set<String> _symptoms = <String>{};\n  String _supportNeed = 'none';\n  bool _shareSummary = false;\n\n",
    "",
)
regex_once(
    path,
    r"\n  @override\n  void dispose\(\) \{\n    _dailyNoteController\.dispose\(\);\n    super\.dispose\(\);\n  \}\n",
    "\n",
)
regex_once(
    path,
    r"\n    final daily = profile\['dailyCheckIn'\] as Map<String, dynamic>\?;.*?\n    \}\n  \}\n\n  Future<void> _openSubscription",
    "\n  }\n\n  Future<void> _openSubscription",
    flags=re.S,
)
regex_once(
    path,
    r"\n  Future<void> _saveDailyCheckIn\(\) async \{.*?\n  \}\n\n  Future<void> _createEpisode",
    "\n  Future<void> _createEpisode",
    flags=re.S,
)
regex_once(
    path,
    r"\n  void _scrollToMonth\(\) \{.*?\n  \}\n\n  @override",
    "\n  @override",
    flags=re.S,
)
replace_once(
    path,
    "            'با فعال‌سازی تقویم بانوان، چرخه، حال روزانه و گزارش‌های خصوصی در WellMate نمایش داده می‌شوند.',",
    "            'با فعال‌سازی تقویم بانوان، تنظیمات چرخه و مدیریت ثبت‌های دوره در دسترس قرار می‌گیرد.',",
)
regex_once(
    path,
    r"    final estimate = _estimate;\n    return WomenCycleBackground\(.*?\n    \);\n  \}\n\n  static DateTime _dateOnly",
    r'''    final estimate = _estimate;
    return WomenCycleBackground(
      child: RefreshIndicator(
        onRefresh: _load,
        color: womenRose,
        child: ListView(
          key: const ValueKey('women-calendar-settings-only'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
          children: [
            const WomenSoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تنظیمات و مدیریت ثبت‌ها',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: womenInk),
                  ),
                  SizedBox(height: 7),
                  Text(
                    'اینجا فقط تنظیمات ماندگار چرخه، یادآوری‌ها و تاریخچه دوره‌ها مدیریت می‌شود. حال روزانه از خود تقویم ثبت می‌شود.',
                    style: TextStyle(color: AppColors.textSecondary, height: 1.65),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            WomenCycleSettingsCard(
              lastPeriodStart: _lastPeriodStart,
              cycleLength: _cycleLength,
              periodLength: _periodLength,
              remindersEnabled: _remindersEnabled,
              saving: _saving,
              onPickDate: _pickStartDate,
              onCycleChanged: (value) => setState(() => _cycleLength = value),
              onPeriodChanged: (value) => setState(() => _periodLength = value),
              onReminderChanged: (value) => setState(() => _remindersEnabled = value),
              onSave: _saveSettings,
            ),
            const SizedBox(height: 14),
            WomenRemindersCard(
              estimate: estimate,
              remindersEnabled: _remindersEnabled,
              activeTreatmentCount: _activeTreatmentCount,
            ),
            const SizedBox(height: 14),
            WomenPeriodHistoryCard(
              episodes: _episodes,
              hasOpenEpisode: _openEpisode != null,
              saving: _saving,
              onStart: _createEpisode,
              onFinish: _finishPeriodToday,
              onEdit: _editEpisode,
            ),
            const SizedBox(height: 14),
            const WomenPrivacyNotice(),
          ],
        ),
      ),
    );
  }

  static DateTime _dateOnly''',
    flags=re.S,
)
# remove no-longer-needed helpers that were daily-check-in only
regex_once(path, r"\n  static bool _sameDay\(.*?\n      left\.day == right\.day;\n", "\n", flags=re.S)
regex_once(path, r"\n  static String _dateString\(.*?\n      '\$\{value\.day.*?;\n", "\n", flags=re.S)

# Replace all remaining settings CRUD SnackBars with the shared notice. Keep the
# user-visible semantics but use the new shared feedback system.
text = read(path)
text = text.replace(
    "      ScaffoldMessenger.of(context).showSnackBar(\n        const SnackBar(\n          content: Text('تنظیمات چرخه ذخیره شد.'),\n          behavior: SnackBarBehavior.floating,\n        ),\n      );",
    "      LifeMateNotice.show(context, type: LifeMateNoticeType.success, title: 'تنظیمات ذخیره شد', message: 'تنظیمات چرخه به‌روزرسانی شد.');",
)
text = re.sub(
    r"      ScaffoldMessenger\.of\(context\)\.showSnackBar\(\n        SnackBar\(\n          content: Text\(\n            error\.code == 'stale_women_calendar_profile'\n                \? 'اطلاعات تغییر کرده بود؛ صفحه تازه‌سازی شد\.'\n                : 'ذخیره تنظیمات انجام نشد\.',\n          \),\n          behavior: SnackBarBehavior\.floating,\n        \),\n      \);",
    "      LifeMateNotice.show(context, type: LifeMateNoticeType.error, title: 'ذخیره انجام نشد', message: error.code == 'stale_women_calendar_profile' ? 'اطلاعات تغییر کرده بود؛ صفحه تازه‌سازی شد.' : 'تنظیمات ذخیره نشد.');",
    text,
)
for old, new in [
    ("      ScaffoldMessenger.of(context).showSnackBar(\n        const SnackBar(\n          content: Text('دوره و یادداشت خصوصی ثبت شد.'),\n          behavior: SnackBarBehavior.floating,\n        ),\n      );", "      LifeMateNotice.show(context, type: LifeMateNoticeType.success, title: 'دوره ثبت شد', message: 'بازه دوره و یادداشت خصوصی ذخیره شد.');"),
    ("      ScaffoldMessenger.of(context).showSnackBar(\n        const SnackBar(\n          content: Text('پایان دوره برای امروز ثبت شد.'),\n          behavior: SnackBarBehavior.floating,\n        ),\n      );", "      LifeMateNotice.show(context, type: LifeMateNoticeType.success, title: 'پایان دوره ثبت شد', message: 'پایان دوره برای امروز ذخیره شد.');"),
    ("      ScaffoldMessenger.of(context).showSnackBar(\n        const SnackBar(\n          content: Text('ثبت دوره اصلاح شد.'),\n          behavior: SnackBarBehavior.floating,\n        ),\n      );", "      LifeMateNotice.show(context, type: LifeMateNoticeType.success, title: 'ثبت دوره اصلاح شد', message: 'تغییرات تاریخچه دوره ذخیره شد.');"),
]:
    text = text.replace(old, new)
# Error snackbars with conditional messages, for create/edit episode.
text = re.sub(
    r"      ScaffoldMessenger\.of\(context\)\.showSnackBar\(\n        SnackBar\(\n          content: Text\(\n            error\.code == 'women_calendar_episode_overlap'\n                \? 'این بازه با یک ثبت قبلی هم‌پوشانی دارد\.'\n                : '(?:ثبت دوره انجام نشد|اصلاح ثبت انجام نشد)\.',\n          \),\n          behavior: SnackBarBehavior\.floating,\n        \),\n      \);",
    "      LifeMateNotice.show(context, type: LifeMateNoticeType.error, title: 'ثبت دوره انجام نشد', message: error.code == 'women_calendar_episode_overlap' ? 'این بازه با یک ثبت قبلی هم‌پوشانی دارد.' : 'تغییرات ثبت دوره ذخیره نشد.');",
    text,
)
write(path, text)

# ---------------------------------------------------------------------------
# Client API: remove the deprecated profile-embedded daily check-in surface.
# ---------------------------------------------------------------------------
path = 'packages/lifemate_client/lib/src/lifemate_api_client.dart'
replace_once(
    path,
    "    required bool remindersEnabled,\n    Map<String, dynamic>? dailyCheckIn,\n    bool includeDailyCheckIn = false,\n  }) async => _asObject(",
    "    required bool remindersEnabled,\n  }) async => _asObject(",
)
replace_once(path, "        'remindersEnabled': remindersEnabled,\n        if (includeDailyCheckIn) 'dailyCheckIn': dailyCheckIn,\n", "        'remindersEnabled': remindersEnabled,\n")

# ---------------------------------------------------------------------------
# Backend: canonical daily-log endpoint is the only active daily state writer.
# Historical profile columns remain only for safe migration/backward storage.
# ---------------------------------------------------------------------------
path = 'supabase/functions/lifemate-api/women_calendar.ts'
replace_once(
    path,
    "    const expectedVersion = nonNegativeInt(body.version, \"version\");\n    const hasDailyCheckIn = Object.prototype.hasOwnProperty.call(\n      body,\n      \"dailyCheckIn\",\n    );",
    "    const expectedVersion = nonNegativeInt(body.version, \"version\");\n    assertCanonicalWomenDailyLogPayload(body);\n    const hasDailyCheckIn = false;",
)
replace_once(
    path,
    "    const requestedDailyCheckIn = hasDailyCheckIn\n      ? parseDailyCheckIn(body.dailyCheckIn)\n      : undefined;",
    "    const requestedDailyCheckIn: DailyCheckIn | undefined = undefined;",
)
replace_once(path, "    dailyCheckIn: dailyCheckInFromRow(row),", "    dailyCheckIn: null,")
old_summary = r'''    const profile = mapProfile(profiles[0]);
    const dailyCheckIn = profile.dailyCheckIn as Record<string, unknown> | null;
    const sharedDailySummary = dailyCheckIn?.shareSummary === true
      ? {
        date: dailyCheckIn.date,
        mood: dailyCheckIn.mood,
        energy: dailyCheckIn.energy,
        supportNeed: dailyCheckIn.supportNeed,
      }
      : null;
    const patientProfile = patientProfiles[0];'''
new_summary = r'''    const profile = mapProfile(profiles[0]);
    const canonicalSharedLog = sharedLogs[0]
      ? mapDailyLogCompanion(sharedLogs[0])
      : null;
    const sharedDailySummary = canonicalSharedLog == null
      ? null
      : {
          date: canonicalSharedLog.loggedOn,
          mood: canonicalSharedLog.mood,
          energy: canonicalSharedLog.energyLevel,
          pain: canonicalSharedLog.painLevel,
          symptoms: canonicalSharedLog.symptoms,
        };
    const patientProfile = patientProfiles[0];'''
replace_once(path, old_summary, new_summary)
replace_once(
    path,
    "      latestSharedDailyLog: sharedLogs[0]\n        ? mapDailyLogCompanion(sharedLogs[0])\n        : null,",
    "      latestSharedDailyLog: canonicalSharedLog,",
)
# Add exported guard just before estimate export so it can be regression tested without DB.
replace_once(
    path,
    "export function calculateWomenCalendarEstimate(",
    r'''export function assertCanonicalWomenDailyLogPayload(
  body: Record<string, unknown>,
): void {
  if (Object.prototype.hasOwnProperty.call(body, "dailyCheckIn")) {
    throw new ApiError(
      400,
      "women_calendar_daily_log_endpoint_required",
      "Daily wellbeing state must use /api/v1/women-calendar/daily-logs.",
    );
  }
}

export function calculateWomenCalendarEstimate(''',
)

# Safe additive backfill. No legacy columns are dropped and existing canonical
# logs win on conflict.
write(
    'supabase/migrations/20260808113000_canonicalize_women_daily_logs.sql',
    r'''-- Preserve legacy profile-embedded daily state by copying it into the
-- canonical per-day log table. This is additive and idempotent; no legacy
-- column is removed in this release.
insert into lifemate.women_calendar_daily_logs (
    id, owner_user_id, logged_on, mood, energy_level, pain_level, symptoms,
    private_notes, share_summary_with_companion, version,
    created_at_utc, updated_at_utc
)
select
    gen_random_uuid(),
    p.owner_user_id,
    p.daily_check_in_date,
    coalesce(p.daily_mood, 'Neutral'),
    coalesce(p.daily_energy, 3),
    0,
    coalesce((
        select array_agg(mapped)::character varying(32)[]
        from (
            select distinct case lower(trim(value))
                when 'cramps' then 'Cramps'
                when 'headache' then 'Headache'
                when 'bloating' then 'Bloating'
                when 'fatigue' then 'Fatigue'
                when 'breast_tenderness' then 'BreastTenderness'
                when 'breasttenderness' then 'BreastTenderness'
                when 'back_pain' then 'BackPain'
                when 'backpain' then 'BackPain'
                when 'sleep_change' then 'SleepChange'
                when 'sleepchange' then 'SleepChange'
                when 'appetite_change' then 'AppetiteChange'
                when 'appetitechange' then 'AppetiteChange'
                when 'no_symptom' then 'NoSymptom'
                when 'nosymptom' then 'NoSymptom'
                else null
            end as mapped
            from unnest(p.daily_symptoms) value
        ) normalized
        where mapped is not null
    ), '{}'::character varying(32)[]),
    p.daily_private_note,
    p.share_daily_summary,
    1,
    coalesce(p.created_at_utc, now()),
    coalesce(p.updated_at_utc, now())
from lifemate.women_calendar_profiles p
where p.daily_check_in_date is not null
  and p.daily_mood is not null
on conflict (owner_user_id, logged_on) do nothing;

comment on column lifemate.women_calendar_profiles.daily_check_in_date is
'Legacy compatibility column. New daily wellbeing writes use women_calendar_daily_logs only.';
''',
)

# Reframe API regression tests around canonical daily logs.
write(
    'packages/lifemate_client/test/women_calendar_daily_checkin_api_test.dart',
    r'''import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('daily wellbeing uses only the canonical daily-log endpoint', () async {
    late http.Request observed;
    final api = WomenCompanionApi(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'id': 'log-1',
            'loggedOn': '2026-08-05',
            'mood': 'good',
            'energyLevel': 4,
            'painLevel': 2,
            'symptoms': ['fatigue'],
            'privateNotes': 'یادداشت خصوصی',
            'shareSummaryWithCompanion': true,
            'version': 1,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.saveDailyLog(
      version: 0,
      loggedOn: DateTime(2026, 8, 5),
      mood: 'good',
      energyLevel: 4,
      painLevel: 2,
      symptoms: const ['fatigue'],
      privateNotes: 'یادداشت خصوصی',
      shareSummaryWithCompanion: true,
    );

    expect(observed.method, 'PUT');
    expect(observed.url.path, '/api/v1/women-calendar/daily-logs');
    final payload = jsonDecode(observed.body) as Map<String, dynamic>;
    expect(payload['loggedOn'], '2026-08-05');
    expect(payload['energyLevel'], 4);
    expect(payload['painLevel'], 2);
    expect(payload.containsKey('supportNeed'), isFalse);
  });

  test('settings-only update has no daily state field', () async {
    late http.Request observed;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'ownerUserId': 'owner-1',
            'enabled': true,
            'lastPeriodStart': '2026-08-01',
            'cycleLength': 30,
            'periodLength': 6,
            'remindersEnabled': false,
            'version': 5,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.updateWomenCalendarProfile(
      version: 4,
      enabled: true,
      lastPeriodStart: DateTime(2026, 8, 1),
      cycleLength: 30,
      periodLength: 6,
      remindersEnabled: false,
    );

    final payload = jsonDecode(observed.body) as Map<String, dynamic>;
    expect(payload.containsKey('dailyCheckIn'), isFalse);
  });

  test('care support action uses patient-scoped authorized route', () async {
    late http.Request observed;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'caregiver-token',
      httpClient: MockClient((request) async {
        observed = request;
        return http.Response(
          jsonEncode({
            'id': 'action-1',
            'actionType': 'hug',
            'performedAtUtc': '2026-08-05T19:00:00Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.recordCareRecipientWomenSupportAction(
      patientUserId: 'patient-1',
      actionType: ' hug ',
    );

    expect(observed.method, 'POST');
    expect(
      observed.url.path,
      '/api/v1/care/patients/patient-1/women-calendar/support-actions',
    );
    expect(jsonDecode(observed.body), {'actionType': 'hug'});
  });
}
''',
)

# Pure backend source-of-truth guard test.
write(
    'supabase/functions/lifemate-api/women_calendar_source_of_truth_test.ts',
    r'''import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { assertCanonicalWomenDailyLogPayload } from "./women_calendar.ts";

Deno.test("profile settings reject the legacy embedded daily check-in field", () => {
  const error = assertThrows(
    () => assertCanonicalWomenDailyLogPayload({ dailyCheckIn: { mood: "good" } }),
  );
  assertEquals((error as { code?: string }).code, "women_calendar_daily_log_endpoint_required");
});

Deno.test("profile settings accept persistent configuration without daily state", () => {
  assertCanonicalWomenDailyLogPayload({
    enabled: true,
    cycleLength: 28,
    periodLength: 5,
    remindersEnabled: true,
  });
});
''',
)

# Widget regression for explicit selected-day state on a compact small surface.
write(
    'wellmate/test/women_calendar_selected_day_test.dart',
    r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellmate/screens/women_calendar/women_calendar_month_card.dart';

void main() {
  testWidgets('women calendar exposes and updates selected-day state', (tester) async {
    DateTime? selected;
    final today = DateTime(2026, 8, 8);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: WomenCalendarMonthCard(
              episodes: const [],
              estimate: null,
              initialFocusedDate: today,
              selectedDate: today,
              onDateSelected: (value) => selected = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final candidates = find.byKey(const ValueKey('women-calendar-month-grid'));
    expect(candidates, findsOneWidget);
    final dayFinder = find.byKey(const ValueKey('women-calendar-day-2026-8-10'));
    if (dayFinder.evaluate().isNotEmpty) {
      await tester.tap(dayFinder);
      expect(selected, DateTime(2026, 8, 10));
    } else {
      // Persian month boundaries differ from Gregorian month boundaries; tap a
      // rendered date cell through semantics when the exact Gregorian day is
      // outside the visible Jalali month.
      final tappable = find.byType(InkWell).last;
      await tester.tap(tappable);
      expect(selected, isNotNull);
    }
  });
}
''',
)

# Static architecture regression: settings file must not expose or write the
# duplicate daily model. Runtime behavior is covered by API + companion tests.
write(
    'wellmate/test/women_calendar_settings_architecture_test.dart',
    r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('women calendar settings contains persistent configuration only', () {
    final source = File('lib/screens/women_calendar/women_calendar_screen.dart').readAsStringSync();
    expect(source, contains("ValueKey('women-calendar-settings-only')"));
    expect(source, isNot(contains('WomenDailyCheckInCard(')));
    expect(source, isNot(contains("includeDailyCheckIn")));
    expect(source, isNot(contains("dailyCheckIn:")));
    expect(source, isNot(contains('_saveDailyCheckIn')));
  });
}
''',
)

Path(__file__).unlink()
workflow = ROOT / '.github/workflows/round2-women-calendar-one-shot.yml'
if workflow.exists():
    workflow.unlink()
print('round2 women calendar applied')
