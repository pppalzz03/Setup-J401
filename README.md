# sensing-j401 — ติดตั้งกล้อง SENSING SG4A บน Seeed J401 หลัง clone repo

ขั้นตอนนี้เริ่มหลังจาก Jetson แฟลช JetPack 6.1 เสร็จ และ clone repo นี้ไว้ที่ `/home/nx_jp61/sensing-j401` แล้ว

> **สถานะ:** config นี้รับภาพได้จริงบน JetPack 6.2 / R36.4.3 (`docs/SUCCESS-SETUP-jp62.md`) ชุด JetPack 6.1 ใน `jetpack-6.1-r36.4.2/` **ยังไม่ได้ทดสอบ** จนกว่าจะกรอกตาราง "ผลทดสอบ" ท้ายไฟล์นี้

## โครงสร้าง repo

```text
sensing-j401/
├── README.md
├── .gitattributes
├── .gitignore
├── common/                         ← ใช้ได้ทุก JetPack
│   ├── dts/sensing-j401-j9-2lane.dts
│   ├── helpers/
│   │   ├── configure-2lane.py
│   │   └── restore-serializer-address.py
│   ├── loader/sensing-j401-load
│   ├── systemd/sensing-camera-load.service
│   └── capture/
│       ├── capture.sh
│       └── record-60s.py
├── docs/
│   ├── SUCCESS-SETUP-jp62.md
│   └── SETUP-JP61.md
└── jetpack-6.1-r36.4.2/            ← ผูกกับ L4T release นี้เท่านั้น
    ├── RELEASE
    ├── SHA256SUMS
    ├── modules/
    │   ├── max96712.ko
    │   └── sgx-yuv-gmsl2.ko
    └── kernel/
        ├── Image
        ├── tegra-camera.ko
        └── nvhost-nvcsi.ko
```

DTBO ไม่ได้เก็บใน repo ขั้นตอนที่ 7 compile จาก `common/dts` บนเครื่องทุกครั้ง และทดสอบกับ base DTB ของเครื่องนั้นก่อนติดตั้ง

ทุกคำสั่งรันบน Jetson ผ่าน SSH ตั้งตัวแปรนี้ก่อนในทุก terminal ที่เปิดใหม่:

```bash
REPO=/home/nx_jp61/sensing-j401
BSP=$REPO/jetpack-6.1-r36.4.2
```

---

## 1. ล็อก package ของ L4T ก่อนใช้ apt

repo apt `r36.4` ของ NVIDIA ส่ง package ของ R36.4.3 (JetPack 6.2) มาด้วย ถ้าไม่ล็อกไว้ การ `apt upgrade` จะอัปเกรดเครื่องข้ามไป 6.2 และเขียนทับ kernel/modules กล้อง

```bash
sudo apt-mark hold nvidia-l4t-display-kernel nvidia-l4t-kernel nvidia-l4t-kernel-dtbs nvidia-l4t-kernel-headers nvidia-l4t-kernel-oot-headers nvidia-l4t-kernel-oot-module
apt-mark showhold
```

ห้ามรัน `sudo apt upgrade` บนเครื่องนี้หลังจากติดตั้งกล้องแล้ว

## 2. ติดตั้ง dependencies และดึงไฟล์ binary

```bash
sudo apt-get update
sudo apt-get install -y git-lfs i2c-tools v4l-utils device-tree-compiler gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good python3-pil python3-gi gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0
cd $REPO
git lfs install
git lfs pull
```

## 3. ตรวจก่อนติดตั้ง

