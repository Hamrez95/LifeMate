# CocoonMate asset policy

`manifest.json` is the release inventory for every bundled visual and font.
An asset is not production-approved merely because a file exists. Medical
illustrations also require the clinical evidence and reviewer fields in
`docs/design/cocoon-fetal-illustration-release-gate-v1.md`.

Rules:

- use original LifeMate/CocoonMate artwork only;
- no competitor artwork or copied medical illustrations;
- do not encode PHI or Person identifiers in filenames;
- keep critical status meaning accessible without color alone;
- keep clinical/content bundles in the approved versioned content path.

The current fetal runtime remains the abstract `CocoonGrowthOrb`. It makes no
anatomy or fetal-position claim. The generated onboarding visual is explicitly
non-clinical and may not be repurposed as a fetal-development image.

Vazirmatn 33.003 is bundled from the official project release under SIL OFL
1.1; the unmodified license text is stored beside the font files.
