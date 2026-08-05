from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding='utf-8')
    if old not in text:
        if new in text:
            return
        raise SystemExit(f'Expected snippet not found in {path}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8')


def replace_between(path: str, start: str, end: str, new: str, marker: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding='utf-8')
    if marker in text:
        return
    start_index = text.find(start)
    if start_index < 0:
        raise SystemExit(f'Start marker not found in {path}: {start}')
    end_index = text.find(end, start_index)
    if end_index < 0:
        raise SystemExit(f'End marker not found in {path}: {end}')
    target.write_text(
        text[:start_index] + new + text[end_index:],
        encoding='utf-8',
    )


replace_once(
    'wellmate/lib/screens/women_calendar/women_calendar_screen.dart',
    "import '../profile/profile_destination_screens.dart';\n",
    "import '../profile/profile_destination_screens.dart';\n"
    "import 'women_calendar_month_card.dart';\n",
)

replace_between(
    'packages/lifemate_client/lib/src/lifemate_api_client.dart',
    '  Future<Map<String, dynamic>> completeWomenCalendarEpisode({\n',
    '  Future<void> deleteWomenCalendarEpisode',
    '''  Future<Map<String, dynamic>> updateWomenCalendarEpisode({
    required String episodeId,
    required int version,
    required DateTime startedOn,
    required DateTime? endedOn,
    String? privateNotes,
  }) async => _asObject(
    await _send(
      'PATCH',
      '/api/v1/women-calendar/episodes/$episodeId',
      body: {
        'version': version,
        'startedOn': _date(startedOn),
        'endedOn': endedOn == null ? null : _date(endedOn),
        'privateNotes': _emptyToNull(privateNotes),
      },
    ),
  );

''',
    'Future<Map<String, dynamic>> updateWomenCalendarEpisode',
)

replace_between(
    'supabase/functions/lifemate-api/women_calendar.ts',
    '  async function updateOwnerEpisode(\n',
    '  async function deleteOwnerEpisode(',
    '''  async function updateOwnerEpisode(
    userId: string,
    episodeIdValue: unknown,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const episodeId = requiredUuid(episodeIdValue, "episodeId");
    const expectedVersion = requiredPositiveInt(body.version, "version");
    const startedOn = requiredDate(body.startedOn, "startedOn");
    const endedOn = body.endedOn == null
      ? null
      : requiredDate(body.endedOn, "endedOn");
    if (endedOn != null && endedOn < startedOn) {
      throw new ApiError(
        400,
        "invalid_women_calendar_episode",
        "endedOn cannot precede startedOn.",
      );
    }
    const privateNotes = limitedOptional(
      body.privateNotes,
      "privateNotes",
      500,
    );
    const endBoundary = endedOn ?? startedOn;

    return await sql.begin(async (tx: any) => {
      const existingRows = await tx`
        select * from lifemate.women_calendar_episodes
        where id = ${episodeId} and owner_user_id = ${userId}
        for update
      `;
      const existing = existingRows[0];
      if (!existing) {
        throw new ApiError(
          404,
          "women_calendar_episode_not_found",
          "Episode not found.",
        );
      }
      if (existing.version !== expectedVersion) {
        throw new ApiError(
          409,
          "stale_women_calendar_episode",
          "Period episode changed. Refresh and try again.",
        );
      }
      const overlaps = await tx`
        select id from lifemate.women_calendar_episodes
        where owner_user_id = ${userId}
          and id <> ${episodeId}
          and started_on <= ${endBoundary}::date
          and coalesce(ended_on, started_on) >= ${startedOn}::date
        limit 1
      `;
      if (overlaps[0]) {
        throw new ApiError(
          409,
          "women_calendar_episode_overlap",
          "Period episode overlaps an existing episode.",
        );
      }
      const rows = await tx`
        update lifemate.women_calendar_episodes
        set started_on = ${startedOn}, ended_on = ${endedOn},
            private_notes = ${privateNotes}, version = version + 1,
            updated_at_utc = now()
        where id = ${episodeId}
        returning *
      `;
      await tx`
        update lifemate.women_calendar_profiles
        set last_period_start = case
              when last_period_start = ${dateString(existing.started_on)}::date
                then ${startedOn}::date
              else last_period_start
            end,
            version = version + 1,
            updated_at_utc = now()
        where owner_user_id = ${userId}
      `;
      await insertAudit(
        tx,
        userId,
        "women_calendar.episode_updated",
        "women_calendar_episode",
        episodeId,
      );
      return mapEpisodeOwner(rows[0]);
    });
  }

''',
    '"women_calendar.episode_updated"',
)

