#!/bin/bash
# Capture NV16 still frame(s) from the SENSING camera and convert to PNG.
# Usage: bash capture.sh [device] [count]     e.g. bash capture.sh /dev/video2 1
set -euo pipefail

DEV=${1:-/dev/video2}
COUNT=${2:-1}
W=1920
H=1536
FRAME=$((W * H * 2))   # NV16 = 5,898,240 bytes
OUT="$HOME/Downloads/sensing-photo/$(date +%Y%m%d-%H%M%S)"

[ -e "$DEV" ] || { echo "STOP: $DEV not found" >&2; exit 1; }
mkdir -p "$OUT"
echo "Output: $OUT"

# 2-lane MIPI config must be applied before every capture (needs root for I2C)
sudo python3 /usr/local/lib/sensing-j401/configure-2lane.py

v4l2-ctl -d "$DEV" --set-ctrl=sensor_mode=1,bypass_mode=0 \
  --set-fmt-video=width=$W,height=$H,pixelformat=NV16
v4l2-ctl -d "$DEV" --get-fmt-video | tee "$OUT/format.txt"

# Skip a few frames so exposure settles, then save COUNT frames
timeout 20 v4l2-ctl -d "$DEV" --stream-mmap --stream-skip=5 \
  --stream-count="$COUNT" --stream-to="$OUT/capture.nv16"

python3 - "$OUT" "$W" "$H" "$COUNT" <<'PY'
import sys
from pathlib import Path
from PIL import Image
out, w, h, n = Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
size = w * h * 2
data = (out / 'capture.nv16').read_bytes()
print(f'capture.nv16: {len(data):,} bytes (expected {size * n:,})')
if len(data) != size * n:
    raise SystemExit('STOP: size mismatch (check bytesperline/sizeimage in format.txt)')
for i in range(n):
    f = data[i * size:(i + 1) * size]
    (out / f'frame-{i:02d}.nv16').write_bytes(f)
    y = Image.frombytes('L', (w, h), f[:w * h])
    uv = f[w * h:]
    u = Image.frombytes('L', (w // 2, h), uv[0::2]).resize((w, h))
    v = Image.frombytes('L', (w // 2, h), uv[1::2]).resize((w, h))
    Image.merge('YCbCr', (y, u, v)).convert('RGB').save(out / f'frame-{i:02d}.png')
    print(f'frame-{i:02d}.png')
PY
rm -f "$OUT/capture.nv16"
echo "Done. Open the PNG and confirm the real scene is visible."
