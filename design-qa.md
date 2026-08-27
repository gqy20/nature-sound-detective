# Design QA

## Scope

- Reference: `C:\Users\gqy17\.codex\generated_images\019ff430-2aa2-78c1-bbfc-7c8199dcdeed\exec-f0c22039-a0f8-4946-972c-ee819475e9ca.png`
- Implementation: `deploy/modelscope/app.py` + `deploy/modelscope/theme.css` + `deploy/modelscope/instrument.css`
- Primary viewport: 1487 × 1058
- Responsive viewport: 390 × 844
- Runtime under test: Gradio 6.17.3 (the version pinned by the ModelScope bundle)

## Visual comparison

- Combined reference/implementation image: `tmp/design-audit/reference-vs-implementation-final.png`
- Final desktop capture: `tmp/design-audit/implementation-desktop-final.png`
- Alignment follow-up reference: `C:\Users\gqy17\AppData\Local\Temp\codex-clipboard-446234d3-2b09-4fba-9b85-930b42584250.png` (2350 × 921)
- Alignment follow-up desktop capture: `tmp/design-audit/mic-wave-alignment-final.png` (1280 × 720 CSS px, device scale 1)
- Alignment follow-up mobile capture: `tmp/design-audit/mic-wave-alignment-mobile.png` (390 × 844 CSS px, device scale 1)
- Focused before/after comparison: `tmp/design-audit/mic-wave-alignment-review.png`

## Issues found and resolved

| Severity | Finding | Resolution |
| --- | --- | --- |
| P1 | The initial input console consumed most of the viewport and pushed the upload/action region too low. | Replaced the flexible console row with a fixed instrument-height row and aligned the remaining controls to the start. |
| P1 | Upload headline and note text inherited the old dark-panel foreground color and had insufficient contrast on ivory. | Added explicit Android-derived ink/forest text colors. |
| P1 | The previous quality card was absolutely positioned over the primary analysis action. | Returned it to normal document flow and kept the action fully visible. |
| P2 | The first pass left too much unused space compared with the selected reference. | Added field context metadata and a compact three-step investigation guide in the observation rail. |
| P2 | The main Gradio container retained a 1280 px cap, making the composition visibly narrower than the reference. | Applied the layout width and padding to the actual Gradio 6 `main.app` container. |
| P2 | Mobile navigation wrapped onto an isolated second line. | Removed non-core desktop navigation below 760 px and retained the functional Record/Results tabs. |
| P2 | The desktop console label overlapped the clear control on narrow mobile screens. | Hid that secondary label below 760 px. |
| P2 | The microphone glyph sat 20 px above the circular control center, while the acoustic asset's waveform baseline rendered above that center axis. | Positioned the microphone/stop glyph at the exact 50%/50% button center and compensated for the source asset's 34%-height waveform baseline with desktop/mobile focal-point offsets. Post-fix measurements put the panel, ring, button, and glyph centers at the same `391.99px` desktop axis. |

## Alignment follow-up comparison history

- Earlier evidence: the supplied console screenshots showed the microphone glyph high inside its circle and the waveform baseline on a separate horizontal track.
- Fix: changed the microphone and stop pseudo-icon positions to `top: 50%` with two-axis centering; changed the desktop acoustic background Y focal point to `calc(50% + 37px)` and the mobile focal point to `calc(50% + 13px)`.
- Post-fix evidence: `tmp/design-audit/mic-wave-alignment-final.png` and `tmp/design-audit/mic-wave-alignment-mobile.png` show a shared horizontal axis. Browser geometry confirms panel center, ring center, and record-button center all equal `391.9921875px` in the desktop check.
- Focused region comparison was required because the issue concerned optical alignment inside the primary recording console; `tmp/design-audit/mic-wave-alignment-review.png` records the supplied state and corrected state together.

## Live waveform follow-up

- User reference: `C:\Users\gqy17\AppData\Local\Temp\codex-clipboard-446234d3-2b09-4fba-9b85-930b42584250.png` (2350 × 921).
- Final implementation capture: `tmp/design-audit/live-waveform-desktop-final.png` (1280 × 720 CSS px, device scale 1).
- State: microphone idle state with the simulated waiting trace; real microphone capture is connected through the same canvas via `AnalyserNode.getByteTimeDomainData()` when Gradio requests an audio stream.
- [P2 resolved] The generated raster waveform looked visually heavy and could not respond to the recording. It has been removed from the visible console and replaced by a canvas signal renderer.
- [P2 resolved] The circular control still felt too far right. Its desktop inset changed from 34 px to 20 px; the compact mobile inset is 8 px so the focus ring is not clipped.
- Post-fix geometry: panel, ring, and canvas baselines are all `391.9921875px` at 1280 × 720. The canvas measures 612.20 × 270 CSS px.
- Motion evidence: two focused canvas captures taken 650 ms apart differ, confirming that the idle trace animates. Browser console errors: none.
- Live behavior: idle uses a restrained low-amplitude trace; recording switches the label to `LIVE INPUT · REAL-TIME WAVEFORM` and draws actual time-domain microphone samples with smoothing and a subtle signal glow.
- Permission note: browser microphone permission was not accepted during automated QA, so no personal microphone audio was captured or transmitted.

## Calculated microphone centering follow-up

- User evidence: `C:\Users\gqy17\AppData\Local\Temp\codex-clipboard-af563d9d-3586-4822-852d-5293dc9ee064.png` (582 × 609).
- Implementation evidence: `tmp/design-audit/user-current-centered-after.png` (768 × 860 CSS capture at device pixel ratio 2).
- Focused comparison: `tmp/design-audit/mic-centering-calculated-comparison.png`.
- [P2 resolved] Box-model measurements initially showed the button and ring centers aligned, but pixel-component analysis of the rendered white microphone found its visual centroid at `159.5px` against a ring center of `150px`.
- Root cause: the masked microphone pseudo-element's rasterized visual content was 9.5 CSS px to the right of its computed element center in the user's 768 px / DPR 2 preview environment.
- Calculated fix: applied `left: calc(50% - 10px)` to microphone and stop glyphs only. The circle and “开始聆听” label were not moved.
- Post-fix evidence: white-pixel connected-component analysis reports microphone centroids of `149.57px` and `149.52px`, leaving a maximum `0.5px` optical difference from the `150px` ring center.

## Functional checks

- Custom drag/click upload surface opens the native Gradio file chooser.
- Generated 8-second WAV fixture uploads successfully.
- Audio preflight reports duration and size correctly.
- Analyze action enables after a valid upload.
- Analyze action updates the quality and observation result regions.
- Mobile Record/Results tabs switch the visible panel.
- Desktop and mobile layouts remain within a single viewport without document scrolling.
- Contract suite: 15 passed.
- Python compilation and ModelScope artifact assembly: passed.
- Desktop and mobile microphone/waveform alignment: passed.
- Idle waveform animation and microphone-stream hook: passed.
- Browser console errors after the alignment fix: none.

## Remaining differences accepted

- The implementation preserves the current product logo and existing Gradio audio/player behavior rather than copying decorative controls from the visual reference.
- Location and environment remain explanatory metadata rather than new editable product fields, keeping this refactor within the existing feature scope.

final result: passed
