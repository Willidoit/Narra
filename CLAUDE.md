# Design System — Liquid Glass (Dark Mode)

This app uses a dark-mode liquid glass design language inspired by Apple's Liquid Glass material. Every UI element must follow these rules. Do not improvise values.

## Core Principles

1. **Glass is for navigation, not decoration.** Apply glass to toolbars, tab bars, sidebars, floating controls, and contextual menus. Content areas stay solid.
2. **Never stack glass on glass.** A glass surface must never sit directly on another glass surface — it kills legibility and tanks performance.
3. **Soft, organic edges everywhere.** No sharp corners. Every container uses continuous corner radius (`RoundedRectangle(cornerRadius:, style: .continuous)`).
4. **Motion should feel like water.** Transitions are fluid and spring-based. Nothing snaps. Nothing bounces hard.
5. **Dark mode is the default.** All tokens below are dark-mode values. Light mode is not in scope.

## Glass Material

Use Apple's native glass effect APIs (iOS 26+ / macOS Tahoe+):

```swift
// PRIMARY: Use .glassEffect for true liquid glass
.glassEffect(.regular.interactive, in: .capsule)
.glassEffect(.regular, in: RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))

// FALLBACK (iOS 25 and earlier): Use system materials
.background(.ultraThinMaterial)
.background(.thinMaterial)

