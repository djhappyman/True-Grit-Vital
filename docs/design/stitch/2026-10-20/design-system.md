---
name: Warm Clinical Minimalism
colors:
  surface: '#f9f9f8'
  surface-dim: '#d9dad9'
  surface-bright: '#f9f9f8'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f3f4f3'
  surface-container: '#edeeed'
  surface-container-high: '#e7e8e7'
  surface-container-highest: '#e1e3e2'
  on-surface: '#191c1c'
  on-surface-variant: '#3f4946'
  inverse-surface: '#2e3131'
  inverse-on-surface: '#f0f1f0'
  outline: '#6f7976'
  outline-variant: '#bfc9c5'
  surface-tint: '#29685e'
  primary: '#00443b'
  on-primary: '#ffffff'
  primary-container: '#1a5c52'
  on-primary-container: '#93d2c5'
  inverse-primary: '#94d2c6'
  secondary: '#52625f'
  on-secondary: '#ffffff'
  secondary-container: '#d2e3df'
  on-secondary-container: '#566663'
  tertiary: '#5a3100'
  on-tertiary: '#ffffff'
  tertiary-container: '#7b4500'
  on-tertiary-container: '#ffb771'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#afefe1'
  primary-fixed-dim: '#94d2c6'
  on-primary-fixed: '#00201b'
  on-primary-fixed-variant: '#065046'
  secondary-fixed: '#d5e6e2'
  secondary-fixed-dim: '#b9cac6'
  on-secondary-fixed: '#0f1e1c'
  on-secondary-fixed-variant: '#3a4a47'
  tertiary-fixed: '#ffdcbf'
  tertiary-fixed-dim: '#ffb873'
  on-tertiary-fixed: '#2d1600'
  on-tertiary-fixed-variant: '#6a3b00'
  background: '#f9f9f8'
  on-background: '#191c1c'
  surface-variant: '#e1e3e2'
  ink: '#182725'
  text-secondary: '#5B6B68'
  border-crisp: '#E2E6E4'
  dark-canvas: '#101715'
  dark-surface: '#192420'
  dark-accent: '#96D1BB'
  dark-text-primary: '#E8F0EC'
  dark-text-secondary: '#A7B6AE'
  dark-border: '#23342E'
  destructive: '#C24134'
  destructive-dark: '#F87171'
typography:
  headline-xl:
    fontFamily: Noto Sans
    fontSize: 36px
    fontWeight: '600'
    lineHeight: 44px
    letterSpacing: -0.02em
  headline-xl-mobile:
    fontFamily: Noto Sans
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 34px
    letterSpacing: -0.015em
  headline-lg:
    fontFamily: Noto Sans
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Noto Sans
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.005em
  title-md:
    fontFamily: Noto Sans
    fontSize: 17px
    fontWeight: '600'
    lineHeight: 24px
    letterSpacing: 0em
  body-lg:
    fontFamily: Noto Sans
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: 0em
  body-md:
    fontFamily: Noto Sans
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: 0em
  body-sm:
    fontFamily: Noto Sans
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
    letterSpacing: 0.01em
  metric-lg:
    fontFamily: Noto Sans
    fontSize: 32px
    fontWeight: '500'
    lineHeight: 38px
    letterSpacing: -0.02em
  metric-md:
    fontFamily: Noto Sans
    fontSize: 20px
    fontWeight: '500'
    lineHeight: 26px
    letterSpacing: -0.01em
  label-md:
    fontFamily: Noto Sans
    fontSize: 13px
    fontWeight: '500'
    lineHeight: 18px
    letterSpacing: 0.01em
  label-sm:
    fontFamily: Noto Sans
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
    letterSpacing: 0.02em
rounded:
  sm: 0.5rem
  DEFAULT: 1rem
  md: 1.5rem
  lg: 2rem
  xl: 3rem
  full: 9999px
spacing:
  gutter: 1rem
  margin: 1rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

