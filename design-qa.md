# Design QA

## Evidence

- Source visual truth: `C:\Users\gqy17\.codex\generated_images\019fc6f7-dba1-77e2-923a-0a2e12d211c6\exec-03ab33cd-08fe-4e22-8ab4-a7728eb7df8e.png`
- Final implementation screenshot: `C:\Users\gqy17\.codex\visualizations\2026\08\03\019fc6f7-dba1-77e2-923a-0a2e12d211c6\implementation-home-v3.png`
- Combined comparison: `C:\Users\gqy17\.codex\visualizations\2026\08\03\019fc6f7-dba1-77e2-923a-0a2e12d211c6\design-qa-side-by-side-v3.png`
- Device and viewport: realme RMX3562, portrait, 1080 x 2412 physical pixels; Android reports a 360 x 756 dp app viewport at device scale factor 3.
- Source pixels: 853 x 1844, representing the selected portrait concept.
- Implementation pixels: 1080 x 2412, including the real device status and navigation bars.
- Density normalization: source resized by width from 853 x 1844 to 1080 x 2335 and placed on a 1080 x 2412 ivory canvas; implementation retained at native 1080 x 2412. The side-by-side comparison uses equal pixel widths.
- State: initial listening screen, light theme, Hangzhou.

## Full-view comparison evidence

The final combined image compares the selected concept and the real-device capture in one input. Both retain the same hierarchy and proportions: quiet Hangzhou landscape, compact brand/location row, centered display title, dominant circular listening action, overlapping 20-second pill, and three symbolic listening hints near the lower edge. The app remains legible with the phone's status and navigation bars present.

## Focused region comparison evidence

Focused checks were made on the four fidelity-sensitive regions visible in the combined image:

- Typography: Alibaba PuHuiTi 3.0 regular and semibold render consistently across display and UI text; the previous phone calligraphy font no longer leaks into the app.
- Listening control: final diameter, forest color, solid microphone, ivory halo, timing pill, and outer rings align with the selected composition.
- Header and scenery: brand/location alignment and the generated pagoda/bamboo crop remain clear without competing with the hero.
- Listening hints: leaf, muted sound, and car symbols now match the concept and use the same separators and green token.

## Required fidelity surfaces

- Fonts and typography: passed. Family, weights, sizes, line height, wrapping, and hierarchy are coherent; no clipping or fallback-font mismatch is visible.
- Spacing and layout rhythm: passed. Major vertical anchors and control proportions align after the second iteration; no viewport overflow hides the primary action or hints.
- Colors and visual tokens: passed. Warm ivory, forest green, gray-green supporting text, subtle borders, and low elevation remain consistent with the source.
- Image quality and asset fidelity: passed. The background is a dedicated 853 x 1844 raster asset derived from the selected art direction, not a code-drawn approximation; crop and sharpness hold on the 1080-pixel device.
- Copy and content: passed. The initial screen uses the selected concise copy and symbolic hints; removed diagnostic and explanatory text remains available through debug-only long-press actions or later workflow states.

## Findings

No actionable P0, P1, or P2 findings remain.

- [P3] The source concept contains a faint generated texture inside the green microphone circle, while the implementation uses a stable flat Material surface. This is acceptable because the flat control improves state consistency and contrast during recording.
- [P3] The real-device capture includes the user's Android status/navigation bars and uses a 360 x 756 dp viewport instead of the concept's approximate 390 x 844 frame. Safe-area behavior is correct and the composition remains intact.

## Comparison history

- Iteration 0: implementation capture was blocked by the Oplus streamed-install verifier. Fixed by using the authorized USB `pm install` path from `/data/local/tmp`; no device security setting was disabled.
- Iteration 1 evidence: `implementation-home-v1.png`. Findings: listening hint used an ear instead of a leaf, separators were absent, and the microphone halo was too weak. Fixes: leaf icon, vertical separators, solid microphone, and ivory halo.
- Iteration 2 evidence: `implementation-home-v2.png` and `design-qa-side-by-side-v2.png`. Finding: the primary green action was moderately smaller than the selected source. Fixes: increased control, halo, progress ring, icon, and label proportions; slightly reduced header/location type; softened the background.
- Iteration 3 evidence: `implementation-home-v3.png` and `design-qa-side-by-side-v3.png`. Post-fix comparison has no actionable P0/P1/P2 differences.

## Functional verification

- `flutter analyze --no-pub`: passed after final visual iteration.
- Flutter tests: 31 passed.
- Android arm64 debug APK: built and installed successfully via USB `pm install`.
- Android arm64 release APK: built successfully at 77.1 MB after removing the stale dev-only plugin entry from the ignored local generated registrant.
- Primary interaction: microphone permission granted, recording started, live timer/progress rendered, and 20-second recording completed to a WAV result without a crash.
- Screen behavior: `mHoldScreenWindow` pointed to `MainActivity` during recording, confirming keep-screen-on; the flag is cleared on stop/cancel/destroy.
- Logs checked: `recording_started` and `recording_completed` present; no fatal exception observed.
- Browser console: not applicable to this native Flutter/Android implementation.

final result: passed
