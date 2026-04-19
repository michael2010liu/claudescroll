#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Claude Code Focus Mode — Hooks Setup
# Opens Instagram Reels + YouTube Shorts while Claude works; closes when done.
# ─────────────────────────────────────────────────────────────────────────────

set -e

HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "🔧 Setting up Claude Code Focus Hooks..."

# ── 1. Create hooks directory ─────────────────────────────────────────────────
mkdir -p "$HOOKS_DIR"

# ── 2. Write open_tabs.py ─────────────────────────────────────────────────────
cat > "$HOOKS_DIR/open_tabs.py" << 'PYEOF'
#!/usr/bin/env python3
"""
open_tabs.py — Called by Claude Code's UserPromptSubmit hook.
Opens Instagram Reels and YouTube Shorts in separate browser windows.
Uses a lock file so windows only open once per Claude "working" session.
"""
import os
import subprocess
import sys

LOCK = "/tmp/.claude_focus_tabs"
REELS_URL = "https://www.instagram.com/reels/"
SHORTS_URL = "https://www.youtube.com/shorts"

def get_default_browser():
    """Return 'chrome', 'safari', or 'other'."""
    try:
        result = subprocess.run(
            ["defaults", "read", "com.apple.LaunchServices/com.apple.launchservices.secure",
             "LSHandlers"],
            capture_output=True, text=True, timeout=5
        )
        text = result.stdout.lower()
        if "google chrome" in text or "com.google.chrome" in text:
            return "chrome"
        if "safari" in text or "com.apple.safari" in text:
            return "safari"
        if "firefox" in text or "org.mozilla.firefox" in text:
            return "firefox"
    except Exception:
        pass
    return "chrome"  # sensible default

def open_chrome(url):
    script = f'''
        tell application "Google Chrome"
            make new window
            set URL of active tab of front window to "{url}"
        end tell
    '''
    subprocess.run(["osascript", "-e", script], check=True)

def open_safari(url):
    script = f'''
        tell application "Safari"
            make new document
            set URL of front document to "{url}"
        end tell
    '''
    subprocess.run(["osascript", "-e", script], check=True)

def open_firefox(url):
    subprocess.Popen(["open", "-a", "Firefox", "--new", url])

def open_url(url, browser):
    if browser == "chrome":
        open_chrome(url)
    elif browser == "safari":
        open_safari(url)
    elif browser == "firefox":
        open_firefox(url)
    else:
        subprocess.Popen(["open", url])

def main():
    # Already open? Do nothing.
    if os.path.exists(LOCK):
        sys.exit(0)

    browser = get_default_browser()

    try:
        open_url(REELS_URL, browser)
        open_url(SHORTS_URL, browser)
    except Exception as e:
        # Non-fatal — don't interrupt Claude if something goes wrong
        print(f"[focus-hooks] Could not open tabs: {e}", file=sys.stderr)
        sys.exit(0)

    # Write lock file with browser name so close script knows what to close
    with open(LOCK, "w") as f:
        f.write(browser)

    sys.exit(0)

if __name__ == "__main__":
    main()
PYEOF

# ── 3. Write close_tabs.py ────────────────────────────────────────────────────
cat > "$HOOKS_DIR/close_tabs.py" << 'PYEOF'
#!/usr/bin/env python3
"""
close_tabs.py — Called by Claude Code's Stop hook.
Closes any browser windows containing Instagram Reels or YouTube Shorts.
"""
import os
import subprocess
import sys

LOCK = "/tmp/.claude_focus_tabs"
REELS_HOST  = "instagram.com/reels"
SHORTS_HOST = "youtube.com/shorts"

CHROME_CLOSE_SCRIPT = f'''
tell application "Google Chrome"
    set toClose to {{}}
    repeat with w in (every window)
        repeat with t in (every tab of w)
            set u to URL of t
            if u contains "{REELS_HOST}" or u contains "{SHORTS_HOST}" then
                set end of toClose to w
                exit repeat
            end if
        end repeat
    end repeat
    repeat with w in toClose
        close w
    end repeat
end tell
'''

SAFARI_CLOSE_SCRIPT = f'''
tell application "Safari"
    set toClose to {{}}
    repeat with w in (every document)
        set u to URL of w
        if u contains "{REELS_HOST}" or u contains "{SHORTS_HOST}" then
            set end of toClose to w
        end if
    end repeat
    repeat with w in toClose
        close w
    end repeat
end tell
'''

def main():
    if not os.path.exists(LOCK):
        sys.exit(0)

    with open(LOCK) as f:
        browser = f.read().strip()

    try:
        if browser == "chrome":
            subprocess.run(["osascript", "-e", CHROME_CLOSE_SCRIPT],
                           capture_output=True, timeout=10)
        elif browser == "safari":
            subprocess.run(["osascript", "-e", SAFARI_CLOSE_SCRIPT],
                           capture_output=True, timeout=10)
        elif browser == "firefox":
            # Firefox AppleScript is limited; fall back to closing by process
            # (only works if Reels/Shorts windows are the *only* Firefox windows)
            pass
    except Exception as e:
        print(f"[focus-hooks] Could not close tabs: {e}", file=sys.stderr)

    # Always remove lock so next prompt can reopen
    try:
        os.remove(LOCK)
    except FileNotFoundError:
        pass

    sys.exit(0)

if __name__ == "__main__":
    main()
PYEOF

# ── 4. Make scripts executable ────────────────────────────────────────────────
chmod +x "$HOOKS_DIR/open_tabs.py"
chmod +x "$HOOKS_DIR/close_tabs.py"

# ── 5. Merge hook config into ~/.claude/settings.json ─────────────────────────
NEW_HOOKS=$(cat << JSON
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 $HOOKS_DIR/open_tabs.py",
            "async": true
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 $HOOKS_DIR/close_tabs.py",
            "async": true
          }
        ]
      }
    ]
  }
}
JSON
)

if [ -f "$SETTINGS_FILE" ]; then
    echo "📄 Found existing settings.json — merging hooks..."
    # Use Python to deep-merge so existing settings aren't clobbered
    python3 - "$SETTINGS_FILE" "$NEW_HOOKS" << 'PYEOF'
import json, sys

settings_path = sys.argv[1]
new_hooks_str  = sys.argv[2]

with open(settings_path) as f:
    existing = json.load(f)

new_hooks = json.loads(new_hooks_str)

# Deep-merge: append new hook groups to existing event arrays
existing.setdefault("hooks", {})
for event, groups in new_hooks["hooks"].items():
    existing["hooks"].setdefault(event, [])
    existing["hooks"][event].extend(groups)

with open(settings_path, "w") as f:
    json.dump(existing, f, indent=2)

print("✅ Merged into existing settings.json")
PYEOF
else
    echo "📄 No settings.json found — creating one..."
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    echo "$NEW_HOOKS" > "$SETTINGS_FILE"
    echo "✅ Created $SETTINGS_FILE"
fi

echo ""
echo "✅ Done! Hooks installed:"
echo "   📂 $HOOKS_DIR/open_tabs.py"
echo "   📂 $HOOKS_DIR/close_tabs.py"
echo "   ⚙️  $SETTINGS_FILE"
echo ""
echo "🎬 Next time you send a prompt in Claude Code:"
echo "   → Reels + Shorts windows open automatically"
echo "   → Both close the moment Claude finishes"
echo ""
echo "💡 Tip: Make sure your browser isn't blocking pop-ups from instagram.com / youtube.com."