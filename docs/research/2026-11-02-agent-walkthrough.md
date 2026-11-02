# Agent walkthrough review

The reviewed Pi session started on October 29, 2026; the Showback interaction occurred on November 1. Evidence comes from the matching session JSONL, messages 462–570, and the retained final recording bundle. Times below are elapsed wall time, including agent reasoning and tool overhead.

## Observed sequence

| Stage | Evidence | Result |
| --- | --- | --- |
| Discover and prepare | Messages 463–504, about 5 minutes | Separate setup reads, browser navigation/focus recovery, an unsupported find flag, broad ancestor/offscreen matches, and scrolling errors. |
| First run | 513–515 | All ten narration clips prepared; duplicate point target stopped the run. `--mute` also prevented the requested live voice. |
| Second run | 520–525 | Scrollbar write requested 0.45; the app returned 0.44990548. Verification failed despite movement. |
| Third run | 529–532 | Earlier scrolling was not reset; the first target was outside capture. |
| Fourth run | 539–542 | A later navigation link had scrolled outside capture. |
| Fifth run | 543–554 | Tested focus plus Page Down/Home and reset the start. The ten-scene walkthrough completed. |
| Delivery | 555–570 | Agent revealed raw `recording.mp4` and claimed audio. After the user reported missing voice/highlights, it inspected and delivered exported `demo.mp4`. |

The completed run took about 14 minutes from the request. Correct file delivery took about 25 minutes, including a user response gap. The successful video is about 80 seconds. These timings do not isolate speech or export CPU cost.

## Causes and changes

- **Preparation had no clear completion criteria.** The skill now batches setup reads, qualifies unique targets, checks uncertain navigation, and restores the starting state before presentation. Schema validation explicitly says it does not check the app.
- **Accessibility presence was confused with visible content.** The skill separates those checks and gives explicit reveal/scroll guidance. Runtime inspection also found that `scroll-to` presented offscreen bounds before it could reveal the target; it now scrolls once, resolves fresh bounds, then presents them.
- **Errors did not identify the repair location.** Runtime failures now name the preparation stage or scene/action/condition; ambiguous-target errors include the selector. No automatic action retry was added.
- **The output contract encouraged file guessing.** The CLI now prints the finished MP4 and summary paths; metadata includes an absolute `video` path only after finalization. Failed/cancelled media is labeled partial. The skill distinguishes the exported video from raw source and checks the actual deliverable.
- **Live presentation intent was lost.** The skill uses audible narration for walkthroughs; quiet/test runs retain `--mute`.
- **Generated output triggered unrelated repository hooks.** The skill keeps generated material outside the application repository and uses a scratch working directory when those hooks scan it.

## Forward tests

Two fresh Pi sessions used a local landing-page fixture on a virtual display, the installed skill/CLI, and the user's configured default model. Extensions and MCP were disabled to isolate Showback. Tests used `--mute`; they did not play speakers or capture a physical display.

The first trial stopped before recording after clicking a state-changing preview button during preparation and finding no reset route. That exposed another instruction gap: preparation now rehearses uncertain navigation while keeping state-changing actions for the recording unless a reset route is known. The skill also includes common session/window/target commands and initial window focus. Both trials requested `showback run --help`; its erroneous failure exit was reproduced and fixed with a CLI regression.

The second trial produced a completed five-scene recording on its first recorded run. It read summary/metadata, inspected frames from the exported video, verified the resulting button through a fresh accessibility query, checked audio, and delivered the actual `demo.mp4`. Independent inspection confirmed the exported highlight and H.264/AAC tracks. It took about 232 seconds including preparation, a 32-second presentation, export, and verification. This simpler fixture is not a controlled speed comparison with the original page.

## Limits

The scrolling precision error belongs to agent-desktop's verification contract. Showback continues to preserve that error and unsafe-delivery disposition; it does not turn approximate values into success or replay the action. The skill steers agents toward a tested semantic reveal or focused page-scroll route.

Indistinguishable duplicate targets still need another unique route or a reported targeting limit. No indexed/coordinate selector or implicit display capture was added.

The automated browser regression checks ambiguous-target diagnostics, offscreen reveal/click, expected/absent outcomes, final-video identity, audio, and blue highlights. A separate read-only skill review exercises preparation, delivery, and unsafe-delivery recovery decisions. The Pi trial establishes one successful controlled workflow; it does not establish that every agent, app, or model will follow the skill or that all target apps implement scrolling reliably.
