# Design references

The owner selected the Stitch designs as Vital's visual target. Use the saved PNGs and HTML when implementing or reviewing the Flutter interface.

**Current snapshot:** [20 October 2026](stitch/2026-10-20/README.md), including full-resolution screen images, unchanged HTML exports, generated design tokens and supporting assets. The snapshot separates visible screens from hidden earlier variants.

## Contribution workflow

1. Find the relevant current screen in the snapshot index. Read its PNG, HTML and metadata together; canvas labels and generated export titles sometimes differ.
2. Match its layout, spacing, typography, colours, geometry and glass placement using shadcn_flutter controls and selected liquid_glass_widgets surfaces.
3. Compare the Flutter screen against the reference at the same logical width and colour mode. Check large text, touch targets, contrast, keyboard behaviour and opaque/reduced-motion settings as well.
4. Include the reference path and comparison screenshots in UI pull requests. Explain necessary platform or accessibility adaptations. Obtain owner agreement for intentional visual redesigns.

Use the single-user product specification for behaviour, record integrity, privacy and app wording. Generated sample data, charts, medical claims, suggested features or dependency choices do not override those requirements. The generated design-system document is source evidence, not a new product specification.

Where a screen or theme has no reference, reuse the established components and identify the gap. Hidden earlier variants are historical material, not the default target. Keep archived originals unchanged; store owner-selected revisions as a new dated snapshot and update this pointer.

## Files and provenance

PNG and HTML pairs, screen IDs, original dimensions, canvas visibility and SHA-256 hashes are committed so contributors can inspect the reference without a Stitch account. The asset archive preserves downloadable dependencies for reference; runtime adoption still follows Vital's dependency and licence requirements.

Original HTML retains its external links and scripts. Inspect it as source; use the PNG as the stable rendering reference. API keys and authentication headers are excluded from this archive.
