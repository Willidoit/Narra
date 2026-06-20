# Narra

Native macOS voice-to-text with intelligent post-processing. Press a global hotkey, talk, get clean prose pasted into the focused app. Built in Swift + SwiftUI for macOS 15+, designed for macOS 26's Liquid Glass.

## What it does

- **Push-to-talk capture** via a global hotkey, anywhere in macOS.
- **Multi-provider transcription.** Cloud: Groq, OpenAI, Deepgram, ElevenLabs. Local: WhisperKit, Apple Speech, Parakeet (MLX). Pick per-engine from the Models settings, swap models from a dropdown.
- **Post-processing** that strips fillers ("um", "uh", "you know") and resolves self-corrections — "I'll head to the store, oh wait, the mall" → "the mall". Mid-sentence correction markers (`scratch that`, `no wait`, `oh wait`, `wait no`, `let me rephrase`) drop everything before them. Runs on Grok (cloud) or a local MLX fallback.
- **Auto-paste** the cleaned text into whatever app had focus.
- **Glass HUD** that opens horizontally from a 80pt bead to a 320pt pill showing record / process / review state.

## Architecture

```
Mic ─▶ AudioCaptureManager ─▶ TranscriptionService ─▶ PostProcessingService ─▶ Paste
                                  ▲                       ▲
                                  │                       └─ Grok | local MLX
                                  │
                                  └─ Groq | OpenAI | Deepgram | ElevenLabs
                                  └─ WhisperKit | Apple Speech | Parakeet
```

Source layout (`Sources/Narra/`):

- `Audio/` — `AVAudioEngine` capture and rolling buffer.
- `Services/Transcription/` — Groq + WhisperKit backends behind a protocol.
- `Services/PostProcessing/` — Grok + local LLM backends behind a protocol.
- `Services/Orchestrator/` — wires capture → STT → cleanup → paste.
- `Services/KeychainService.swift` — API key storage in the macOS Keychain.
- `Services/KeybindingManager.swift` — global shortcut registration.
- `Views/` — `SettingsView`, `KeyRecorderView`.
- `Design/DesignTokens.swift` — the Glass Bead dark design system (see `CLAUDE.md`).
- `LiquidGlassView.swift`, `WaveformView.swift`, `ContentView.swift` — HUD.

## Requirements

- macOS 15 (Sequoia) or later. Liquid Glass styling activates on macOS 26.
- Xcode 16 / Swift 6.
- Microphone + Accessibility permissions (the latter for paste-into-frontmost-app).
- A Groq and/or xAI Grok API key for the cloud path. Local path needs no keys.

## Build

```bash
# Swift Package
swift build -c release

# Or open the Xcode project
open Narra.xcodeproj
```

A prebuilt `Narra.dmg` / `NarraV2.dmg` ships at the repo root.

## Configure

Open Settings from the menu bar item:

1. Paste your Groq API key (used for streaming Whisper) and/or Grok key (cleanup).
2. Record a global shortcut in the key recorder.
3. Pick cloud or local for each stage.

Keys are stored in the macOS Keychain, not on disk.

## Design system

Dark only, glass-on-glass forbidden, capsules for HUD beads, continuous rounded rectangles for cards. Use the tokens in `Sources/Narra/Design/DesignTokens.swift` — don't improvise values. Full rules in `CLAUDE.md`.

## Repo layout

```
Narra.xcodeproj/        Xcode project
Package.swift           SwiftPM manifest
Sources/Narra/          App source
Tests/NarraTests/       Unit tests
docs/                   Plans and notes
tools/                  Build / packaging helpers
Narra.dmg, NarraV2.dmg  Prebuilt installers
```

## License

No license file yet — all rights reserved by the author until one is added.
