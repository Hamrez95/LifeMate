import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores only whether the device has shown the Camp guide; no account or
/// health information is written to local preferences.
class CampIntroductionPreferences {
  const CampIntroductionPreferences();

  static const _completedKey = 'lifemate.camp_intro.v1.completed';

  Future<bool> get hasCompleted async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_completedKey) ?? false;
  }

  Future<void> markCompleted() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_completedKey, true);
  }
}

Future<void> showCampIntroduction({
  required BuildContext context,
  required bool isPersian,
}) => showDialog<void>(
  context: context,
  barrierDismissible: true,
  builder: (_) => CampIntroductionDialog(isPersian: isPersian),
);

class CampIntroductionDialog extends StatefulWidget {
  const CampIntroductionDialog({super.key, required this.isPersian});

  final bool isPersian;

  @override
  State<CampIntroductionDialog> createState() => _CampIntroductionDialogState();
}

class _CampIntroductionDialogState extends State<CampIntroductionDialog> {
  final PageController _controller = PageController();
  int _page = 0;

  static const _icons = <IconData>[
    Icons.home_work_rounded,
    Icons.grid_view_rounded,
    Icons.explore_rounded,
  ];

  List<_CampIntroductionStep> get _steps => widget.isPersian
      ? const [
          _CampIntroductionStep(
            title: 'به دهکدهٔ LifeMate خوش آمدی',
            body: 'خانهٔ مرکزی نقطهٔ شروع تو برای مرور دهکده و بخش امروز است.',
            caption: 'خانهٔ تو در یک نگاه',
          ),
          _CampIntroductionStep(
            title: 'خانهٔ محصولت را باز کن',
            body:
                'با انتخاب خانهٔ فعال، مستقیم وارد WellMate، CareMate یا CocoonMate می‌شوی؛ همان حساب LifeMate همراهت می‌ماند.',
            caption: 'هر خانه، یک مسیر',
          ),
          _CampIntroductionStep(
            title: 'از نوار پایین حرکت کن',
            body:
                'Home برای دهکده، Journey برای مسیرها، Circle برای همراهان و You برای پروفایل مشترک است. بعضی بخش‌ها با آماده‌شدن سرویس فعال می‌شوند.',
            caption: 'همه‌چیز از همین‌جا',
          ),
        ]
      : const [
          _CampIntroductionStep(
            title: 'Welcome to your LifeMate Camp',
            body:
                'The central house is your starting point for Camp and Today.',
            caption: 'Your home at a glance',
          ),
          _CampIntroductionStep(
            title: 'Open a product house',
            body:
                'Choose an active house to enter WellMate, CareMate or CocoonMate. Your LifeMate account stays with you.',
            caption: 'Each house has a path',
          ),
          _CampIntroductionStep(
            title: 'Move around from the bottom bar',
            body:
                'Home is your Camp, Journey is for pathways, Circle is for companions, and You is your shared profile. Some areas appear as their services become available.',
            caption: 'Start wherever you need',
          ),
        ];

  String _t(String en, String fa) => widget.isPersian ? fa : en;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _steps.length - 1) {
      Navigator.of(context).pop();
      return;
    }
    final nextPage = _page + 1;
    setState(() => _page = nextPage);
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(nextPage);
    } else {
      _controller.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _t('Camp guide', 'راهنمای دهکده'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('camp-guide-skip'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(_t('Skip', 'رد کردن')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 280,
                  child: PageView.builder(
                    controller: _controller,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _steps.length,
                    itemBuilder: (context, index) {
                      final page = _steps[index];
                      return LayoutBuilder(
                        builder: (context, constraints) =>
                            SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 96,
                                      height: 96,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: colors.primaryContainer,
                                        boxShadow: [
                                          BoxShadow(
                                            color: colors.primary.withValues(
                                              alpha: .14,
                                            ),
                                            blurRadius: 28,
                                            spreadRadius: 3,
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        _icons[index],
                                        size: 54,
                                        color: colors.onPrimaryContainer,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      page.title,
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      page.body,
                                      textAlign: TextAlign.center,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      page.caption,
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(color: colors.primary),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                Semantics(
                  liveRegion: true,
                  label: _t(
                    'Step ${_page + 1} of ${_steps.length}',
                    'مرحلهٔ ${_page + 1} از ${_steps.length}',
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var index = 0; index < _steps.length; index++)
                        AnimatedContainer(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          width: index == _page ? 22 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: index == _page
                                ? colors.primary
                                : colors.outlineVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    key: const ValueKey('camp-guide-next'),
                    onPressed: _next,
                    child: Text(
                      _page == _steps.length - 1
                          ? _t('Start exploring', 'شروع کن')
                          : _t('Continue', 'ادامه'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CampIntroductionStep {
  const _CampIntroductionStep({
    required this.title,
    required this.body,
    required this.caption,
  });

  final String title;
  final String body;
  final String caption;
}

class CampIntroductionTile extends StatelessWidget {
  const CampIntroductionTile({
    super.key,
    required this.isPersian,
    required this.onTap,
  });

  final bool isPersian;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      minVerticalPadding: 12,
      leading: const CircleAvatar(child: Icon(Icons.explore_outlined)),
      title: Text(isPersian ? 'راهنمای دهکده' : 'Camp guide'),
      subtitle: Text(
        isPersian
            ? 'با خانه‌ها و بخش‌های LifeMate آشنا شو.'
            : 'Learn how the LifeMate Camp is organized.',
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}
