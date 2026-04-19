#!/usr/bin/env python3
import os, subprocess, sys

LOCK       = "/tmp/.claude_focus_tabs"
REELS_URL  = "https://www.instagram.com/reels/"
SHORTS_URL = "https://www.youtube.com/shorts"

SPLIT_SCREEN_SCRIPT = f'''
-- Get screen dimensions
tell application "Finder"
    set screenBounds to bounds of window of desktop
    set sw to item 3 of screenBounds
    set sh to item 4 of screenBounds
end tell

set halfW to sw div 2

tell application "Safari"
    activate

    -- Open Instagram Reels in first window, lock it to LEFT half
    make new document with properties {{URL:"{REELS_URL}"}}
    delay 0.5
    set bounds of window 1 to {{0, 0, halfW, sh}}

    -- Open YouTube Shorts in second window (becomes new front), lock it to RIGHT half
    make new document with properties {{URL:"{SHORTS_URL}"}}
    delay 0.5
    set bounds of window 1 to {{halfW, 0, sw, sh}}
end tell
'''

def main():
    if os.path.exists(LOCK):
        # Already open — just bring Safari back to front
        subprocess.run(["osascript", "-e", 'tell application "Safari" to activate'],
                       capture_output=True)
        sys.exit(0)

    try:
        subprocess.run(["osascript", "-e", SPLIT_SCREEN_SCRIPT], check=True)
    except Exception as e:
        print(f"[focus] Error: {e}", file=sys.stderr)
        sys.exit(0)

    with open(LOCK, "w") as f:
        f.write("safari")

    sys.exit(0)

if __name__ == "__main__":
    main()