# Implementation decisions

These decisions were made while executing the approved Showback design. The whole-project review found one cleanup defect; its regression failed before the fix and passed after it. No minor findings were deferred.

| Decision | Reason | Cost or limit |
| --- | --- | --- |
| Use the existing local main branch | Required by the user and approved plan | No worktree isolation; commits stay local. |
| Continue implementation without repeated plan approval | The user authorized the build/test/fix loop | Keep all work within the approved design. |
| Start a fresh desktop session before observations | A reused host retained stale virtual-display inventory | Small session startup cost per demo. |
| Own one live/export pointer renderer | agent-desktop exposes no stable overlay window identity for narrow capture | Showback maintains that small renderer. |
| Use synchronous native entry with asynchronous delegate tasks | Nesting the native event loop under an async entry deadlocked | Native lifecycle is explicit in Application/Entry. |
| Use actual capture pixel scale and scalesToFit | A fixed 2× assumption produced empty canvas and displaced pointers | Window resize ends the demo; rerun at the new size. |
| Require explicit display capture for scene window/app switches | Multi-app demos need a declared capture scope | Explicit display capture can contain other visible content on that display. |
| Quote local model/tokenizer paths as JSON/YAML strings | Unquoted # and colon broke valid filesystem paths | No user-facing limit; special-character paths are tested. |
| Remove command-completion click ripples | Measured 145 ms late; desktop command return is not the input-delivery timestamp | No decorative click ring; pointer travel and target outlines remain. |
