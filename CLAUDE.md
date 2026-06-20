# Design System — Glass Bead (Dark)

Narra is dark-only. Every floating control reads as a 3D liquid-glass bead: refractive edges, glossy top highlight, soft bottom caustic, faint chromatic fringe. Surfaces inside content panels are flat sibling slabs of the same glass. Do not improvise values — use the tokens in `Sources/Narra/Design/DesignTokens.swift`.

## Core principles

1. **Glass is the language of the app, not just chrome.** HUD pills, home panel slabs, settings cards — all share the same dark-glass family. Backgrounds are warm charcoal, never pure black.
2. **The HUD drops from the top edge.** The recording / processing / reviewing states render the same `NotchBead`, a capsule that hangs from underneath the system notch (or top-center on non-notch displays). The bead enters collapsed (~48pt) and stretches to the screen's notch width — plus an extra ~88pt for the cancel/confirm disks during recording and reviewing. Content fades in only after the width animation lands.
3. **Glass on glass is forbidden.** A bead, slab, or card may never sit directly on another. Editorial content surfaces are flat (`GlassCard` with one `.glassEffect` layer); the bead does not nest other glass.
4. **Soft, organic edges.** Capsules for HUD beads. `RoundedRectangle(cornerRadius:, style: .continuous)` for everything else.
5. **Motion is liquid but quiet.** Spring (response 0.55, damping 0.78) for the bead open. Ease-out 200ms for state swaps. No bounce-heavy springs.

## Tokens

| Token | Where |
|---|---|
| `Palette.canvas` (`#14130F`) | App background / window fill. |
| `Palette.surface`, `surfaceAlt` | Inside glass cards — used sparingly; the glass material does most of the work. |
| `Palette.border` | Hairline strokes (`Color.white.opacity(0.12)` in dark resolution). |
| `Palette.ink`, `inkSoft`, `muted` | Text. Body = `ink`, secondary = `muted`. |
| `Palette.redBg`/`redInk`, `greenBg`/`greenInk`, etc. | Semantic accents only (record indicator, accept/discard, warnings). |
| `Typography.serif` | Editorial headings only (home panel title, large display text). `.system(design: .serif)`. |
| `Typography.sans` | All UI body / labels / buttons. |
| `Typography.mono` | Code, keystrokes, pipeline status. |
| `CornerRadius.sm/md/lg/xl/pill` | `4 / 6 / 8 / 12 / 16`. |
| `Spacing.xs…xxl` | `4 / 8 / 12 / 16 / 20 / 24`. |
| `Motion.entry / snappy / microFade` | Use `entry` for first-paint reveals, `snappy` for state changes. |

## Components

```swift
// Floating HUD (recording / processing / reviewing) — hangs from the notch
NotchBead(viewModel: viewModel)
    .frame(maxWidth: .infinity, maxHeight: .infinity)

// Content surfaces (home panel, settings cards)
GlassCard(padding: Spacing.lg, radius: CornerRadius.xl) {
    VStack { ... }
}

// Native macOS 26 glass material
.glassEffect(.regular, in: Capsule(style: .continuous))
.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
```

Fallback path (macOS < 26) uses `.ultraThinMaterial` + a black tint overlay; defined inside `GlassBead` / `GlassCard`. Call sites should never branch on availability themselves.

## What not to do

- No gradients anywhere except the HUD waveform, which samples `Iridescence.stops` to match the app icon's refractive edge. No purple-cyan accent gradients, no `BrandGradient` — deleted.
- No light theme. `.preferredColorScheme(.dark)` is set at scene level.
- No glass for `KeyRecorderView` input chip or other recessed inputs — those use a flat `Color.white.opacity(0.05)` fill with a 1pt white-12% border.
- No emoji in code, source comments, or UI strings. SF Symbols only.
- No drop shadows on flat editorial surfaces. Shadows belong to the bead (which is supposed to look like it's floating in the room).
