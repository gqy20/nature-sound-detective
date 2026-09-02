# Recognition Motion Design QA

Date: 2026-09-02

## Scope

- Recording acoustic-field animation
- Recognition reveal screen
- Recognition-to-habitat soundscape handoff

## Compared artifacts

- Visual target: `combined-ink-ecology-result-v001.png`
- Widget-rendered implementation: `implementation-result-v001.png`
- Built APK: `mobile/build/app/outputs/flutter-apk/app-debug.apk`

## Automated verification

- `make analyze`: passed
- `make test`: passed, 180 tests
- `make build`: passed
- Habitat aggregation test: same-park bird and insect records included; unrelated wetland frog record excluded
- Navigation test: structured park/area/habitat focus reaches the comprehensive soundscape without a species-only filter

## Visual review

- P0: none found.
- P1: Android runtime review is not complete because `adb devices -l` returned no connected device. Installation, motion timing, system-font rendering, and real asset decoding could not be inspected on Android.
- P2: The Flutter test renderer exported the implemented layout, but its default font lacks Chinese glyphs and the captured frame did not decode the species photo. The capture is sufficient to inspect spacing and hierarchy, but not sufficient to approve typography, imagery, or final polish against the selected visual target.

## Follow-up required

Connect an authorized Android device or emulator, install the current debug APK, then capture and compare these states at 430×950 or the target device resolution:

1. Active recording with low, medium, and high RMS input.
2. The first 1.2 seconds of the recognition reveal.
3. The settled recognition result, including the recommendation card below the fold.
4. The comprehensive habitat soundscape reached from the result.

final result: blocked