```bash
head -n1 /etc/nv_tegra_release
cat $BSP/RELEASE
head -n1 /etc/nv_tegra_release | grep -qF "$(cat $BSP/RELEASE)" && echo "OK: L4T release ตรง" || echo "STOP: L4T release ไม่ตรง"

[ "$(uname -r)" = "5.15.148-tegra" ] && echo "OK: kernel" || echo "STOP: kernel"

(cd $BSP && sha256sum -c SHA256SUMS)

file $BSP/modules/*.ko $BSP/kernel/Image
file $REPO/common/loader/sensing-j401-load $REPO/common/capture/capture.sh $REPO/common/helpers/*.py

modinfo -F vermagic $BSP/modules/max96712.ko
modinfo -p $BSP/modules/sgx-yuv-gmsl2.ko | grep GMSLMODE_1

i2cdetect -l
ls /boot/dtb/
```

ทุกข้อต้องผ่านก่อนไปต่อ:

| ตรวจ | ต้องได้ | ถ้าไม่ได้ |
|---|---|---|
| release | `OK: L4T release ตรง` | แฟลชผิดรุ่น หรือ `RELEASE` ไม่ตรงเครื่อง ดูหัวข้อ "ไฟล์ RELEASE" ท้ายไฟล์ |
| kernel | `OK: kernel` | หยุด |
| sha256sum | ทุกไฟล์ `OK` | `git lfs pull` ใหม่ หรือไฟล์ใน repo ถูกแก้ |
| `file` ของ .ko / Image | `ELF ... aarch64` / `Linux kernel ARM64 boot executable` | ถ้าขึ้น `ASCII text` คือยังเป็น LFS pointer ให้ `git lfs pull` |
| `file` ของสคริปต์ | ไม่มีคำว่า `CRLF` | ไฟล์ถูกแก้บน Windows แล้ว commit แบบ CRLF ให้ตรวจ `.gitattributes` แล้ว clone ใหม่ |
| vermagic | ขึ้นต้นด้วย `5.15.148-tegra` | โมดูลไม่ใช่ของ kernel นี้ |
| GMSLMODE_1 | มีบรรทัด parameter | driver ไม่ใช่ชุด SENSING ที่รองรับ 3G |
| I2C | มี bus 9 ที่เป็น camera mux | ถ้าเลขต่าง ต้องแก้ `'9'` ใน helper ทั้งสองไฟล์ |
| `/boot/dtb/` | มี `kernel_tegra234-p3768-0000+p3767-0000-nv.dtb` | ถ้าชื่อต่าง ใช้ชื่อจริงแทนในขั้นตอนที่ 7–8 |

## 4. สำรองของเดิม

```bash
B=/home/nx_jp61/Downloads/sensing-before-install
mkdir -p $B
sudo cp -a /boot/extlinux/extlinux.conf $B/
sudo cp -a /boot/Image $B/
sudo cp -a /boot/initrd $B/
sudo cp -a /lib/modules/5.15.148-tegra/updates/drivers/media/platform/tegra/camera/tegra-camera.ko $B/
sudo cp -a /lib/modules/5.15.148-tegra/updates/drivers/video/tegra/host/nvcsi/nvhost-nvcsi.ko $B/
ls -l $B
```

## 5. ติดตั้ง kernel และ camera stack

| ต้นทางใน repo | ปลายทางบน Jetson |
|---|---|
| `jetpack-6.1-r36.4.2/kernel/Image` | `/boot/Image` |
| `jetpack-6.1-r36.4.2/kernel/tegra-camera.ko` | `/lib/modules/5.15.148-tegra/updates/drivers/media/platform/tegra/camera/tegra-camera.ko` |
| `jetpack-6.1-r36.4.2/kernel/nvhost-nvcsi.ko` | `/lib/modules/5.15.148-tegra/updates/drivers/video/tegra/host/nvcsi/nvhost-nvcsi.ko` |

```bash
sudo install -m 644 $BSP/kernel/Image /boot/Image
sudo install -m 644 $BSP/kernel/tegra-camera.ko /lib/modules/5.15.148-tegra/updates/drivers/media/platform/tegra/camera/tegra-camera.ko
sudo install -m 644 $BSP/kernel/nvhost-nvcsi.ko /lib/modules/5.15.148-tegra/updates/drivers/video/tegra/host/nvcsi/nvhost-nvcsi.ko
sudo depmod -a 5.15.148-tegra
sudo update-initramfs -u -k 5.15.148-tegra
```

