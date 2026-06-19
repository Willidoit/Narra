# whisper.cpp bundled model

`WhisperCppTranscriptionService` reads `ggml-base.en.bin` from this directory
via `Bundle.module`. The binary is intentionally not checked into git — it is
~142 MB.

Run once from the repo root:

    Scripts/fetch-whisper-model.sh

That drops `ggml-base.en.bin` here. After that the next `swift build` bundles
it into Narra.app and offline dictation works with no further setup.