replace_once(
    'supabase/functions/lifemate-api/women_calendar.ts',
    '''      await insertAudit(
        tx,
        userId,
        "women_calendar.episode_deleted",
        "women_calendar_episode",
        episodeId,
      );
''',
    '''      await tx`
        update lifemate.women_calendar_profiles
        set last_period_start = case
              when last_period_start = (
                select started_on
                from lifemate.women_calendar_episodes
                where id = ${episodeId}
              ) then (
                select max(started_on)
                from lifemate.women_calendar_episodes
                where owner_user_id = ${userId}
              )
              else last_period_start
            end,
            version = version + 1,
            updated_at_utc = now()
        where owner_user_id = ${userId}
      `;
      await insertAudit(
        tx,
        userId,
        "women_calendar.episode_deleted",
        "women_calendar_episode",
        episodeId,
      );
''',
)

# The deleted row is no longer queryable, so preserve its start date before delete
# and use it for profile reconciliation.
replace_once(
    'supabase/functions/lifemate-api/women_calendar.ts',
    '''    await sql.begin(async (tx: any) => {
      const rows = await tx`
        delete from lifemate.women_calendar_episodes
        where id = ${episodeId} and owner_user_id = ${userId}
        returning id
      `;
''',
    '''    await sql.begin(async (tx: any) => {
      const rows = await tx`
        delete from lifemate.women_calendar_episodes
        where id = ${episodeId} and owner_user_id = ${userId}
        returning id, started_on
      `;
''',
)
replace_once(
    'supabase/functions/lifemate-api/women_calendar.ts',
    '''              when last_period_start = (
                select started_on
                from lifemate.women_calendar_episodes
                where id = ${episodeId}
              ) then (
''',
    '''              when last_period_start = ${dateString(rows[0].started_on)}::date
                then (
''',
)

