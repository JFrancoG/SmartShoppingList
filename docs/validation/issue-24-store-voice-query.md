# In-app store voice query — issue #24

Status: implementation published at `97b0997`, based on `dbd9ca5`. The owner confirms matching-store opening and the no-match notice, and authorizes PR, merge, issue closure and branch cleanup on September 25. The definitive Git delivery is recorded in issue #24. No backend change or deployment. Remaining physical accessibility/edge-case checks are retained in phase 3 of the implementation plan and are not reported as passed.

## Current behavior and owner feedback

The owner reported that the first version worked, but rejected its separate screen and additional selection step because voice must be faster than manually selecting a store. That feedback supersedes the earlier modal design and its physical acceptance does not establish acceptance of the revised UI.

In Shop, the microphone immediately starts capture and reveals an editable transcript within the existing store section. Finish loads the unique matching store automatically. Multiple matches offer a choice inline; an unknown or unintelligible query shows one inline message. The chosen store and real pending list remain visible. There is no voice sheet or additional confirmation for one match.

Speech uses the effective ES/EN app locale. Matching uses real group stores, normalized whole words and documented ES/EN phrases; it does not infer aliases or create data. Users can correct the transcript and search or use the existing Store selector. Apple Intelligence and optional Siri/App Intents #10 are not required.

Cancel hides the transient query. Backgrounding/leaving Shop invalidates automatic completion and stops capture. Signing out/session invalidation also clears the transcript/store snapshot. A group change closes the query. Normal mutation/editor/invitation actions are unavailable while capturing; every sheet entry also centrally interrupts capture, including recovery buttons that reopen an existing editor. Late finish cannot navigate after cancellation or interfere with a later capture. Silent speech cannot reuse earlier typed text as fresh recognition.

## Automated evidence — September 25

- Xcode MCP, SmartShoppingList scheme, iPhone 17 simulator / iOS 27.2, Fast plan: **108 functions / 189 executions passed**, zero failures, skips or runtime warnings. Native result verified independently with `xcresulttool`.
- Seven MCP `No result` entries are Integration/untagged tests excluded from Fast, not seven failed Fast tests.
- Cases include ES/EN matching, accents, branches, unknown/partial words, edited transcripts, silent capture, final transcript, errors, cancellation, late completion, automatic unique opening, ambiguity/no match without navigation, sign-out and sheet reopening during capture, real pending-row lookup, preserved per-store checks/uncertain envelopes and stale-match rejection.
- Existing Fast regressions included. No live backend, microphone or physical accessibility claims from automated tests.
- Build succeeded for iPhone 11. Full build logs retain accepted EXC-002 App Intents metadata diagnostics; no first-party Swift warnings. Original destination restored after simulator checks.

Native result: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunAllTests/Test-SmartShoppingList-2026.09.25_21-50-28-+0200.xcresult`.

Independent iOS and SwiftUI reviews completed. Findings about capture after sign-out and direct editor recovery were corrected and regression-tested. Source style audit covered ten changed/new Swift files with no remaining findings. Thirteen bilingual catalogue additions remain; unused modal-only strings were removed, existing entries preserved.

## Visual evidence and limits

Focused inline controls rendered/inspected on iPhone 18 Pro / iOS 27.2: EN Large (21:50:03), ES XXX Large (21:50:43) and ES AX5 (21:49:18). Visible controls and text wrap without overlap. At AX5 part of the message is below the fold; its scrolling/VoiceOver behavior still needs the physical check. Preview artifacts are in Xcode's temporary `RenderPreview` directory. They use deterministic local data and do not evidence real speech.

## Owner confirmation — September 25

The owner confirms the revised inline query works: a match opens the correct store's list; no match displays a notice. This confirms those two functional cases. The latest reply does not identify device/language, nor explicitly confirm VoiceOver, ambiguous branches, silence or lifecycle interruptions; those are not inferred from it. The accepted match/no-match cases do not need repeating solely to fill the checklist.

## Remaining physical checks for phase 3

1. Shop → microphone. Confirm capture starts immediately and the transcript appears on the same screen. Say “Show me the list for Aldi”, then Finish. A unique match must open that store's real pending list directly. Repeat “Dame la lista de Aldi” when validating Spanish.
2. Try an unknown store or remain silent. Confirm one inline explanation and usable correction/manual selector. If several branches match, choose one inline.
3. Cancel or background during capture once. Check no late navigation in the next query. Sign out or reopen an existing editor during capture only if convenient; deterministic tests cover cancellation at these boundaries.
4. With VoiceOver active before starting, check the error announcement and logical focus after successful selection/cancellation. At maximum text size, scroll to the full message and activate any offered choice.
5. Preserve a checked product while querying another store; return and verify its check remains. No purchase confirmation is needed to test this query.

The accepted #22 edit/cancel matrix and the confirmed match/no-match cases are not repeated solely for bookkeeping. The owner authorized full delivery of #24 on September 25. This functional delivery does not close phase 3, the milestone or final MVP validation; outstanding physical checks above remain visible in that plan.
