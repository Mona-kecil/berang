#!/bin/bash
# Records the website's audio and word timings through Berang's own cleanup and voices.
# usage: site/tools/build-audio.sh [--kitten-only]
# Writes site/public/assets/{hero,hard}/<voice>.m4a and site/public/assets/timing.js. --kitten-only skips the
# Phonon voices, which keep their audio and the timings already in timing.js.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
kitten_only=false
case "${1:-}" in
  "") ;;
  --kitten-only) kitten_only=true ;;
  *) echo "usage: site/tools/build-audio.sh [--kitten-only]" >&2; exit 2 ;;
esac

# The voices of each text, in the order the page shows them.
hero=(kitten/eleanor)
hard=(kitten/eleanor kitten/grace kitten/danny Maeve Edwin "Old Mortlake")

cd "$root/mac"
swift build -c release --product berang-say
bin="$(swift build -c release --show-bin-path)"

# MLX reads its compiled Metal shaders from beside the program, and swift build doesn't make them.
if [ ! -f "$bin/mlx.metallib" ]; then
  shaders="$(find /Applications/Berang.app -name default.metallib 2>/dev/null | head -1)"
  [ -n "$shaders" ] || { echo "No Metal shaders: install Berang, or copy its default.metallib to $bin/mlx.metallib." >&2; exit 1; }
  cp "$shaders" "$bin/mlx.metallib"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

record() {
  local name="$1"; shift
  local voices=()
  for voice in "$@"; do
    if ! $kitten_only || [[ "$voice" == kitten/* ]]; then voices+=("$voice"); fi
  done
  "$bin/berang-say" site "$root/site/text/$name.txt" "$work/$name" "${voices[@]}"
}

record hero "${hero[@]}"
record hard "${hard[@]}"

python3 -I - "$root/site/public/assets" "$work" "$kitten_only" <<'PY'
import json, shutil, sys
from pathlib import Path

assets, work, kitten_only = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3] == "true"
display = {
    "hero": ["eleanor"],
    "hard": ["eleanor", "grace", "danny", "Maeve", "Edwin", "Old Mortlake"],
}
old = json.loads((assets / "timing.js").read_text().removeprefix("window.TIMING = ").rstrip().removesuffix(";"))

timing = {}
for name, voices in display.items():
    fresh = work / name / "timing.json"
    if not fresh.exists():
        raise SystemExit(f"{name}: nothing was recorded")
    entry = json.loads(fresh.read_text())
    kept = old[name]["voices"]
    if kitten_only and (old[name]["say"] != entry["say"] or old[name]["source"] != entry["source"]):
        raise SystemExit(f"{name}: the text's words changed, so the Phonon timings in timing.js no longer fit. Run without --kitten-only.")
    pool = {**(kept if kitten_only else {}), **entry["voices"]}
    missing = [v for v in voices if v not in pool]
    if missing:
        raise SystemExit(f"{name}: no timings for {', '.join(missing)}")
    entry["voices"] = {v: pool[v] for v in voices}
    timing[name] = entry

for name in display:
    for clip in (work / name).glob("*.m4a"):
        shutil.copy(clip, assets / name / clip.name)
(assets / "timing.js").write_text("window.TIMING = " + json.dumps(timing, separators=(",", ":")) + ";\n")
PY
