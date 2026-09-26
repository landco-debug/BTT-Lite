#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
APP_SRC="$ROOT/Trickpad.app"
HELPER_SRC="$ROOT/bin/trickpad-hide-hovered-dock-app"
CONFIG_SRC="$ROOT/config.toml"

APP_DST="$HOME/Applications/Trickpad.app"
HELPER_DST="$HOME/bin/trickpad-hide-hovered-dock-app"
CONFIG_DIR="$HOME/.config/trickpad"
CONFIG_DST="$CONFIG_DIR/config.toml"

[[ -d "$APP_SRC" ]] || { echo "Missing $APP_SRC"; exit 1; }
[[ -x "$HELPER_SRC" ]] || { echo "Missing $HELPER_SRC"; exit 1; }
[[ -f "$CONFIG_SRC" ]] || { echo "Missing $CONFIG_SRC"; exit 1; }

/usr/bin/codesign --verify --deep --strict "$APP_SRC"
/usr/bin/codesign --verify --strict "$HELPER_SRC"

mkdir -p "$HOME/Applications" "$HOME/bin" "$CONFIG_DIR"

/usr/bin/pkill -x Trickpad 2>/dev/null || true
rm -rf "$APP_DST"
/usr/bin/ditto "$APP_SRC" "$APP_DST"
/bin/cp -f "$HELPER_SRC" "$HELPER_DST"
/bin/chmod 755 "$HELPER_DST"

if [[ -f "$CONFIG_DST" ]]; then
    stamp="$(/bin/date +%Y%m%d-%H%M%S)"
    /bin/cp -p "$CONFIG_DST" "$CONFIG_DST.backup-$stamp"
    echo "Existing Trickpad config backed up to:"
    echo "  $CONFIG_DST.backup-$stamp"
fi
/bin/cp -f "$CONFIG_SRC" "$CONFIG_DST"

/usr/bin/xattr -dr com.apple.quarantine "$APP_DST" 2>/dev/null || true
/usr/bin/xattr -d com.apple.quarantine "$HELPER_DST" 2>/dev/null || true

echo
echo "Installed:"
echo "  $APP_DST"
echo "  $HELPER_DST"
echo "  $CONFIG_DST"
echo
echo "Opening Trickpad..."
/usr/bin/open "$APP_DST"

echo
echo "One-time permissions:"
echo "  1. System Settings -> Privacy & Security -> Accessibility: enable Trickpad."
echo "  2. Add and enable: $HELPER_DST"
echo "     (press Cmd+Shift+G in the file picker and paste that path)."
echo
echo "Trackpad native setting required for the two 2-finger gestures:"
echo "  System Settings -> Trackpad -> More Gestures -> Swipe between pages"
echo "  -> Scroll left or right with two fingers."
echo
echo "After permissions are granted, choose Reload Settings in Trickpad."
