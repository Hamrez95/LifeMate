part of 'lifemate_experience_gate.dart';

class _AccountPreparationExperience extends StatefulWidget {
  const _AccountPreparationExperience({
    required this.appName,
    required this.logoAssetPath,
  });

  final String appName;
  final String logoAssetPath;

  @override
  State<_AccountPreparationExperience> createState() =>
      _AccountPreparationExperienceState();
}

class _AccountPreparationExperienceState
    extends State<_AccountPreparationExperience>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Random _random;
  Timer? _factTimer;
  int _factIndex = 0;

  _BrandPalette get _brand => _BrandPalette.forApp(widget.appName);

  @override
  void initState() {
    super.initState();
    _random = Random(DateTime.now().microsecondsSinceEpoch);
    _factIndex = _random.nextInt(lifeMateHealthFacts.length);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _factTimer = Timer.periodic(const Duration(milliseconds: 2400), (_) {
      if (!mounted || lifeMateHealthFacts.length < 2) return;
      var next = _random.nextInt(lifeMateHealthFacts.length);
      if (next == _factIndex) next = (next + 1) % lifeMateHealthFacts.length;
      setState(() => _factIndex = next);
    });
  }

  @override
  void dispose() {
    _factTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = _brand;
    final fact = lifeMateHealthFacts[_factIndex];
    return Directionality(
      textDirection: LifeMateRuntimeLocale.isPersian
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: brand.background,
        body: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) => _AmbientBackdrop(
                  progress: _controller.value,
                  brand: brand,
                  quieter: true,
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(22, 28, 22, 30),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 470),
                    child: Column(
                      children: [
                        _OrbitingLogo(
                          controller: _controller,
                          logoAssetPath: widget.logoAssetPath,
                          brand: brand,
                        ),
                        SizedBox(height: 26),
                        Text(
                          brand.eyebrow,
                          style: TextStyle(
                            color: brand.primary,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'در حال آماده‌سازی حساب',
                              en: "Preparing account",
                            ),
                            en: "Preparing account",
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: brand.ink,
                            fontSize: 31,
                            height: 1.3,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          brand.preparationSubtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF687895),
                            fontSize: 14,
                            height: 1.8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 24),
                        _PreparationStages(
                          controller: _controller,
                          brand: brand,
                        ),
                        SizedBox(height: 18),
                        Semantics(
                          liveRegion: true,
                          label: '${fact.category}: ${fact.text}',
                          child: AnimatedSwitcher(
                            duration: Duration(milliseconds: 520),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: Offset(0, 0.08),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: _HealthFactCard(
                              key: ValueKey(_factIndex),
                              fact: fact,
                              brand: brand,
                            ),
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'نکته‌های عمومی سلامت هستند و جایگزین توصیه پزشک شما نیستند.',
                              en: "These are general health tips and are not a substitute for your doctor's advice.",
                            ),
                            en: "These are general health tips and are not a substitute for your doctor's advice.",
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF8A95A8),
                            fontSize: 10,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrbitingLogo extends StatelessWidget {
  const _OrbitingLogo({
    required this.controller,
    required this.logoAssetPath,
    required this.brand,
  });

  final AnimationController controller;
  final String logoAssetPath;
  final _BrandPalette brand;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      height: 190,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final angle = controller.value * pi * 2;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: brand.primary.withValues(alpha: 0.16),
                    width: 1.5,
                  ),
                ),
              ),
              Transform.rotate(
                angle: angle,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: brand.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: brand.primary.withValues(alpha: 0.45),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Transform.rotate(
                angle: -angle * 0.72,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: brand.secondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              Transform.scale(
                scale: 0.98 + sin(angle) * 0.025,
                child: Container(
                  width: 116,
                  height: 116,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(34),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: brand.primary.withValues(alpha: 0.17),
                        blurRadius: 30,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    logoAssetPath,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        Icon(brand.heroIcon, size: 70, color: brand.primary),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PreparationStages extends StatelessWidget {
  const _PreparationStages({required this.controller, required this.brand});

  final AnimationController controller;
  final _BrandPalette brand;

  @override
  Widget build(BuildContext context) {
    final stages = [
      (
        Icons.cloud_download_rounded,
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'دریافت اطلاعات',
            en: "Get information",
          ),
          en: "Get information",
        ),
      ),
      (
        Icons.event_available_rounded,
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'تنظیم برنامه',
            en: "Program setting",
          ),
          en: "Program setting",
        ),
      ),
      (
        Icons.shield_rounded,
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'ایمن‌سازی', en: "Immunization"),
          en: "Immunization",
        ),
      ),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: brand.primary.withValues(alpha: 0.09),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final active =
              (controller.value * stages.length).floor() % stages.length;
          return Row(
            children: List.generate(stages.length * 2 - 1, (index) {
              if (index.isOdd) {
                return Expanded(
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          brand.primary.withValues(alpha: 0.2),
                          brand.primary.withValues(alpha: 0.72),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                );
              }
              final stageIndex = index ~/ 2;
              final stage = stages[stageIndex];
              final highlighted = stageIndex == active;
              return AnimatedScale(
                duration: const Duration(milliseconds: 260),
                scale: highlighted ? 1.06 : 1,
                child: SizedBox(
                  width: 91,
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: brand.primary.withValues(
                              alpha: highlighted ? 0.52 : 0.16,
                            ),
                            width: highlighted ? 2 : 1,
                          ),
                          boxShadow: highlighted
                              ? [
                                  BoxShadow(
                                    color: brand.primary.withValues(
                                      alpha: 0.25,
                                    ),
                                    blurRadius: 18,
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(stage.$1, color: brand.primary, size: 25),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        stage.$2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: brand.primaryDeep,
                          fontSize: 10,
                          height: 1.35,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class _HealthFactCard extends StatelessWidget {
  const _HealthFactCard({required this.fact, required this.brand, super.key});

  final LifeMateHealthFact fact;
  final _BrandPalette brand;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.79),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: brand.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  brand.primary.withValues(alpha: 0.16),
                  brand.secondary.withValues(alpha: 0.2),
                ],
              ),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(Icons.tips_and_updates_rounded, color: brand.primary),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fact.category,
                  style: TextStyle(
                    color: brand.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  fact.text,
                  style: const TextStyle(
                    color: Color(0xFF354262),
                    fontSize: 13,
                    height: 1.72,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
