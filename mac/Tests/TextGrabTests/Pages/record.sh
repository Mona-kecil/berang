#!/bin/sh
# Records saved pages: opens each page, saves its accessibility tree to <name>.json.lzma, and writes the
# text read back from that copy to <name>.md. A PDF saves its lines instead of a tree. Review the .md diffs
# before committing them.
# usage: Tests/TextGrabTests/Pages/record.sh [name ...]   (default: every page in pages.tsv)
# Needs Accessibility access for the terminal. Chrome and VS Code pages use a throwaway profile.
set -e
cd "$(dirname "$0")"
(cd ../../.. && swift build -c release -q)
bin=$(cd ../../.. && swift build -c release --show-bin-path)
profile=$(mktemp -d)
# Fixtures open from a fixed folder, so saved pages hold no home folder path.
copy=/tmp/berang-pages
rm -rf "$copy" && mkdir -p "$copy" && cp -R fixtures "$copy/"
trap 'rm -rf "$profile" "$copy"' EXIT

tail -n +2 pages.tsv | while IFS="$(printf '\t')" read -r name source url license; do
  if [ $# -gt 0 ] && ! echo " $* " | grep -q " $name "; then continue; fi
  title=
  if [ "$source" = pdf ]; then
    file=$url
    case $url in http*) file="$profile/$name.pdf"; curl -sL -o "$file" "$url" ;; esac
    "$bin/berang-grab" --pdf "$file" --save "$name.json.lzma" > "$name.md" || echo "FAILED $name"
    continue
  fi
  case $url in http*) ;; *) url="file://$copy/$url" ;; esac
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
    vscode)
      # Screen reader mode puts the editor's text in the accessibility tree.
      mkdir -p "$profile/vscode/User"
      echo '{"editor.accessibilitySupport": "on", "chat.disableAIFeatures": true}' > "$profile/vscode/User/settings.json"
      "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" --user-data-dir "$profile/vscode" \
        --extensions-dir "$profile/vscode-extensions" --new-window "${url#file://}"
      sleep 8
      pid=$(pgrep -f "MacOS/Code --user-data-dir $profile/vscode" | head -1) ;;
    textedit|preview)
      app=$([ "$source" = textedit ] && echo TextEdit || echo Preview)
      open -a "$app" "${url#file://}"
      sleep 2
      pid=$(pgrep -x "$app")
      title=$(basename "$url") ;;
  esac
  # The first read makes the app build its accessibility tree.
  "$bin/berang-grab" "$pid" ${title:+"$title"} > /dev/null 2>&1 || true
  sleep 1
  "$bin/berang-grab" --save "$name.json.lzma" "$pid" ${title:+"$title"} > "$name.md" || echo "FAILED $name"
  if [ "$source" = textedit ] || [ "$source" = preview ]; then
    osascript -e "tell application \"$app\"" \
      -e "close (first document whose path is \"${url#file://}\") saving no" \
      -e "if (count of documents) is 0 then quit" -e "end tell"
  else
    kill "$pid"
  fi
done
