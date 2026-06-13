#!/bin/bash
# Tech Tool - macOS launcher (IBM Granite model). Double-click to start.
# Same as Start-Tech-Tool-Mac.command, but runs on the faster IBM Granite 4.0
# H-Tiny model (a Mixture-of-Experts model that generates ~2.5x faster on CPU-only
# machines than the default Qwen model). It just selects the model, then hands off
# to the normal launcher, so any fixes there apply here too.
export TECHTOOL_MODEL=granite
exec "$(cd "$(dirname "$0")" && pwd)/Start-Tech-Tool-Mac.command"