replace_between(
    'wellmate/lib/screens/women_calendar/women_calendar_screen.dart',
    '  Future<void> _startPeriodToday() async {\n',
    '  @override\n  Widget build(BuildContext context) {',
    '''  Future<void> _createEpisode() async {
    if (_saving) return;
    final draft = await _showEpisodeEditor();
    if (draft == null) return;
    setState(() => _saving = true);
    try {
      await context.read<LifeMateApiClient>().createWomenCalendarEpisode(
        startedOn: draft.startedOn,
        endedOn: draft.endedOn,
        privateNotes: draft.privateNotes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('دوره و یادداشت خصوصی ثبت شد.')),
      );
      await _load();
      await widget.onProfileChanged?.call();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.code == 'women_calendar_episode_overlap'
                ? 'این بازه با یک ثبت قبلی هم‌پوشانی دارد.'
                : 'ثبت دوره انجام نشد.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _finishPeriodToday() async {
    final episode = _openEpisode;
    if (episode == null || _saving) return;
    final startedOn = DateTime.parse(episode['startedOn'].toString());
    setState(() => _saving = true);
    try {
      await context.read<LifeMateApiClient>().updateWomenCalendarEpisode(
        episodeId: episode['id'].toString(),
        version: episode['version'] is int ? episode['version'] as int : 1,
        startedOn: startedOn,
        endedOn: DateTime.now(),
        privateNotes: episode['privateNotes']?.toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('پایان دوره برای امروز ثبت شد.')),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editEpisode(Map<String, dynamic> episode) async {
    if (_saving) return;
    final draft = await _showEpisodeEditor(episode: episode);
    if (draft == null) return;
    if (draft.deleteRequested) {
      await _deleteEpisode(episode);
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<LifeMateApiClient>().updateWomenCalendarEpisode(
        episodeId: episode['id'].toString(),
        version: episode['version'] is int ? episode['version'] as int : 1,
        startedOn: draft.startedOn,
        endedOn: draft.endedOn,
        privateNotes: draft.privateNotes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ثبت دوره اصلاح شد.')),
      );
      await _load();
      await widget.onProfileChanged?.call();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.code == 'stale_women_calendar_episode'
                ? 'این ثبت تغییر کرده است؛ اطلاعات تازه‌سازی شد.'
                : error.code == 'women_calendar_episode_overlap'
                ? 'این بازه با یک ثبت قبلی هم‌پوشانی دارد.'
                : 'اصلاح ثبت انجام نشد.',
          ),
        ),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteEpisode(Map<String, dynamic> episode) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف ثبت اشتباه'),
        content: const Text(
          'این ثبت و یادداشت خصوصی آن حذف می‌شود. این کار قابل بازگشت نیست.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await context.read<LifeMateApiClient>().deleteWomenCalendarEpisode(
        episodeId: episode['id'].toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ثبت اشتباه حذف شد.')),
      );
      await _load();
      await widget.onProfileChanged?.call();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<_EpisodeEditorResult?> _showEpisodeEditor({
    Map<String, dynamic>? episode,
  }) async {
    var startedOn = episode == null
        ? DateTime.now()
        : DateTime.parse(episode['startedOn'].toString());
    DateTime? endedOn = episode?['endedOn'] == null
        ? null
        : DateTime.parse(episode!['endedOn'].toString());
    final notesController = TextEditingController(
      text: episode?['privateNotes']?.toString() ?? '',
    );
    String? validationError;
    final result = await showDialog<_EpisodeEditorResult>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(episode == null ? 'ثبت دوره' : 'اصلاح ثبت دوره'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تاریخ شروع'),
                  subtitle: Text(formatAppDate(context, startedOn)),
                  trailing: const Icon(Icons.edit_calendar_rounded),
                  onTap: () async {
                    final value = await showAppDatePicker(
                      context: context,
                      initialDate: startedOn,
                      firstDate: DateTime(2015),
                      lastDate: DateTime.now(),
                      title: 'تاریخ شروع دوره',
                    );
                    if (value != null) {
                      setDialogState(() {
                        startedOn = value;
                        validationError = null;
                      });
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تاریخ پایان'),
                  subtitle: Text(
                    endedOn == null
                        ? 'هنوز ادامه دارد'
                        : formatAppDate(context, endedOn!),
                  ),
                  trailing: Wrap(
                    spacing: 2,
                    children: [
                      if (endedOn != null)
                        IconButton(
                          tooltip: 'حذف تاریخ پایان',
                          onPressed: () =>
                              setDialogState(() => endedOn = null),
                          icon: const Icon(Icons.clear_rounded),
                        ),
                      IconButton(
                        tooltip: 'انتخاب تاریخ پایان',
                        onPressed: () async {
                          final value = await showAppDatePicker(
                            context: context,
                            initialDate: endedOn ?? startedOn,
                            firstDate: startedOn,
                            lastDate: DateTime.now(),
                            title: 'تاریخ پایان دوره',
                          );
                          if (value != null) {
                            setDialogState(() {
                              endedOn = value;
                              validationError = null;
                            });
                          }
                        },
                        icon: const Icon(Icons.edit_calendar_rounded),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesController,
                  maxLength: 500,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'یادداشت خصوصی',
                    hintText: 'این متن فقط برای خود شما نمایش داده می‌شود.',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                ),
                if (validationError != null)
                  Text(
                    validationError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            if (episode != null)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(
                  _EpisodeEditorResult(
                    startedOn: startedOn,
                    endedOn: endedOn,
                    privateNotes: notesController.text.trim(),
                    deleteRequested: true,
                  ),
                ),
                child: const Text('حذف ثبت'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                if (endedOn != null && endedOn!.isBefore(startedOn)) {
                  setDialogState(() {
                    validationError = 'تاریخ پایان نمی‌تواند قبل از شروع باشد.';
                  });
                  return;
                }
                Navigator.of(dialogContext).pop(
                  _EpisodeEditorResult(
                    startedOn: startedOn,
                    endedOn: endedOn,
                    privateNotes: notesController.text.trim(),
                  ),
                );
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
    notesController.dispose();
    return result;
  }

''',
    'Future<_EpisodeEditorResult?> _showEpisodeEditor',
)

replace_once(
    'wellmate/lib/screens/women_calendar/women_calendar_screen.dart',
    '''          _SummaryCard(estimate: estimate),
          const SizedBox(height: 18),
          _TimelineCard(estimate: estimate),
''',
    '''          _SummaryCard(estimate: estimate),
          const SizedBox(height: 18),
          WomenCalendarMonthCard(episodes: _episodes, estimate: estimate),
          const SizedBox(height: 18),
          _TimelineCard(estimate: estimate),
''',
)

replace_once(
    'wellmate/lib/screens/women_calendar/women_calendar_screen.dart',
    '''            onStart: _startPeriodToday,
            onFinish: _finishPeriodToday,
''',
    '''            onStart: _createEpisode,
            onFinish: _finishPeriodToday,
            onEdit: _editEpisode,
''',
)

