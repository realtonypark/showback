# Third-party notices

Showback downloads the following pinned assets during installation. It performs synthesis locally and does not offer voice cloning.

- **Pocket TTS Rust runtime and model configuration:** Kyutai, MIT license. Runtime release v4.0.1 (asset version 3.3.0). https://github.com/kyutai-labs/pocket-tts . The runtime's license is installed at `Assets/notices/pocket-runtime.txt`. The bundled English 18M configuration replaces remote asset references with local paths; its architecture settings are unchanged.
- **Pocket TTS non-cloning English 18M weights and tokenizer:** Kyutai, CC BY 4.0. https://huggingface.co/kyutai/pocket-tts-without-voice-cloning . Revision `a7056f505a4a8ca72d8b5fb1440071d6f1a35739`. Weights are unmodified. https://creativecommons.org/licenses/by/4.0/
- **Alba voice:** performed by Alba MacKenna, CC BY 4.0. The installed embedding is fetched from https://huggingface.co/kyutai/pocket-tts-without-voice-cloning/blob/a7056f505a4a8ca72d8b5fb1440071d6f1a35739/languages/english_18m_2026-10/embeddings/alba.safetensors (revision `a7056f505a4a8ca72d8b5fb1440071d6f1a35739`), as pinned in `assets.json`. The voice performer attribution comes from https://huggingface.co/kyutai/tts-voices/tree/main/alba-mackenna . The installed precomputed embedding is distributed unmodified. https://creativecommons.org/licenses/by/4.0/
- **Marius and Javert voices:** Unmute Voice Donation Project, CC0. Source recordings `voice-donations/Selfie.wav` and `voice-donations/Butter.wav`. https://huggingface.co/kyutai/tts-voices . Precomputed embeddings are distributed unmodified. https://creativecommons.org/publicdomain/zero/1.0/
- **agent-desktop v1.0.2 and macOS helper:** Vercel, Inc. and contributors, Apache 2.0. https://github.com/vercel-labs/agent-desktop . See the bundled Apache license.

The production app does not contain Scrawl source code. The development-only `Tests/Fixtures/VirtualDisplay.swift` is adapted from Scrawl, copyright (c) 2026 Kit Langton, under the MIT license in `Tests/Fixtures/SCRAWL-LICENSE`. Scrawl informed the separation of capture, media timing, visual presentation, and readable results.
