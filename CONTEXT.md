# Showback

Showback lets an agent show and explain its output by using the computer while narrating a demonstration.

## Language

**Demo**:
A walkthrough of actual software behavior, with narration and visible interaction.
_Avoid_: proof (a demonstration alone does not establish correctness)

**Demo script**:
The agent-authored instructions for a demo, including what to show, do, and say.

**Demo run**:
One execution of a demo script against actual software.

**Recording bundle**:
The video, audio, screenshots, and accompanying information saved from a demo run.

**Showback Cloud**:
Showback-provided speech synthesis that the user can access without supplying a provider key.

**OpenRouter BYOK**:
Speech synthesis accessed through the user's own OpenRouter API key.

**Local speech model**:
A speech-synthesis model downloaded with the user's consent and run on their computer.

**Voice**:
The speaking identity selected for narration within a speech model or service.
_Avoid_: model (the synthesis model and the speaking identity are separate choices)