## 6. ติดตั้ง SENSING driver, helper, loader และ service

| ต้นทางใน repo | ปลายทางบน Jetson | mode |
|---|---|---|
| `jetpack-6.1-r36.4.2/modules/max96712.ko` | `/usr/local/lib/sensing-j401/max96712.ko` | 644 |
| `jetpack-6.1-r36.4.2/modules/sgx-yuv-gmsl2.ko` | `/usr/local/lib/sensing-j401/sgx-yuv-gmsl2.ko` | 644 |
| `jetpack-6.1-r36.4.2/RELEASE` | `/usr/local/lib/sensing-j401/RELEASE` | 644 |
| `common/helpers/configure-2lane.py` | `/usr/local/lib/sensing-j401/configure-2lane.py` | 644 |
| `common/helpers/restore-serializer-address.py` | `/usr/local/lib/sensing-j401/restore-serializer-address.py` | 755 |
| `common/loader/sensing-j401-load` | `/usr/local/sbin/sensing-j401-load` | 755 |
| `common/systemd/sensing-camera-load.service` | `/etc/systemd/system/sensing-camera-load.service` | 644 |
| `common/capture/capture.sh` | `/home/nx_jp61/Downloads/sensing-capture/capture.sh` | 755 |
| `common/capture/record-60s.py` | ใช้จาก repo ตรง ๆ | — |

```bash
sudo mkdir -p /usr/local/lib/sensing-j401
sudo install -m 644 $BSP/modules/max96712.ko $BSP/modules/sgx-yuv-gmsl2.ko $BSP/RELEASE /usr/local/lib/sensing-j401/
sudo install -m 644 $REPO/common/helpers/configure-2lane.py /usr/local/lib/sensing-j401/
sudo install -m 755 $REPO/common/helpers/restore-serializer-address.py /usr/local/lib/sensing-j401/
sudo install -m 755 $REPO/common/loader/sensing-j401-load /usr/local/sbin/sensing-j401-load
sudo install -m 644 $REPO/common/systemd/sensing-camera-load.service /etc/systemd/system/sensing-camera-load.service

mkdir -p /home/nx_jp61/Downloads/sensing-capture
install -m 755 $REPO/common/capture/capture.sh /home/nx_jp61/Downloads/sensing-capture/capture.sh
```

loader อ่าน `/usr/local/lib/sensing-j401/RELEASE` ตอนบูต ถ้าเครื่องถูกอัปเกรด L4T ไปรุ่นอื่น service จะหยุดก่อนโหลดโมดูล

## 7. Compile และติดตั้ง overlay

```bash
dtc -@ -I dts -O dtb -o /tmp/sensing-j401-j9-2lane.dtbo $REPO/common/dts/sensing-j401-j9-2lane.dts

fdtoverlay \
  -i /boot/dtb/kernel_tegra234-p3768-0000+p3767-0000-nv.dtb \
  -o /tmp/sensing-merged-check.dtb \
  /tmp/sensing-j401-j9-2lane.dtbo && echo "OK: overlay apply ได้"

dtc -I dtb -O dts /tmp/sensing-merged-check.dtb 2>/dev/null | grep -c -e 'cam_2@1c' -e 'serial_c'

sudo install -m 644 /tmp/sensing-j401-j9-2lane.dtbo /boot/sensing-j401-j9-2lane.dtbo
```

`dtc` ขึ้น warning ได้ แต่ `fdtoverlay` ต้องได้ `OK` และ `grep -c` ต้องมากกว่า 0 ถ้า `fdtoverlay` error ให้หยุด ห้ามใส่ overlay ใน extlinux

## 8. เพิ่ม boot entry ใน extlinux

