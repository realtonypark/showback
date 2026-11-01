# Run results

`Sources/ShowbackCore/Runner.swift` owns scene sequencing and outcome gating. `RunBundle.swift` owns durable result files and final status.

- Preflight, then prepare speech, then interact. Each scene completes its actions, check, and speech before the next begins.
- Recorded narration is authored content; checks are observed facts. Never infer correctness from a success sentence.
- Stop on failed checks, unsafe desktop delivery, synthesis failure, capture failure, or cancellation. Do not retry or roll back application actions automatically.
- Preserve source media and partial results. A failed/cancelled run stays failed/cancelled even when its partial video is usable.
- A recorded run cannot complete successfully without a finalized MP4. Keep `.incomplete` when media did not finalize.
- Existing bundles are never overwritten. Cleanup finishes after the first stop signal. A second Ctrl+C or termination signal forces exit and can leave source media unfinalized; the incomplete marker remains.
- Save screenshots only for scenes with actions/checks; narration over a static screen does not create another frame.

Run `RunBundleTests`, `scripts/check-cli.py`, and `scripts/check-runs.py`. The latter uses and closes only the controlled native fixture; restart it before another run.
