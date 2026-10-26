#!/bin/zsh
# acc2 GUI walkthrough leg A — M-1 culling dual-pane render (per acc1 recipe).
# Presets: legacy gate via env, browser.mode=culling, NSNavLastRootDirectory seam.
# Cleanup: defaults restored by the caller (values sampled before).
set -euo pipefail
SHOT_DIR="/Volumes/UNITEK/Documents/Development/Lightamer/.work/gsd/phases/r12-repairs/acceptance-2"
APP="$HOME/Library/Developer/Xcode/DerivedData/Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi/Build/Products/Debug/Lightamer.app"

defaults write com.kamasylvia.lightamer browser.mode culling
defaults write com.kamasylvia.lightamer NSNavLastRootDirectory "$HOME/Documents/omp-g6-proj/session"

LIGHTAMER_LEGACY_LIBRARY=1 open -n "$APP"
sleep 6
osascript <<'EOF'
tell application "System Events"
  tell process "Lightamer"
    set frontmost to true
    delay 1
    keystroke "o" using command down
    delay 2
    -- the open panel opens at NSNavLastRootDirectory; confirm the choose
    keystroke return
    delay 8
  end tell
end tell
EOF
sleep 6
screencapture -x "$SHOT_DIR/cull-shot.png"
echo "CULL_SHOT_TAKEN"
# Sample the AX tree for pane evidence (image elements inside the culling view)
osascript <<'EOF' > "$SHOT_DIR/cull-ax.txt" 2>&1
tell application "System Events"
  tell process "Lightamer"
    set out to ""
    try
      set win to window 1
      set uiEls to entire contents of win
      repeat with el in uiEls
        try
          set r to role of el
          if r is "AXImage" or r is "AXProgressIndicator" then
            set out to out & r & " | "
          end if
        end try
      end repeat
    on error errMsg
      set out to "ERR: " & errMsg
    end try
    return out
  end tell
end tell
EOF
echo "AX_SAMPLED"
