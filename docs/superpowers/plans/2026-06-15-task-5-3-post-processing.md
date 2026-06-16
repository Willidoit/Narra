# Task 5.3 Post-Processing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic local filler/correction cleanup plus service wrappers for the post-processing pipeline.

**Architecture:** Keep the existing `LocalCorrectionFilter` as the first deterministic pass, extend it with a small context-aware cleanup pipeline, then wrap it in two services: one local-only and one async refinement service that can fall back to local output. Tests cover the pipeline entry points rather than internal helpers.

**Tech Stack:** Swift 5.9, XCTest, Swift Package Manager.

---

### Task 1: Extend the local filter behavior

**Files:**
- Modify: `Sources/NarraV2/Services/PostProcessing/LocalCorrectionFilter.swift`
- Test: `Tests/NarraV2Tests/LocalCorrectionFilterTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
func testFillerWordsAreRemovedWhenUsedAsStandaloneFillers()
func testLikeIsPreservedWhenUsedSemantically()
func testIMeanAndRatherTriggerCorrectionPrefixRemoval()
func testRestatementDedupesNearDuplicateContextToCleanerVersion()
```

- [ ] **Step 2: Run the focused test file and verify it fails**

Run: `swift test --filter LocalCorrectionFilterTests`

Expected: failures showing the missing behavior.

- [ ] **Step 3: Implement the local filter updates**

```swift
public func apply(_ request: PostProcessingRequest) -> PostProcessingResult
```

- [ ] **Step 4: Re-run the focused tests and verify they pass**

Run: `swift test --filter LocalCorrectionFilterTests`

Expected: pass.

### Task 2: Add service wrappers

**Files:**
- Create: `Sources/NarraV2/Services/PostProcessing/LocalPostProcessingService.swift`
- Create: `Sources/NarraV2/Services/PostProcessing/GrokPostProcessingService.swift`
- Test: `Tests/NarraV2Tests/PostProcessingServiceTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
func testLocalPostProcessingServiceUsesLocalFilter()
func testGrokPostProcessingServiceFallsBackWhenRefinementThrows()
func testGrokPostProcessingServiceUsesRefinementOutput()
```

- [ ] **Step 2: Run the focused test file and verify it fails**

Run: `swift test --filter PostProcessingServiceTests`

- [ ] **Step 3: Implement the services**

```swift
public struct LocalPostProcessingService: PostProcessingService
public struct GrokPostProcessingService: PostProcessingService
```

- [ ] **Step 4: Re-run the focused tests and verify they pass**

Run: `swift test --filter PostProcessingServiceTests`

### Task 3: Verify the package as a whole

**Files:**
- No new files

- [ ] **Step 1: Run `swift test`**
- [ ] **Step 2: Run `swiftc -typecheck` with a writable module cache path if needed**
- [ ] **Step 3: Commit the changes**

```bash
git add Sources Tests docs/superpowers/plans/2026-06-15-task-5-3-post-processing.md
git commit -m "feat: add smart post-processing pipeline"
```
