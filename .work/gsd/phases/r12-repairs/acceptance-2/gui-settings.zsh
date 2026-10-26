#!/bin/zsh
# acc2 GUI walkthrough leg B — F2-4 deep link + remount + crosstalk.
# Plain instance (library workspace), probe project + 2 ARW import,
# inspector AI row → 打开设置… → ACA page; then:
#   (a) remount attack: switch sidebar page, click the button again → ACA again
#   (b) crosstalk: close window, ⌘, reopen → default page (语言与主题), NOT ACA
set -uo pipefail
SHOT_DIR="/Volumes/UNITEK/Documents/Development/Lightamer/.work/gsd/phases/r12-repairs/acceptance-2"
APP="$HOME/Library/Developer/Xcode/DerivedData/Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi/Build/Products/Debug/Lightamer.app"
FIX="$SHOT_DIR/fixture-imgs"

mkdir -p "$FIX" /tmp/r12-acc2
cp "$HOME/Documents/omp-g6-proj/session/A.ARW" "$FIX/a.ARW"
cp "$HOME/Documents/omp-g6-proj/session/B.ARW" "$FIX/b.ARW"

open -n "$APP"
sleep 6

osascript <<'EOF'
on clickMenu(titleFragment)
  tell application "System Events" to tell process "Lightamer"
    set frontmost to true
    delay 0.5
    tell menu bar 1 to tell menu bar item "File" to tell menu 1
      click (first menu item whose name contains titleFragment)
    end tell
  end tell
end clickMenu
EOF

# --- New Project (⌘⇧N) → save panel → /tmp/r12-acc2/probe.lalb
osascript <<'EOF'
tell application "System Events" to tell process "Lightamer"
  set frontmost to true
  delay 0.5
  keystroke "n" using {command down, shift down}
  delay 2
  keystroke "g" using {command down, shift down}
  delay 1
  keystroke "/tmp/r12-acc2"
  delay 0.5
  keystroke return
  delay 1
  keystroke return
  delay 1
  -- name field: set to probe
  keystroke "a" using command down
  keystroke "probe"
  delay 0.5
  keystroke return
  delay 2
end tell
EOF
sleep 3
screencapture -x "$SHOT_DIR/probe-project.png"

# --- Import folder: File → import (匹配「导入」项) → go-to folder → choose
osascript <<'EOF'
tell application "System Events" to tell process "Lightamer"
  set frontmost to true
  delay 0.5
  tell menu bar 1 to tell menu bar item "File" to tell menu 1
    click (first menu item whose name contains "导入")
  end tell
  delay 2.5
  keystroke "g" using {command down, shift down}
  delay 1
  keystroke "/Volumes/UNITEK/Documents/Development/Lightamer/.work/gsd/phases/r12-repairs/acceptance-2/fixture-imgs"
  delay 0.5
  keystroke return
  delay 1
  keystroke return
  delay 3
end tell
EOF
sleep 6
screencapture -x "$SHOT_DIR/after-import.png"
echo "IMPORT_DONE_OR_CHECK_SHOT"
