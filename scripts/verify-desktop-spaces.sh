#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

space_json=$(defaults export com.apple.spaces - 2>/dev/null \
  | plutil -convert json -o - -- - \
  | jq -c '.SpacesDisplayConfiguration["Management Data"].Monitors[0]
      | {current:."Current Space".ManagedSpaceID, ids:[.Spaces[] | select(.type == 0) | .ManagedSpaceID]}')
space_count=$(jq '.ids | length' <<<"$space_json")

current_id=$(jq -r '.current' <<<"$space_json")
original_index=-1
for ((i = 0; i < space_count; i++)); do
  if [[ $(jq -r ".ids[$i]" <<<"$space_json") == "$current_id" ]]; then
    original_index=$i
    break
  fi
done
if ((space_count < 1 || original_index < 0)); then
  echo "Could not resolve the active Desktop Space" >&2
  exit 1
fi

swift build >/dev/null
binary="$(swift build --show-bin-path)/MacSnap"
log="${TMPDIR:-/tmp}/macsnap-space-verify-$$.log"
"$binary" --demo stack >"$log" 2>&1 &
demo_pid=$!
position=$original_index
window_id=""

switch_left() {
  osascript -e 'tell application "System Events" to key code 123 using control down' >/dev/null
  sleep 0.65
  position=$((position - 1))
}

switch_right() {
  osascript -e 'tell application "System Events" to key code 124 using control down' >/dev/null
  sleep 0.65
  position=$((position + 1))
}

restore_desktop() {
  set +e
  while ((position > original_index)); do switch_left; done
  while ((position < original_index)); do switch_right; done
  kill "$demo_pid" 2>/dev/null
  wait "$demo_pid" 2>/dev/null
  rm -f "$log"
}
trap restore_desktop EXIT INT TERM

osascript -e 'tell application "System Events" to launch' >/dev/null 2>&1 || true
sleep 1

check_panel() {
  local label=$1 output
  output=$(LABEL="$label" DEMO_PID="$demo_pid" EXPECTED_ID="$window_id" swift -e '
    import CoreGraphics
    import Foundation

    let env = ProcessInfo.processInfo.environment
    let pid = Int(env["DEMO_PID"]!)!
    let label = env["LABEL"]!
    let expected = Int(env["EXPECTED_ID"] ?? "")
    let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    guard let window = windows.first(where: {
        ($0[kCGWindowOwnerPID as String] as? NSNumber)?.intValue == pid
    }) else {
        fputs("\(label): MacSnap panel missing\n", stderr)
        exit(1)
    }
    let id = (window[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0
    let onscreen = (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
    let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0
    let bounds = window[kCGWindowBounds as String] as? [String: Any]
    let height = (bounds?["Height"] as? NSNumber)?.doubleValue ?? 0
    guard onscreen, alpha >= 0.99, height > 1, expected == nil || expected == id else {
        fputs("\(label): invalid panel state id=\(id) onscreen=\(onscreen) alpha=\(alpha) height=\(height)\n", stderr)
        exit(1)
    }
    print("\(label): PASS id=\(id) onscreen=1 alpha=\(alpha) height=\(Int(height))")
  ' 2>/dev/null)
  echo "$output"
  if [[ -z $window_id ]]; then window_id=${output#*id=}; window_id=${window_id%% *}; fi
}

check_panel "Desktop $((position + 1))"
while ((position > 0)); do
  switch_left
  check_panel "Desktop $((position + 1))"
done
while ((position < space_count - 1)); do
  switch_right
  check_panel "Desktop $((position + 1))"
done

echo "DESKTOP SPACE VERIFICATION PASS ($space_count Desktops, stable panel $window_id)"