คำสั่งคัดบรรทัด `APPEND` จาก entry `primary` ของเครื่องนี้ จึงได้ PARTUUID และ boot arguments ของเครื่องเอง

```bash
sudo cp -a /boot/extlinux/extlinux.conf /boot/extlinux/extlinux.conf.before-sensing
APPEND_LINE=$(awk '/^LABEL primary/{f=1} f && /APPEND/{print; exit}' /boot/extlinux/extlinux.conf)
echo "$APPEND_LINE"

sudo tee -a /boot/extlinux/extlinux.conf >/dev/null <<EOF

LABEL sensing-j9
      MENU LABEL SENSING J401 J9 2-lane
      LINUX /boot/Image
      FDT /boot/dtb/kernel_tegra234-p3768-0000+p3767-0000-nv.dtb
      INITRD /boot/initrd
${APPEND_LINE}
      OVERLAYS /boot/sensing-j401-j9-2lane.dtbo
EOF

sudo sed -i 's/^DEFAULT .*/DEFAULT sensing-j9/' /boot/extlinux/extlinux.conf
cat /boot/extlinux/extlinux.conf
```

ตรวจไฟล์ที่ได้:

- `DEFAULT sensing-j9`
- entry `sensing-j9` มี `APPEND ${cbootargs} root=PARTUUID=...` ตรงกับ `sudo blkid -s PARTUUID -o value "$(findmnt -no SOURCE /)"`
- ยังมี `LABEL primary`
- มี entry `sensing-j9` แค่ entry เดียว (ถ้ารันคำสั่งซ้ำ ให้คืนไฟล์ `.before-sensing` แล้วทำใหม่)
- ไม่มี `LABEL JetsonIO` และไม่มี `tegra234-camera-yuv-gmslx4-overlay.dtbo`

## 9. เปิด service และ reboot

```bash
sudo systemctl daemon-reload
sudo systemctl enable sensing-camera-load.service
sudo reboot
```

## 10. ตรวจหลังบูต

```bash
head -n1 /etc/nv_tegra_release
systemctl status sensing-camera-load.service --no-pager
journalctl -b -u sensing-camera-load.service --no-pager
sudo dmesg | grep -i -e max96712 -e sgx -e nvcsi -e disagrees -e 'Invalid module'
cat /sys/module/sgx_yuv_gmsl2/parameters/GMSLMODE_1
v4l2-ctl --list-devices
media-ctl -p -d /dev/media0
v4l2-ctl -d /dev/video2 --get-fmt-video
```

ต้องได้:

- release ยังเป็นรุ่นเดิม
- service `active (exited)`
- GMSLMODE_1 `2,2,2,2`
- `/dev/video2` เป็น cam_2@1c, NV16 1920×1536
- dmesg ไม่มี `disagrees about version of symbol` หรือ `Invalid module format`

## 11. ทดสอบภาพนิ่งและวิดีโอ

ภาพนิ่ง (สคริปต์ถาม sudo password แล้วสร้างโฟลเดอร์ใหม่ใต้ Downloads):

```bash
bash /home/nx_jp61/Downloads/sensing-capture/capture.sh /dev/video2 1
```

วิดีโอ 60 วินาที (ผลอยู่ที่ `/home/nx_jp61/Downloads/sensing-record-60s/`):

```bash
sudo python3 $REPO/common/capture/record-60s.py

gst-launch-1.0 -q \
  filesrc location=/home/nx_jp61/Downloads/sensing-record-60s/capture.mkv ! \
  matroskademux ! jpegdec ! fakesink sync=false
```

เปิดดูภาพด้วยตาทุกครั้ง ไฟล์ขนาดครบหรือไม่มี error ยังไม่ใช่หลักฐานว่ารับภาพจริง คำสั่งแยกขั้นอยู่ในหัวข้อ 7–8 ของ `docs/SUCCESS-SETUP-jp62.md`

## 12. ถ้าต้องย้อนกลับ