This design system delivers an intimate, restorative, and sovereign routine-tracking environment. It frames supplement and medication management not as an anxiety-inducing obligation or gamified streak, but as an intentional, objective act of self-care.

### Core Tenets
- **Warm Restraint:** Organic, botanical undertones soften clinical precision. The experience is welcoming, tranquil, and serene.
- **Sovereign & Local-First:** Free from coercive mechanics, high-pressure notifications, or noisy gamification. The visual tone remains calm, confident, and grounded.
- **Precision Typography & Hierarchy:** High typographic clarity ensures critical dosage, unit, and schedule markers are legible at a glance.
- **Adaptive Geometry:** Architectural containers with generous smooth radii (16px and 24px) are juxtaposed against fluid, full-pill action elements to ensure tactile accessibility and effortless touch navigation.

### Design Style: Warm Tactile Glass & Pill Flow
The interface blends `shadcn_flutter` compositional clarity with ambient material layering:
- **Foundational Surfaces:** Crisp structural containment paired with calm tinted neutrals.
- **Translucency & Blurs:** Navigation anchors and elevated dialogs leverage 16px frosted glass layering alongside solid high-contrast fallbacks for accessibility modes.
- **Touch Ergonomics:** Strictly phone-first with guaranteed 48×48dp interactive boundaries and fully rounded pill contours for all primary triggers.

## Colors

The color system combines deep botanical ink, soft mineral stone, and evergreen therapeutic accents to provide clinical dependability without hospital coldness.

### Light Mode Architecture
- **Canvas Base (`#F6F7F6`):** Soft warm limestone background eliminating glare during early morning or bedtime routines.
- **Surface Opaque (`#FFFFFF`):** High-clarity containers for substantive cards, panels, and input fields.
- **Surface Translucent (`rgba(255, 255, 255, 0.76)`):** Frosted ambient glass with backdrop blur (16px) and low-contrast rim strokes (`rgba(0, 0, 0, 0.06)`).
- **Ink Primary (`#182725`):** Deep botanical ink ensuring WCAG AAA legibility against canvas and card levels.
- **Text Secondary (`#5B6B68`):** Muted slate teal for metadata, timestamp suffixes, and dosage units.
- **Primary Teal Accent (`#1A5C52`):** Saturated deep evergreen teal driving active states, primary buttons, and affirmative checks.
- **Border Crisp (`#E2E6E4`):** Low-contrast structural lines providing gentle separation without harsh dividers.

### Dark Mode Architecture
- **Dark Canvas (`#101715`):** Deep green-charcoal canvas engineered for zero eye fatigue in dark rooms.
- **Dark Graphite Surface (`#192420`):** Subtle elevated background for cards and bottom sheets.
- **Dark Surface Translucent (`rgba(25, 36, 32, 0.78)`):** Smoked glass paired with highlight edge stroke (`rgba(255, 255, 255, 0.08)`).
- **Luminous Mint Accent (`#96D1BB`):** Muted therapeutic mint delivering high-contrast, glare-free legibility.
- **Dark Ink Foreground (`#101715`):** High-contrast text layered inside mint buttons and affirmative badges.
- **Dark Primary Text (`#E8F0EC`) & Secondary Text (`#A7B6AE`):** Soft luminous mineral chalk and celadon mist.
- **Dark Border (`#23342E`):** Perimeter edge separator.

### System Feedback & Semantic Tones
- **Destructive (`#C24134` light / `#F87171` dark):** Earthy crimson reserved for missed critical doses, contraindication warnings, or irreversible deletions.
- **Caution / Schedule Shift (`#C87B24` light / `#FBBF24` dark):** Warm amber signaling interval spacing alerts or pending intakes.

## Typography

The type system is powered exclusively by **Noto Sans** for its universal clarity, broad multilingual glyph repertoire, and clinical authority.

### Tabular Numbers & Dynamic Feeds
All timestamps, interval timers, pill counts, and dosage quantities must activate OpenType tabular figures:
`font-feature-settings: "tnum" 1, "cv05" 1;`
This prevents layout jitter during real-time schedule updates, intake countdowns, or counter steppers.

