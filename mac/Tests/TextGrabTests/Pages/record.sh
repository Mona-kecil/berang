#!/bin/sh
# Records saved pages: opens each page, saves its accessibility tree to <name>.json.lzma, and writes the
# text read back from that copy to <name>.md. Review the .md diffs before committing them.
# usage: Tests/TextGrabTests/Pages/record.sh [name ...]   (default: every page in pages.tsv)
# Needs Accessibility access for the terminal. Chrome pages use a throwaway profile.
set -e
cd "$(dirname "$0")"
here=$PWD
(cd ../../.. && swift build -c release -q)
bin=$(cd ../../.. && swift build -c release --show-bin-path)
profile=$(mktemp -d)
trap 'rm -rf "$profile"' EXIT

tail -n +2 pages.tsv | while IFS="$(printf '\t')" read -r name source url license; do
  if [ $# -gt 0 ] && ! echo " $* " | grep -q " $name "; then continue; fi
  title=
  case $source in
    webkit)
      "$bin/page-viewer" "$url" > "$profile/viewer.out" 2>&1 &
      pid=$!
      for _ in $(seq 60); do grep -q -e loaded -e failed "$profile/viewer.out" && break; sleep 0.5; done ;;
    chrome)
      open -na "Google Chrome" --args --user-data-dir="$profile/chrome" --no-first-run --no-default-browser-check \
        --force-renderer-accessibility --new-window "$url"
      sleep 10
      pid=$(pgrep -f "MacOS/Google Chrome --user-data-dir=$profile/chrome" | head -1) ;;
    textedit)
      open -a TextEdit "$here/$url"
      sleep 2
      pid=$(pgrep -x TextEdit)
      title=$(basename "$url") ;;
  esac
  # The first read makes the app build its accessibility tree.
  "$bin/berang-grab" "$pid" ${title:+"$title"} > /dev/null 2>&1 || true
  sleep 1
  "$bin/berang-grab" --save "$name.json.lzma" "$pid" ${title:+"$title"} > "$name.md" || echo "FAILED $name"
  [ "$source" = textedit ] || kill "$pid"
done
