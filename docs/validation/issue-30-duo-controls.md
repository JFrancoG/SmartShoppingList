# iPhone Duo control layout — issue #30

Status: the owner accepts the focused iPhone Duo adaptation and final manual-entry label on September 26 and authorizes commit, push, PR, merge, issue closure and branch removal. Implementation is based on `dde27b7` (PR #29). Definitive Git/CI outcomes are recorded in [issue #30](https://github.com/JFrancoG/SmartShoppingList/issues/30) and its linked PR after delivery.

Owner follow-up: the owner reports that the app looks correct in every tested posture, then accepts the shorter **Add manually / Añadir a mano** label. The label keeps its existing Dynamic Type wrapping and native accessibility label, and the updated app compiled and launched in Xcode 27.2 on Duo. This acceptance does not separately establish the untested cases listed below.

## Scope and design

Related Add controls and the purchase count/action receive a shared local layout that avoids active division regions. Product rows remain continuous. The manual Add prompt is included. Buttons use the width proposed to their block (60%, 75% with accessibility text); the native Apple button is capped at 375 pt. Existing iPhone landscape configuration changes are retained. Tabs, store selection, sheets, alerts, tasks and observable models keep their identity and behavior.

The Form viewport supplies all active `ReservedRegion` frames, including their existing margins. Viewport and group frames measured in the same global coordinate space convert these rectangles into the group's local space; this is coordinate conversion, not fixed screen positioning. A single RTL reflection matches SwiftUI Layout placement. An anchored scroll offset prevents horizontal-fold displacement from pinning tall content during scrolling, while content growth and natural row movement still update placement. iOS 27.1 APIs are guarded; the runtime minimum remains 27.0. Building requires Xcode/SDK 27.1 or later.

The first implementation cached horizontal local queries and could miss growing content. Independent review caught that case. A subsequent simulator check found an 82-point origin mismatch with a named Form coordinate space. The final version measures both origins in the common global space and converts locally. Neither temporary logging nor fixture launch arguments remain in the project.

## Automated and build evidence

- Xcode 27.1, iPhone Duo / iOS 27.1, Fast: **140 Swift Testing functions / 245 device executions passed**, zero failures, skips or xcresult runtime warnings. Native result summary verified with `xcresulttool`.
- Result: `~/Library/Developer/Xcode/DerivedData/SmartShoppingList-cnedcbvxlssppmejeutmxomopscm/Logs/Test/Test-SmartShoppingList-2026.09.26_21-45-17-+0200.xcresult`.
- Fast ran before the final geometry conversion/refinement. Domain logic remained unchanged; subsequent native builds and the focused runtime checks below cover the final layout.
- Final Xcode 27.1 native build/install/launch succeeded. Build log manifest `987B58B5-4607-48F7-B4CD-03320577EDCB.xcactivitylog` reports zero warnings/errors; the complete log contains the accepted EXC-002 App Intents metadata-extraction diagnostic, without Swift compiler warnings. Final incremental build `99FE668D-4AAA-45B4-A637-6172479C8267.xcactivitylog` also reports zero warnings/errors.
- Xcode 27.2 also built the final source successfully for the Duo destination. Full native build log `56030B8C-D5D2-49B6-8FEE-196D91D232F7.xcactivitylog` contains no Swift compiler warning or error; its only warning text is the already accepted EXC-002 App Intents metadata-extraction diagnostic. Using Xcode 27.1 for the runtime checks is not a requirement to downgrade from 27.2.
- Independent iOS/SwiftUI/accessibility and changed-source review completed. Ten Swift files inspected by the source-style audit; no outstanding findings. `git diff --check` passes.
- No new unit tests mirror the layout implementation. Existing Fast tests exercise surrounding recovery and state contracts; native interaction is the evidence for layout.
- Design-system validation passes: 64 pairs × 4 modes and 21 assets × 4 variants; palette values are unchanged.
- Delivery checkpoint: the final label and geometry built again in Xcode 27.2 after the changed-Swift style audit; native log `4D6A276A-6FC8-42B0-A095-DF80F4232D09.xcactivitylog` contains only accepted EXC-002. Contract validation passes 16 operations, 40 positive examples and 20 negative requests. Fast evidence above is reused without claiming a new run; the final layout and label have native/owner acceptance.

The iOS 27.1 beta simulator console emits system accessibility bundle/category diagnostics. These are not first-party compiler warnings or failures reported by the test result, and a clean build does not assert a silent beta runtime.

## Focused runtime checks

Executed through native Xcode and the existing Device Hub Duo, using `-shopping-ai-validation`. This fixture substitutes speech, interpretation, credentials and HTTP with local doubles. It does not access the microphone, Apple authorization or production writes.

| Check | Observed result |
|---|---|
| Open / exterior, ES normal text | Initial prompt and microphone remain usable |
| Book, ES normal text | Prompt/micro and purchase count/action move together into the trailing region; products remain full-width |
| Dictation fixture: book → horizontal → exterior | Listening state, transcript and stop/cancel survive; finishing produces the expected Confirm/Edit proposal |
| Horizontal, normal text | The whole dictation group fits above the fold without unnecessary displacement |
| Horizontal, AX5 | The growing dictation group moves below the fold; scrolling reaches both full stop/cancel labels |
| Native draft editor, rotation | Editor stays open with Yogurts / 6 / Aldi unchanged and uses the native region placement |
| Shop, selection then rotation | One selected product remains selected; count and action retain 1 |
| Shop, horizontal AX5 and scroll | Full count and multiline Confirm purchase action remain reachable |

Temporary text size was restored to its original value (3); appearance remained Light. The shared scheme is restored without fixture arguments. The final app was launched with its ordinary services and original account/group (Case). No real item was submitted or purchased during these checks.

Local capture of book-mode Shop: `/tmp/ssl-duo-book-shopping.png` (fixture evidence, not a physical-device capture).

## Acceptance boundaries

Not yet demonstrated for this unit: a complete EN posture pass; software-keyboard appearance/reflow (the editor field focused, but the software keyboard was not shown); transitions during real microphone capture or real Foundation Models interpretation; a prepared signed-out Apple button rendered at the former problematic width; a fresh launch on iOS 27.0; complete VoiceOver focus behavior across postures. Static availability guards, existing localization and previous physical acceptance do not replace these checks.

The owner authorizes closing this bounded UI unit with these evidence limits recorded. The checks above remain part of the broader MVP/release validation; their absence is not reported as a pass or as a newly discovered defect. NavigationSplitView and a universal voice-entry redesign remain out of scope.