### Application Rules
- **Display & Headlines:** Used strictly for date anchors ("Today, Oct 24") and view titles. Mobile screens scale `headline-xl` down to `headline-xl-mobile` to maintain single-line layout integrity.
- **Metrics (`metric-lg`, `metric-md`):** Reserved for numerical values, dosages (e.g. `100 mg`, `2 drops`), and historical adherence statistics.
- **Labels:** Set with medium weights and slight positive tracking to ensure fast glanceability on pill buttons, action triggers, and filter chips.

## Layout & Spacing

Layout adheres to a phone-first single-column structure designed for one-handed operation.

### Spatial Rhythm
- **Canvas Margins:** Fixed 16px (`1rem`) horizontal padding on mobile viewports (<480px).
- **Responsive Max-Width:** On tablets and desktops, content remains anchored in a centered `640px` maximum column (`margin: 0 auto`), preventing excessive tracking list widths and preserving thumb reach.
- **Vertical Spacing:** Modules adhere strictly to an 8px base rhythm (`space-sm`, `space-md`, `space-lg`, `space-xl`). Single-column card stacks keep attention focused on chronological order.

### Touch Ergonomics
All actionable nodes—pill buttons, dosage steppers, list check triggers, and modal dismiss targets—enforce a bounding box of at least **48×48dp**, regardless of whether their internal visual asset is 16px or 24px.

## Elevation & Depth

Visual depth is achieved through delicate surface tinting, fine-line rim borders, and frosted glass filtration rather than dark, muddy drop shadows.

### Surface Tiers
- **Tier 0 (Canvas Base):** Ground color (`#F6F7F6` light / `#101715` dark). Flat, non-elevated viewport background.
- **Tier 1 (Cards, Modules & Containers):** Solid resting cards (`#FFFFFF` light / `#192420` dark) paired with a 1px border (`#E2E6E4` light / `#23342E` dark). Zero drop shadow at rest.
- **Tier 2 (Interactive Floating Docks):** Bottom navigation bars, floating quick-log docks, and dosage toolbars utilize frosted glass:
  - *Light Glass:* `rgba(255, 255, 255, 0.76)`, `backdrop-filter: blur(16px)`, border `1px solid rgba(0, 0, 0, 0.06)`, shadow `0 8px 32px rgba(0, 0, 0, 0.04)`.
  - *Dark Glass:* `rgba(25, 36, 32, 0.78)`, `backdrop-filter: blur(16px)`, border `1px solid rgba(255, 255, 255, 0.08)`, shadow `0 8px 32px rgba(0, 0, 0, 0.35)`.
  - *Accessibility Variant:* Fall back to solid Tier 1 backgrounds if reduced-transparency preferences are detected.
- **Tier 3 (Modals, Dialogs & Sheets):** Smooth 24px rounded surfaces elevated with a diffuse soft shadow (`0 20px 48px rgba(0, 0, 0, 0.08)` in light mode; `0 24px 64px rgba(0, 0, 0, 0.55)` in dark mode) and framed with a crisp boundary outline.

## Shapes

The geometric signature combines generous, smooth radii on architectural enclosures with fully rounded pill profiles on all interactive touchpoints.

### Architectural Containers (Smooth Radii: 16px & 24px)
- **Standard Cards, Panels & Modules:** Standardized on `1rem` (16px / `ROUND_SIXTEEN`).
- **Modals, Dialogs & Bottom Sheet Caps:** Enforced at `1.5rem` (24px / `ROUND_TWENTY_FOUR`).
- **Input Fields & Textarea Frames:** Form containers and search fields utilize `1rem` (16px / `ROUND_SIXTEEN`) for a soft, approachable frame.
- **Filter Segment Enclosures & Grouped Card Wrappers:** Bound by `1rem` (16px / `ROUND_SIXTEEN`).

