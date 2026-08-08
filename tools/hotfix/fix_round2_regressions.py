from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


def write(path: str, content: str) -> None:
    (ROOT / path).write_text(content, encoding='utf-8')


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{path}: expected one match, found {count}: {old[:100]!r}')
    write(path, text.replace(old, new, 1))


path = 'wellmate/lib/screens/treatments/treatments_screen.dart'
replace_once(
    path,
    '''      final api = context.read<LifeMateApiClient>();
      final now = DateTime.now();
      final results = await Future.wait<dynamic>([
        api.getTreatmentPlans(),
        // The care-event endpoint is intentionally bounded. A one-month window
        // keeps this hub fast while recurrence series are represented by the
        // occurrence returned inside the window.
        api.getCareEvents(
          fromDate: now.subtract(const Duration(days: 31)),
          toDate: now,
        ),
        api.getCareEvents(
          fromDate: now.add(const Duration(days: 1)),
          toDate: now.add(const Duration(days: 31)),
        ),
      ]);
      final plans = results[0] as List<Map<String, dynamic>>;
      final pastEvents = results[1] as List<Map<String, dynamic>>;
      final futureEvents = results[2] as List<Map<String, dynamic>>;''',
    '''      final api = context.read<LifeMateApiClient>();
      final now = DateTime.now();
      var failedSources = 0;
      Future<List<Map<String, dynamic>>> safeLoad(
        Future<List<Map<String, dynamic>>> request,
        String label,
      ) async {
        try {
          return await request;
        } catch (error) {
          failedSources += 1;
          debugPrint('WellMate care hub $label load failed: $error');
          return const <Map<String, dynamic>>[];
        }
      }

      final results = await Future.wait<List<Map<String, dynamic>>>([
        safeLoad(api.getTreatmentPlans(), 'treatments'),
        // The care-event endpoint is intentionally bounded. A one-month window
        // keeps this hub fast while recurrence series are represented by the
        // occurrence returned inside the window.
        safeLoad(
          api.getCareEvents(
            fromDate: now.subtract(const Duration(days: 31)),
            toDate: now,
          ),
          'past care events',
        ),
        safeLoad(
          api.getCareEvents(
            fromDate: now.add(const Duration(days: 1)),
            toDate: now.add(const Duration(days: 31)),
          ),
          'future care events',
        ),
      ]);
      final plans = results[0];
      final pastEvents = results[1];
      final futureEvents = results[2];
      if (failedSources == 3) {
        throw StateError('All treatment sources are unavailable.');
      }''',
)

# The hub can be mounted directly by tests and embedded in non-Material shells.
# Give all search/filter controls a shared transparent Material ancestor rather
# than individually patching ChoiceChip/TextField/DropdownButton.
replace_once(
    path,
    '''    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(''',
    '''    return Material(
      color: Colors.transparent,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(''',
)
replace_once(
    path,
    '''        ],
      ),
    );
  }
}

class _TypeChip''',
    '''        ],
        ),
      ),
    );
  }
}

class _TypeChip''',
)

replace_once(
    path,
    '''          else
            for (final item in visible) _CareHubCard(item: item),''',
    '''          else
            for (final item in visible)
              Semantics(
                button: item.type == CareItemType.medication,
                label: item.type == CareItemType.medication
                    ? 'جزئیات ${item.title}'
                    : item.title,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: item.type == CareItemType.medication
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _TreatmentDetailsScreen(
                                plan: item.raw,
                              ),
                            ),
                          )
                      : null,
                  child: _CareHubCard(item: item),
                ),
              ),''',
)

# Keep the 320 logical pixel assertion but give the full month card enough
# vertical room; this prevents the test harness itself from clipping the card.
test_path = 'wellmate/test/women_calendar_selected_day_test.dart'
replace_once(
    test_path,
    '''    final today = DateTime(2026, 8, 8);
    await tester.pumpWidget(''',
    '''    final today = DateTime(2026, 8, 8);
    await tester.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(''',
)

Path(__file__).unlink()
print('round2 regression fixes applied')
