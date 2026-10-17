# SUCCESS SETUP — JetPack 6.2 / R36.4.3

> **สถานะเอกสาร:** โครงไฟล์นี้ถูกสร้างใหม่ เพราะต้นฉบับไม่ได้อยู่ใน repo ส่วนที่มี `TODO` ต้องกรอกจากบันทึกของเครื่องที่รับภาพได้จริง
> คำสั่งในหัวข้อ 7–8 คือคำสั่งแยกขั้นที่ `README.md` อ้างถึง

## 1. เครื่องที่ทดสอบ

| รายการ | ค่า |
|---|---|
| บอร์ด / module | Seeed J401 + Orin NX (TODO: รุ่น) |
| บรรทัดแรก `/etc/nv_tegra_release` | TODO |
| `uname -r` | TODO |
| กล้อง / พอร์ต | SENSING SG4A ที่ J9, port 2 (`cam_2@1c`) |
| วันที่ทดสอบ | TODO |

## 2. ไฟล์ที่ติดตั้ง

TODO: รายชื่อไฟล์และ sha256 ที่ใช้บนเครื่อง 6.2

## 3. Overlay และ extlinux

TODO: entry ที่ใช้งานได้

## 4. โหลด driver

TODO: ลำดับที่โหลดและ output ของ dmesg

## 5. ค่า MAX96712 2-lane

ใช้ `common/helpers/configure-2lane.py` ตาม register ในไฟล์นั้น

## 6. ผลที่ได้

TODO: ผลภาพนิ่ง และสถิติวิดีโอ (frames / fps / ขนาด)

## 7. ทดสอบภาพนิ่งแยกขั้น

```bash
sudo python3 /usr/local/lib/sensing-j401/configure-2lane.py
v4l2-ctl -d /dev/video2 --set-ctrl=sensor_mode=1,bypass_mode=0 \
  --set-fmt-video=width=1920,height=1536,pixelformat=NV16
v4l2-ctl -d /dev/video2 --get-fmt-video
mkdir -p ~/Downloads/sensing-frame-test && cd ~/Downloads/sensing-frame-test
timeout 20 v4l2-ctl -d /dev/video2 --stream-mmap --stream-skip=5 \
  --stream-count=1 --stream-to=frame.nv16
stat -c %s frame.nv16          # ต้องได้ 5898240
```

แปลงเป็น PNG และเปิดดูด้วยตา:

```bash
python3 - <<'PY'
from PIL import Image
w, h = 1920, 1536
f = open('frame.nv16', 'rb').read()
y = Image.frombytes('L', (w, h), f[:w*h]); uv = f[w*h:]
u = Image.frombytes('L', (w//2, h), uv[0::2]).resize((w, h))
v = Image.frombytes('L', (w//2, h), uv[1::2]).resize((w, h))
Image.merge('YCbCr', (y, u, v)).convert('RGB').save('frame.png')
PY
```

## 8. ทดสอบวิดีโอแยกขั้น

```bash
sudo python3 /usr/local/lib/sensing-j401/configure-2lane.py
gst-launch-1.0 -e v4l2src device=/dev/video2 io-mode=mmap num-buffers=300 ! \
  video/x-raw,format=NV16,width=1920,height=1536,framerate=30/1 ! \
  queue ! videoconvert ! jpegenc quality=95 ! matroskamux ! \
  filesink location=$HOME/Downloads/sensing-frame-test/test-10s.mkv

gst-launch-1.0 -q filesrc location=$HOME/Downloads/sensing-frame-test/test-10s.mkv ! \
  matroskademux ! jpegdec ! fakesink sync=false && echo "OK: decode ครบ"
```

ถ้า `v4l2src` ค้างหรือ timeout ให้ดู `sudo dmesg | tail -50` หา error ของ nvcsi / vi