replace_between(
    'wellmate/lib/screens/women_calendar/women_calendar_screen.dart',
    'class _EpisodeActionsCard extends StatelessWidget {\n',
    'class _SoftSection extends StatelessWidget {',
    '''class _EpisodeActionsCard extends StatelessWidget {
  const _EpisodeActionsCard({
    required this.openEpisode,
    required this.episodes,
    required this.saving,
    required this.onStart,
    required this.onFinish,
    required this.onEdit,
  });

  final Map<String, dynamic>? openEpisode;
  final List<Map<String, dynamic>> episodes;
  final bool saving;
  final VoidCallback onStart;
  final VoidCallback onFinish;
  final ValueChanged<Map<String, dynamic>> onEdit;

  @override
  Widget build(BuildContext context) {
    return _SoftSection(
      title: 'ثبت واقعی دوره',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: saving
                  ? null
                  : (openEpisode == null ? onStart : onFinish),
              icon: Icon(
                openEpisode == null
                    ? Icons.play_circle_fill_rounded
                    : Icons.stop_circle_rounded,
              ),
              label: Text(
                openEpisode == null ? 'ثبت شروع و یادداشت' : 'پایان دوره امروز',
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'آخرین ثبت‌ها',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (episodes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('هنوز دوره‌ای ثبت نشده است.'),
            )
          else
            ...episodes.take(4).map((episode) {
              final notes = episode['privateNotes']?.toString().trim() ?? '';
              final endedOn = episode['endedOn'];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.water_drop_outlined),
                title: Text(
                  formatAppDate(
                    context,
                    DateTime.parse(episode['startedOn'].toString()),
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      endedOn == null
                          ? 'در حال ثبت'
                          : 'تا ${formatAppDate(context, DateTime.parse(endedOn.toString()))}',
                    ),
                    if (notes.isNotEmpty)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.lock_outline_rounded, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              notes,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                trailing: IconButton(
                  tooltip: 'اصلاح ثبت',
                  onPressed: saving ? null : () => onEdit(episode),
                  icon: const Icon(Icons.edit_rounded),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _EpisodeEditorResult {
  const _EpisodeEditorResult({
    required this.startedOn,
    required this.endedOn,
    required this.privateNotes,
    this.deleteRequested = false,
  });

  final DateTime startedOn;
  final DateTime? endedOn;
  final String privateNotes;
  final bool deleteRequested;
}

''',
    'class _EpisodeEditorResult',
)

replace_once(
    'supabase/functions/lifemate-api/women_calendar_integration_test.ts',
    '''      assertEquals(episode.privateNotes, "owner-only secret note");

      await assertApiError(
''',
    '''      assertEquals(episode.privateNotes, "owner-only secret note");

      const correctedEpisode = await women.updateOwnerEpisode(
        patient.appUserId,
        episode.id,
        {
          version: episode.version,
          startedOn: "2026-08-02",
          endedOn: "2026-08-06",
          privateNotes: "corrected owner-only note",
        },
      );
      assertEquals(correctedEpisode.startedOn, "2026-08-02");
      assertEquals(correctedEpisode.endedOn, "2026-08-06");
      assertEquals(
        correctedEpisode.privateNotes,
        "corrected owner-only note",
      );
      const ownerEpisodes = await women.listOwnerEpisodes(patient.appUserId);
      assertEquals(ownerEpisodes.length, 1);
      assertEquals(ownerEpisodes[0].privateNotes, "corrected owner-only note");
      const leakedAudit = await admin`
        select count(*)::int as count
        from lifemate.audit_logs as logs
        where actor_user_id = ${patient.appUserId}
          and to_jsonb(logs)::text ilike ${"%corrected owner-only note%"}
      `;
      assertEquals(leakedAudit[0].count, 0);

      await assertApiError(
''',
)

replace_once(
    'supabase/functions/lifemate-api/women_calendar_integration_test.ts',
    '''      await assertApiError(
        () => women.getCareSummary(caregiver.appUserId, patient.appUserId),
        403,
        "women_calendar_access_denied",
      );
    } finally {
''',
    '''      await assertApiError(
        () => women.getCareSummary(caregiver.appUserId, patient.appUserId),
        403,
        "women_calendar_access_denied",
      );

      await women.deleteOwnerEpisode(
        patient.appUserId,
        correctedEpisode.id,
      );
      assertEquals(
        (await women.listOwnerEpisodes(patient.appUserId)).length,
        0,
      );
    } finally {
''',
)

print('Women calendar monthly view, private notes, and episode correction patch applied.')
