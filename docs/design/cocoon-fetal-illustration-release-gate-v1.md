# CocoonMate fetal illustration release gate v1

Status: required before any week illustration is published

The previous asset pack is not approved for production use. It repeats a small
number of silhouettes across many weeks and therefore does not meet the stated
morphology, proportion, posture, or scale requirements.

## Dating and terminology invariants

- Gestational age is counted from the first day of the last menstrual period,
  approximately two weeks before conception in a typical cycle.
- Weeks 1–2 must not show an embryo or fetus. The visual may explain cycle
  preparation/ovulation only when approved clinical content supports it.
- Week 3 may use a non-anthropomorphic fertilization/cell-development visual.
- Week 4 may use a blastocyst/implantation visual.
- The embryonic stage runs approximately through the end of week 8.
- The label and fetal visual system starts around gestational week 9.
- A single late-gestation baby render must never be reused at smaller scale for
  early weeks.

Medical references:

- Cleveland Clinic fetal development overview, medically reviewed 2024-03-19:
  https://my.clevelandclinic.org/health/articles/7247-fetal-development-stages-of-growth
- NHS week-by-week pregnancy guide:
  https://www.nhs.uk/best-start-in-life/pregnancy/week-by-week-guide-to-pregnancy/
- UNSW Embryology Carnegie stages:
  https://embryology.med.unsw.edu.au/embryology/index.php/Carnegie_Stages

## Required manifest per asset

Each illustration requires:

- gestational week or approved week range;
- stage name and terminology;
- crown-rump or crown-heel measurement basis where relevant;
- morphology notes;
- head-to-body proportion notes;
- limb and digit development notes;
- skin/fat/vernix/lanugo notes where relevant;
- posture and position choice, marked as illustrative rather than predictive;
- source references and access dates;
- medical reviewer reference, review date, and next review date;
- art version and checksum;
- accessible description in Persian and English.

## Visual requirements

- Premium soft editorial 3D or painted realism; calm, non-frightening lighting.
- Anatomical silhouette and proportions must survive at the in-app crop size.
- Umbilical cord, placenta, membranes, and uterine context appear only when they
  teach something relevant and have been reviewed.
- Variation in posture may prevent visual repetition, but the app must never
  imply that the illustration predicts the user's actual fetal position.
- No anatomy labels are baked into the bitmap. Localized labels belong to the UI.
- No text, watermark, competitor composition, or copied medical plate.

## Release checks

1. Design review at hero and compact crops.
2. Clinical review against the manifest, not appearance alone.
3. Persian and English accessible descriptions.
4. Small/large phone and text scale QA.
5. Lazy-load and missing-asset fallback QA.
6. Reduced-motion behavior for layered or animated variants.
7. Final reviewer approval stored with the content version.

Until all checks pass, CocoonMate uses the abstract `CocoonGrowthOrb` and does
not make an anatomy claim.