ถ้าบูต entry `sensing-j9` ไม่ขึ้น เลือก `primary` จากเมนูทาง serial console (ttyTCU0) ภายใน 3 วินาที แล้ว:

```bash
B=/home/nx_jp61/Downloads/sensing-before-install
sudo systemctl disable sensing-camera-load.service
sudo cp -a $B/extlinux.conf /boot/extlinux/extlinux.conf
sudo cp -a $B/Image /boot/Image
sudo cp -a $B/initrd /boot/initrd
sudo cp -a $B/tegra-camera.ko /lib/modules/5.15.148-tegra/updates/drivers/media/platform/tegra/camera/tegra-camera.ko
sudo cp -a $B/nvhost-nvcsi.ko /lib/modules/5.15.148-tegra/updates/drivers/video/tegra/host/nvcsi/nvhost-nvcsi.ko
sudo depmod -a 5.15.148-tegra
sudo reboot
```

## 13. แก้ปัญหา

| อาการ | สิ่งที่ทำ |
|---|---|
| Service fail ทันที | `journalctl -b -u sensing-camera-load.service` ดูว่าตกบรรทัดไหนของ loader |
| ตกที่ตรวจ release | เครื่องถูกอัปเกรด L4T ไปแล้ว ตรวจ `apt-mark showhold` |
| `/bin/sh^M: bad interpreter` | ไฟล์เป็น CRLF ตรวจ `.gitattributes` แล้ว clone ใหม่ |
| `Invalid module format` / `disagrees about version of symbol` | โมดูลกับ kernel/camera stack ไม่ใช่ชุดเดียวกัน |
| ไม่มี `/proc/device-tree/bus@0/cam_i2cmux/i2c@1/cam_2@1c` | overlay ไม่ถูก apply ตรวจ `FDT` และ `OVERLAYS` ใน extlinux |
| `Unexpected deserializer ID` | I2C bus/address ต่าง ตรวจ `i2cdetect -l` และ `sudo i2cdetect -y -r 9` |
| มี `/dev/video2` แต่ capture timeout | รัน `sudo python3 /usr/local/lib/sensing-j401/configure-2lane.py` ก่อนทุกรอบ แล้วดู dmesg ของ nvcsi/vi |

---

## ไฟล์ RELEASE

`jetpack-6.1-r36.4.2/RELEASE` มีบรรทัดเดียว เป็นส่วนต้นของบรรทัดแรกใน `/etc/nv_tegra_release` ของเครื่องที่ใช้ทดสอบชุด binary นี้ เช่น:

```text
# R36 (release), REVISION: 4.2,
```

ค่าต้องตรงกับเครื่องจริง JetPack 6.1 รุ่นแรกรายงาน `REVISION: 4.0` ถ้าเครื่องขึ้นเลขอื่นให้ใช้เลขนั้น และเปลี่ยนชื่อโฟลเดอร์ให้ตรงกันด้วย อย่าแก้ RELEASE ให้ตรงเพื่อให้ผ่านการตรวจโดยที่ binary ไม่ได้มาจาก release นั้น

## สร้าง SHA256SUMS (ทำครั้งเดียวหลังทดสอบผ่าน)

```bash
cd $BSP
sha256sum RELEASE modules/* kernel/* > SHA256SUMS
cat SHA256SUMS
```

## ผลทดสอบชุด jetpack-6.1-r36.4.2

| การตรวจ | ผล |
|---|---|
| วันที่ / เครื่อง | |
| บรรทัดแรก `/etc/nv_tegra_release` | |
| SDK ของ SENSING ที่ใช้สร้าง binary | |
| Raw NV16 5,898,240 ไบต์ | |
| ภาพนิ่งเห็นวัตถุจริง | |
| Capture ซ้ำ | |
| Reboot แล้ว service active และ capture ได้ | |
| วิดีโอ 60 วินาที: เฟรม / fps / ขนาด | |
| Decode ครบไฟล์ | |
