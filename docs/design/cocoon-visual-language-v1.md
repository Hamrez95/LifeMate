# CocoonMate visual language v1

Status: implemented foundation

## Product expression

CocoonMate is an editorial care companion, not a medical dashboard, content
feed, marketplace, or social network. The first viewport answers three
questions in order:

1. Where am I in the pregnancy?
2. What is useful today?
3. What deserves attention next?

The emotional moment is intentionally singular. One warm gestational hero is
followed by a quiet timeline and editorial content. Repeated equal-weight cards,
mascots, decorative gradients, and permanent fruit comparisons are excluded.

## Benchmark synthesis

- Pregnancy+ demonstrates the value of a strong weekly visual and a simple
  timeline, but the visual must not displace care actions.
- Flo demonstrates concise weekly orientation, symptom entry, and partner
  continuity, but community and content do not belong at the same hierarchy as
  personal care.
- Ovia demonstrates useful milestone, symptom, and appointment continuity, but
  dense tracking must be progressively disclosed.
- BabyCenter and What to Expect demonstrate long-term pregnancy-to-parenting
  continuity, but Home must not become an article feed.
- Impo, Herlife, and Gahvareh validate Persian-first stage guidance and the
  value of a local, supportive tone. CocoonMate differentiates through shared
  LifeMate records, scoped consent, calm density, and explicit clinical review.

Product references:

- https://flo.health/product-tour/pregnancy-app
- https://www.oviahealth.com/pregnancy-app/
- https://apps.apple.com/us/app/pregnancy-tracker-app/id505864483
- https://impo.app/
- https://herlifeapp.com/
- https://gahvare.net/

## Foundation tokens

- Canvas: `#FFF8F2`
- Raised surface: `#FFFCF9`
- Warm pregnancy surface: `#FFF0E6`
- Primary coral: `#C75C62`
- Accessible coral action: `#A8434D`
- Secondary lilac: `#8765B4`
- Success/care sage: `#39785F` on `#E7F2EA`
- Information sky: `#39769C` on `#E8F3FA`
- Text ink: `#263248`
- Supporting text: `#667085`
- Hairline: `#E9DED6`

Coral identifies the current pregnancy moment and the primary action. It is not
the default background for every surface. Sage identifies routine care and
completed/safe states. Sky identifies information and offline cache status.
Warnings always include text and iconography; color is never the only signal.

## Layout and type

- Mobile content width: one column, 20dp inline page padding.
- Section rhythm: 30–32dp; related item rhythm: 12–18dp.
- Minimum action height: 48dp.
- Hero responds to width and text scale: horizontal on common phones, stacked
  below 340dp or when the scaled body size exceeds 22px.
- Persian and English share semantic hierarchy, not hard-coded mirrored
  positioning. All spacing that carries meaning uses directional primitives.
- Important numbers use the display style and locale digits. Week/day is derived
  from canonical dating at presentation time and is never persisted as mutable
  UI state.
- Persian and mixed-script copy uses the bundled, OFL-licensed Vazirmatn family
  in regular, medium, semibold, and bold weights. Hosts receive it through the
  package-qualified `CocoonVazirmatn` family rather than depending on a device
  font.

## Motion

Only progress, state change, completion, and navigation may animate. Motion is
short, interruptible, and must respect the platform reduced-motion setting.
The foundation deliberately ships without decorative looping animation.

## Offline and unavailable states

Owner-only cached pregnancy data remains useful offline. A quiet sky strip says
that the screen is showing the last protected device copy and offers retry.
Without a protected owner snapshot, the product shows an honest reconnect gate.
Cached information is never presented as current server authority.

## Implemented components

- `CocoonScaffold`
- `CocoonAppBar`
- `CocoonSurface`
- `CocoonPrimaryCta`
- `CocoonStatusBadge`
- `CocoonLoadingState`
- `CocoonEmptyState`
- `CocoonBrandMark`
- `CocoonStatePage`
- `CocoonOfflineStrip`
- `CocoonPagePadding`
- `CocoonSectionHeading`
- `CocoonGrowthOrb`
- `CocoonPregnancyHome`
- `CocoonWeekDetail`

The growth orb is explicitly abstract. It communicates progress and protection
without pretending to be a fetal anatomy illustration.

## Identity and assets

The code-native CocoonMate mark uses nested protective forms and a sage center.
It is intentionally legible without a literal fetus, heart, or gendered pink
cue. The Android preparation script generates legacy, adaptive, Android 13
monochrome, notification-safe, and launch/splash variants from the same mark.

The onboarding protected-growth illustration is non-clinical and approved for
the welcome surface. Every bundled asset is described in `assets/manifest.json`
with placement, aspect ratio, RTL safety, source status, and medical review
status. The fetal development series remains blocked behind the existing
medical release gate; `CocoonGrowthOrb` remains the honest production fallback.

## Visual regression baseline

Stable goldens cover the brand mark, Persian onboarding at 390×844, Persian Home
at 390×844, and English Week Detail at 390×844. Responsive widget matrices also
exercise 320×568 and text scale 1.5. These checks complement, rather than replace,
physical-device review.
