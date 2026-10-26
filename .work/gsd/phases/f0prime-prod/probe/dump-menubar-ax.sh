#!/bin/zsh
# dump-menubar-ax.sh — AX dump of the running Lightamer's menu bar (the
# D-F0P-3 cmd-W alignment record + the gate-1 menu-bar smoke evidence).
# Usage: dump-menubar-ax.sh <outdir> [menu-name]
set -u
outdir="$1"; shift
menu="${1:-File}"
mkdir -p "$outdir"
osascript -e 'tell application "System Events" to set frontmost of process "Lightamer" to true' 2>/dev/null
sleep 1
osascript <<APPLESCRIPT > "$outdir/menubar-top.txt" 2>&1
tell application "System Events"
    tell process "Lightamer"
        set out to ""
        repeat with mi in menu bar items of menu bar 1
            set out to out & (name of mi) & linefeed
        end repeat
        return out
    end tell
end tell
APPLESCRIPT
osascript <<APPLESCRIPT > "$outdir/menu-$menu.txt" 2>&1
tell application "System Events"
    tell process "Lightamer"
        set out to ""
        set m to menu 1 of menu bar item "$menu" of menu bar 1
        repeat with mi in menu items of m
            set nm to name of mi
            if nm is missing value then set nm to "---"
            set ke to ""
            try
                set ke to (value of attribute "AXMenuItemCmdChar" of mi)
            end try
            set mods to ""
            try
                set mods to (value of attribute "AXMenuItemCmdModifiers" of mi) as string
            end try
            set en to ""
            try
                set en to (enabled of mi) as string
            end try
            set out to out & nm & " | key=" & ke & " | mod=" & mods & " | enabled=" & en & linefeed
        end repeat
        return out
    end tell
end tell
APPLESCRIPT
print "dumped menubar + $menu → $outdir"
