part of 'lifemate_experience_gate.dart';

class _ExperienceBlockingState extends StatelessWidget {
  const _ExperienceBlockingState({
    required this.appName,
    required this.icon,
    required this.title,
    required this.message,
    this.logoAssetPath,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String appName;
  final String? logoAssetPath;
  final IconData icon;
  final String title;
  final String message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final brand = _BrandPalette.forApp(appName);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: brand.background,
        body: Stack(
          children: [
            Positioned.fill(
              child: _AmbientBackdrop(progress: 0.64, brand: brand),
            ),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Container(
                      padding: const EdgeInsets.all(26),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.94),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: brand.primary.withValues(alpha: 0.14),
                            blurRadius: 34,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (logoAssetPath != null) ...[
                            Image.asset(
                              logoAssetPath!,
                              height: 74,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                            const SizedBox(height: 18),
                          ],
                          Container(
                            width: 78,
                            height: 78,
                            decoration: BoxDecoration(
                              color: brand.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, size: 42, color: brand.primary),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: brand.ink,
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            message,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF71809A),
                              height: 1.7,
                            ),
                          ),
                          if (primaryLabel != null && onPrimary != null) ...[
                            const SizedBox(height: 22),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: brand.primary,
                                  minimumSize: const Size.fromHeight(52),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(17),
                                  ),
                                ),
                                onPressed: onPrimary,
                                icon: const Icon(Icons.refresh_rounded),
                                label: Text(primaryLabel!),
                              ),
                            ),
                          ],
                          if (secondaryLabel != null && onSecondary != null)
                            TextButton(
                              onPressed: onSecondary,
                              child: Text(secondaryLabel!),
                            ),
                        ],
                      ),
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
