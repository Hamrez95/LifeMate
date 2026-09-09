part of '../cocoonmate_module.dart';

class CocoonScaffold extends StatelessWidget {
  const CocoonScaffold({
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.safeArea = true,
    super.key,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool safeArea;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: appBar,
        body: safeArea ? SafeArea(top: appBar == null, child: body) : body,
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
      );
}

class CocoonAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CocoonAppBar({
    required this.title,
    this.eyebrow,
    this.actions,
    this.showBackButton = true,
    super.key,
  });

  final String title;
  final String? eyebrow;
  final List<Widget>? actions;
  final bool showBackButton;

  @override
  Size get preferredSize => Size.fromHeight(eyebrow == null ? 64 : 76);

  @override
  Widget build(BuildContext context) => AppBar(
        automaticallyImplyLeading: showBackButton,
        toolbarHeight: preferredSize.height,
        titleSpacing: showBackButton ? 0 : CocoonSpacing.lg,
        title: Semantics(
          header: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (eyebrow != null)
                Text(
                  eyebrow!,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: CocoonColors.coralAction),
                ),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        actions: actions,
      );
}

class CocoonSurface extends StatelessWidget {
  const CocoonSurface({
    required this.child,
    this.padding = const EdgeInsetsDirectional.all(CocoonSpacing.lg),
    this.color = CocoonColors.surfaceRaised,
    this.radius = CocoonRadii.card,
    this.borderColor = CocoonColors.line,
    this.elevated = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radius;
  final Color borderColor;
  final bool elevated;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor),
          boxShadow: elevated ? CocoonElevation.subtle : null,
        ),
        child: Padding(padding: padding, child: child),
      );
}

class CocoonPrimaryCta extends StatelessWidget {
  const CocoonPrimaryCta({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: onPressed != null && !busy,
        label: label,
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: busy ? null : onPressed,
            icon: busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon ?? Icons.arrow_forward_rounded),
            label: Text(label),
          ),
        ),
      );
}

class CocoonStatusBadge extends StatelessWidget {
  const CocoonStatusBadge({
    required this.label,
    required this.icon,
    this.foreground = CocoonColors.skyStrong,
    this.background = CocoonColors.sky,
    super.key,
  });

  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(CocoonRadii.chip),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 7, 10, 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: foreground),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: foreground, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class CocoonLoadingState extends StatelessWidget {
  const CocoonLoadingState({required this.semanticLabel, super.key});

  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        liveRegion: true,
        label: semanticLabel,
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              _CocoonSkeleton(height: 210, radius: CocoonRadii.hero),
              SizedBox(height: CocoonSpacing.section),
              _CocoonSkeleton(height: 24, widthFactor: .48),
              SizedBox(height: CocoonSpacing.md),
              _CocoonSkeleton(height: 92),
              SizedBox(height: CocoonSpacing.sm),
              _CocoonSkeleton(height: 92),
            ],
          ),
        ),
      );
}

class _CocoonSkeleton extends StatelessWidget {
  const _CocoonSkeleton({
    required this.height,
    this.radius = CocoonRadii.control,
    this.widthFactor = 1,
  });

  final double height;
  final double radius;
  final double widthFactor;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: widthFactor,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: CocoonColors.warm,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      );
}

class CocoonEmptyState extends StatelessWidget {
  const CocoonEmptyState({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        child: CocoonSurface(
          color: CocoonColors.warm,
          borderColor: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 28, color: CocoonColors.coralAction),
              const SizedBox(height: CocoonSpacing.sm),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: CocoonSpacing.xs),
              Text(
                body,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: CocoonColors.muted),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: CocoonSpacing.md),
                TextButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      );
}

class CocoonBrandMark extends StatelessWidget {
  const CocoonBrandMark({
    required this.semanticLabel,
    this.size = 72,
    this.showWordmark = false,
    super.key,
  });

  final String semanticLabel;
  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: semanticLabel,
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: Size.square(size),
                painter: const _CocoonBrandPainter(),
              ),
              if (showWordmark) ...[
                const SizedBox(width: CocoonSpacing.sm),
                Text(
                  'CocoonMate',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: CocoonColors.ink, letterSpacing: -.2),
                ),
              ],
            ],
          ),
        ),
      );
}

class _CocoonBrandPainter extends CustomPainter {
  const _CocoonBrandPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final background = Paint()..color = CocoonColors.warm;
    canvas.drawCircle(center, scale * .48, background);

