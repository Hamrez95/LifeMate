part of '../cocoonmate_module.dart';

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
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: CocoonTheme.muted),
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
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: CocoonTheme.skyStrong),
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
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: CocoonTheme.coral),
                ),
                const SizedBox(height: 10),
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 14),
                Text(
                  body,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: CocoonTheme.muted),
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
