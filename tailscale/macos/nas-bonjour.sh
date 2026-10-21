#!/bin/bash
# Make the TrueNAS SMB shares show up in Finder → Network when away from home.
#
# Finder's Network list is built from Bonjour (mDNS) announcements, which are
# multicast and never cross Tailscale. The NAS is still REACHABLE over the
# tailnet (sol routes 192.168.1.60/32), it just isn't ANNOUNCED. This installs
# a LaunchAgent that has the Mac announce the NAS to itself: a Bonjour proxy
# record for _smb._tcp pointing at 192.168.1.60.
#
#   ./nas-bonjour.sh            install / update (runs at login, kept alive)
#   ./nas-bonjour.sh uninstall  remove it
#
# Run on the Mac, as your normal user (no sudo).
set -euo pipefail

NAS_IP=192.168.1.60
# Distinct name/host so it doesn't collide with the NAS's own announcement when
# you're at home (both entries then work).
NAME="TrueNAS (Tailscale)"
HOST=truenas-ts.local

LABEL=com.homelab.nas-bonjour
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

if [ "${1:-}" = uninstall ]; then
  rm -f "$PLIST"
  echo "Removed $LABEL."
  exit 0
fi

mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/dns-sd</string>
    <string>-P</string><string>$NAME</string>
    <string>_smb._tcp</string><string>local</string><string>445</string>
    <string>$HOST</string><string>$NAS_IP</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
EOF

launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed $LABEL: \"$NAME\" → smb://$NAS_IP"
echo "Check: dns-sd -B _smb._tcp   (Ctrl-C to stop)"