### Interactive Elements & Action Triggers (Fully Rounded Pills: 9999px)
- **Buttons (Primary, Secondary, Ghost, Destructive):** Fully rounded pill geometry (`rounded-full` / `border-radius: 9999px`).
- **Badges & Status Tags:** Pill geometry (`border-radius: 9999px`).
- **Chips, Category Filters & Intake Toggles:** Pill geometry (`border-radius: 9999px`).
- **Floating Action Buttons & Check Triggers:** Circular/pill geometry (`border-radius: 9999px`).
- **Segmented Control Sliders & Micro Tabs:** Pill geometry (`border-radius: 9999px`).

## Components

Components follow `shadcn_flutter` compositional primitives, styled with smooth rounded frames and fully rounded pill action elements.

### Buttons & Action Triggers
- **Geometry:** Height 48px, horizontal padding 24px, fully rounded pill (`border-radius: 9999px`).
- **Primary Pill:** Background in Deep Teal (`#1A5C52` light / `#96D1BB` dark), text in Foreground (`#FFFFFF` light / `#101715` dark), font `label-md`. Active touch triggers a calm `transform: scale(0.98)` spring with 0.92 opacity.
- **Secondary Pill:** Opaque surface (`#FFFFFF` light / `#192420` dark) with 1px border (`#E2E6E4` light / `#23342E` dark), text in Primary Ink.
- **Ghost Pill:** Borderless, transparent fill, text in Text Secondary (`#5B6B68` / `#A7B6AE`), shifting to Primary Ink on pressed state.
- **Destructive Pill:** Background tinted red surface or clear with Destructive border (`#C24134` / `#F87171`), text in Destructive.

### Cards & Container Panels
- **Anatomy:** Corner radius strictly 16px (`ROUND_SIXTEEN`). Opaque base surface, 1px border (`#E2E6E4` / `#23342E`), padding 16px.
- **Substance Dose Card:** Contains scheduled intake time (`metric-md`), medication/supplement name (`title-md`), dosage specification (`body-md`), and a trailing circular direct-log trigger button (48×48dp hit area, `border-radius: 9999px`).
- **Nested Inner Modules:** Inside 16px cards, internal sub-panels use 12px or 16px corner radii to maintain concentric harmony.

### Chips, Filter Pills & Badges
- **Status Badges & Chips:** Fully rounded pills (`border-radius: 9999px`), height 32px, padding 0 14px, typography `label-sm`.
- **Intake State Indicators:** 
  - *Taken:* Primary Accent pill fill with white text.
  - *Scheduled:* Hairline bordered pill with secondary text.
  - *Skipped/Deferred:* Muted amber tint pill with amber text.

### Form Inputs & Steppers
- **Text Inputs:** Height 48px, smooth 16px corner radius (`ROUND_SIXTEEN`), padding 0 16px, framed with 1px structural border (`#E2E6E4` / `#23342E`). Focused state transitions border to Primary Teal Accent without an outer bloom.
- **Dosage Stepper:** Enclosed in a 16px container or pill shell containing decrement and increment buttons (each 48×48dp, `border-radius: 9999px`) flanking tabular numeric dosage text (`metric-md`).

### Modals, Dialogs & Sheets
- **Modals & Dialogs:** 24px corner radius (`ROUND_TWENTY_FOUR`), solid background with 1px border and Tier 3 diffuse elevation. Inner action buttons use fully rounded pill shapes docked at the base.
- **Bottom Sheets:** Top-left and top-right radii set to 24px (`ROUND_TWENTY_FOUR`). Top handle indicator is an 8-wide pill (`border-radius: 9999px`).

### Navigation Bar
- **Docked Translucent Island or Bar:** Frosted glass backing with 16px blur (solid Tier 1 fallback for accessibility).
- **Tab Triggers:** 48dp minimum touch bounds. Active tabs highlight with a subtle pill backplate (`border-radius: 9999px`, `rgba(26, 92, 82, 0.08)` light / `rgba(150, 209, 187, 0.12)` dark) holding the Lucide icon and label.