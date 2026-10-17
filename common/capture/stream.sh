#!/bin/bash
# Live view of the SENSING camera on the Jetson's own monitor (X11, xvimagesink).
# 1920x1536 NV16 @30 -> 24 fps -> crop to 1920x1080 (16:9) -> scale 1280x720
# Run as the desktop user (not sudo), from the desktop terminal or over SSH:
#   bash stream.sh [device]          Ctrl+C to stop
set -euo pipefail

DEV=${1:-/dev/video2}
U=${SUDO_UID:-$(id -u)}

# X display of the logged-in desktop. Override with DISPLAY=:0 bash stream.sh if needed.
export DISPLAY=${DISPLAY:-:1}
if [ -z "${XAUTHORITY:-}" ] || [ ! -f "$XAUTHORITY" ]; then
  export XAUTHORITY=/run/user/$U/gdm/Xauthority
fi
[ -e "$DEV" ] || { echo "STOP: $DEV not found" >&2; exit 1; }
[ -f "$XAUTHORITY" ] || { echo "STOP: $XAUTHORITY not found (login to the desktop on the Jetson monitor first)" >&2; exit 1; }
echo "DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY device=$DEV"

# 2-lane MIPI config before every stream (needs root for I2C)
sudo python3 /usr/local/lib/sensing-j401/configure-2lane.py

v4l2-ctl -d "$DEV" \
  --set-ctrl=sensor_mode=1,bypass_mode=0 \
  --set-fmt-video=width=1920,height=1536,pixelformat=NV16

exec gst-launch-1.0 -e \
  v4l2src device="$DEV" io-mode=mmap \
    do-timestamp=true pixel-aspect-ratio=1/1 ! \
  video/x-raw,format=NV16,width=1920,height=1536,framerate=30/1 ! \
  queue max-size-buffers=2 max-size-bytes=0 max-size-time=0 leaky=downstream ! \
  videorate drop-only=true ! video/x-raw,framerate=24/1 ! \
  videoconvert n-threads=4 ! video/x-raw,format=YUY2 ! \
  videocrop top=228 bottom=228 ! \
  videoscale method=0 n-threads=4 ! \
  video/x-raw,width=1280,height=720,pixel-aspect-ratio=1/1 ! \
  videoconvert n-threads=4 ! video/x-raw,format=YUY2 ! \
  xvimagesink sync=false
