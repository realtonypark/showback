# Speech and settings

`Sources/ShowbackCore/Speech.swift` owns local synthesis and audio validation. `Assets.swift` and `Resources/assets.json` own the pinned asset identities and voice registry. `SettingsStore.swift` owns the saved voice; `Settings.swift` displays those values.

- Install one curated English model and its eligible preset voices with Showback. Do not download during a run or call an inference provider.
- Prepare all narration before desktop actions. Fail on missing assets, invalid configuration, failed synthesis, invalid samples, or silent output.
- Use local, quoted model/tokenizer paths and local preset embeddings. Do not expose voice cloning or accept remote voice URLs.
- Validate model and preset licenses separately. Preserve attribution; noncommercial-only voices do not ship.
- Narration clips are 24 kHz mono. Their actual sample count determines duration.
- Settings does not silently change an unavailable voice during a run. A selected voice must exist in the curated registry.
- Keep voice IDs and asset identities in the registry; do not duplicate the list in UI or CLI code.

Run `SpeechTests`, `AssetsTests`, and a real offline synthesis check after changing model/configuration code. UI previews play only when the user clicks Preview. During automated QA, use muted playback and inspect file audio.