    final outer = Paint()
      ..color = CocoonColors.coralAction
      ..style = PaintingStyle.stroke
      ..strokeWidth = scale * .105
      ..strokeCap = StrokeCap.round;
    final outerPath = Path()
      ..moveTo(scale * .3, scale * .25)
      ..cubicTo(
        scale * .7,
        scale * .12,
        scale * .88,
        scale * .42,
        scale * .72,
        scale * .7,
      )
      ..cubicTo(
        scale * .58,
        scale * .91,
        scale * .27,
        scale * .82,
        scale * .24,
        scale * .55,
      );
    canvas.drawPath(outerPath, outer);

    final inner = Paint()
      ..color = CocoonColors.lilac
      ..style = PaintingStyle.stroke
      ..strokeWidth = scale * .09
      ..strokeCap = StrokeCap.round;
    final innerPath = Path()
      ..moveTo(scale * .43, scale * .35)
      ..cubicTo(
        scale * .69,
        scale * .29,
        scale * .74,
        scale * .55,
        scale * .59,
        scale * .68,
      )
      ..cubicTo(
        scale * .45,
        scale * .79,
        scale * .32,
        scale * .62,
        scale * .39,
        scale * .49,
      );
    canvas.drawPath(innerPath, inner);
    canvas.drawCircle(
      center,
      scale * .055,
      Paint()..color = CocoonColors.sageStrong,
    );
  }

  @override
  bool shouldRepaint(covariant _CocoonBrandPainter oldDelegate) => false;
}

class CocoonPagePadding extends StatelessWidget {
  const CocoonPagePadding({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 28),
        child: child,
      );
}

class CocoonSectionHeading extends StatelessWidget {
  const CocoonSectionHeading({
    required this.title,
    this.supporting,
    this.action,
    super.key,
  });

  final String title;
  final String? supporting;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                if (supporting != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    supporting!,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: CocoonTheme.muted),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) action!,
        ],
      );
}

class CocoonOfflineStrip extends StatelessWidget {
  const CocoonOfflineStrip({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
    super.key,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: message,
        child: Container(
          width: double.infinity,
          color: CocoonTheme.sky,
          padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 12, 8),
          child: Row(
            children: [
              const Icon(
                Icons.cloud_done_outlined,
                size: 18,
                color: CocoonTheme.skyStrong,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: CocoonTheme.skyStrong),
                ),
              ),
              TextButton(onPressed: onRetry, child: Text(retryLabel)),
            ],
          ),
        ),
      );
}

class CocoonStatePage extends StatelessWidget {
  const CocoonStatePage({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.action,
    required this.onPressed,
    this.secondary,
    super.key,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String body;
  final String action;
  final VoidCallback onPressed;
  final String? secondary;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: CocoonTheme.coralSoft,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 32, color: CocoonTheme.coral),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Text(
                      eyebrow,
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: CocoonTheme.coral),
                    ),
                    const SizedBox(height: 10),
                    Text(title,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 14),
                    Text(
                      body,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(color: CocoonTheme.muted),
                    ),
                    const SizedBox(height: 32),
                    FilledButton(onPressed: onPressed, child: Text(action)),
                    if (secondary != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        secondary!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class CocoonGrowthOrb extends StatelessWidget {
  const CocoonGrowthOrb({
    required this.progress,
    required this.semanticLabel,
    this.size = 164,
    super.key,
  });

  final double progress;
  final double size;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: semanticLabel,
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CocoonTheme.warm,
                  border: Border.all(color: Colors.white, width: 8),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1FD96055),
                      blurRadius: 36,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
              ),
              SizedBox.square(
                dimension: size - 24,
                child: CircularProgressIndicator(
                  value: progress.clamp(0, 1).toDouble(),
                  strokeWidth: 7,
                  strokeCap: StrokeCap.round,
                  color: CocoonTheme.coral,
                  backgroundColor: const Color(0xFFFFE6DF),
                ),
              ),
              Container(
                width: size * .45,
                height: size * .58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size),
                  color: const Color(0xFFFFC5B7),
                ),
                transform: Matrix4.rotationZ(-.42),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    margin: EdgeInsets.only(bottom: size * .08),
                    width: size * .15,
                    height: size * .15,
                    decoration: const BoxDecoration(
                      color: CocoonTheme.sageStrong,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

String cocoonDigits(String value, bool fa) {
  if (!fa) return value;
  const western = '0123456789';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  return value.split('').map((char) {
    final index = western.indexOf(char);
    return index < 0 ? char : persian[index];
  }).join();
}
