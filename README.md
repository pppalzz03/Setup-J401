# sensing-j401 — ติดตั้งกล้อง SENSING SG4A บน Seeed J401 (JetPack 6.1)

คู่มือนี้เริ่มจาก Jetson ที่เพิ่งแฟลช JetPack 6.1 เสร็จ (ผ่าน first-boot setup แล้ว ชื่อ user อะไรก็ได้ คู่มือใช้ `$HOME` แทน path ของ user) ไปจนถึงรับภาพจากกล้องได้ ทุกคำสั่งรันบน Jetson ผ่าน SSH หรือ terminal ของเครื่อง ทำตามลำดับ ห้ามข้ามขั้น

> **สถานะ:** config นี้รับภาพได้จริงบน JetPack 6.2 / R36.4.3 (`docs/SUCCESS-SETUP-jp62.md`) ชุด JetPack 6.1 ใน `jetpack-6.1-r36.4.2/` **ยังไม่ได้ทดสอบ** จนกว่าจะกรอกตาราง "ผลทดสอบ" ท้ายไฟล์นี้

| ขั้น | ทำอะไร | ขั้น | ทำอะไร |
|---|---|---|---|
| 1 | ตรวจเครื่องหลังแฟลช | 9 | Compile และติดตั้ง overlay |
| 2 | ล็อก package L4T | 10 | เพิ่ม boot entry ใน extlinux |
| 3 | ติดตั้ง git, git-lfs, dependencies | 11 | เปิด service และ reboot |
| 4 | Clone repo และเตรียมไฟล์ | 12 | ตรวจหลังบูต |
| 5 | ตรวจก่อนติดตั้ง | 13 | ทดสอบภาพนิ่งและวิดีโอ |
| 6 | สำรองของเดิม | 14 | ย้อนกลับ |
| 7 | ติดตั้ง camera stack | 15 | แก้ปัญหา |
| 8 | ติดตั้ง driver, helper, loader, service | | |

## โครงสร้าง repo

```text
sensing-j401/
├── README.md
├── .gitattributes
├── .gitignore
├── common/                         ← ใช้ได้ทุก JetPack
│   ├── dts/sensing-j401-j9-2lane.dts
│   ├── helpers/
│   │   ├── check-abi.sh
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
        ├── tegra-camera.ko
        └── nvhost-nvcsi-t194.ko
```

ใช้ kernel `Image` เดิมของเครื่อง (5.15.148-tegra จาก JetPack 6.1) ไม่ได้เก็บใน repo และ repo เปลี่ยนเฉพาะโมดูล camera stack

DTBO ไม่ได้เก็บใน repo ขั้นตอนที่ 9 compile จาก `common/dts` บนเครื่องทุกครั้ง และทดสอบกับ base DTB ของเครื่องนั้นก่อนติดตั้ง

---

## 1. ตรวจเครื่องหลังแฟลช

```bash
head -n1 /etc/nv_tegra_release
uname -r
whoami
ping -c 3 github.com
timedatectl
```

ต้องได้:

- `/etc/nv_tegra_release` ขึ้นต้นด้วย `# R36 (release), REVISION: 4.` (จดบรรทัดนี้ไว้ ใช้ในขั้นตอนที่ 4)
- `uname -r` เป็น `5.15.148-tegra`
- `whoami` คือ user ที่จะใช้ติดตั้ง ทุกคำสั่งรันด้วย user นี้ (ไม่ใช่ `sudo -i` / root) เพราะ `$HOME` ต้องชี้ไปที่ home ของ user นี้
- ping ได้ (ต่ออินเทอร์เน็ตแล้ว)
- `System clock synchronized: yes` และวันที่ถูกต้อง ถ้าเวลาเพี้ยน `apt-get update` จะ error ว่า `Release file ... is not valid yet` ให้รัน:

```bash
sudo timedatectl set-ntp true
sleep 10; timedatectl
```

## 2. ล็อก package ของ L4T ก่อนใช้ apt

repo apt `r36.4` ของ NVIDIA ส่ง package ของ R36.4.3 (JetPack 6.2) มาด้วย ถ้าไม่ล็อกไว้ การ `apt upgrade` จะอัปเกรดเครื่องข้ามไป 6.2 และเขียนทับ kernel/modules กล้อง ทำขั้นนี้ก่อนใช้ apt ครั้งแรก

```bash
sudo apt-mark hold nvidia-l4t-display-kernel nvidia-l4t-kernel nvidia-l4t-kernel-dtbs nvidia-l4t-kernel-headers nvidia-l4t-kernel-oot-headers nvidia-l4t-kernel-oot-module
apt-mark showhold
```

`showhold` ต้องแสดงครบทั้ง 6 package ห้ามรัน `sudo apt upgrade` บนเครื่องนี้ ใช้ `apt-get install` เฉพาะ package ที่ต้องการเท่านั้น

## 3. ติดตั้ง git, git-lfs และ dependencies

ต้องติดตั้ง `git-lfs` **ก่อน** clone ไม่อย่างนั้นไฟล์ `.ko` จะเป็นแค่ LFS pointer ขนาด ~130 ไบต์

```bash
sudo apt-get update
sudo apt-get install -y git git-lfs i2c-tools v4l-utils device-tree-compiler gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good python3-pil python3-gi gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0
git lfs install
```

`git lfs install` ต้องขึ้น `Git LFS initialized.`

## 4. Clone repo และเตรียมไฟล์

```bash
git clone https://github.com/pppalzz03/Setup-J401.git $HOME/sensing-j401
cd $HOME/sensing-j401
git lfs pull
git lfs ls-files
```

`git lfs ls-files` ต้องแสดง `.ko` ครบ 4 ไฟล์ ถ้า repo เป็น private git จะถาม username/password ให้ใส่ GitHub username และ Personal Access Token (ไม่ใช่รหัสผ่าน GitHub)

ตั้งตัวแปรที่ใช้ทุกขั้นตอนต่อจากนี้ และบันทึกลง `~/.bashrc` เพื่อให้ terminal ที่เปิดใหม่มีตัวแปรเลย:

```bash
cat >> ~/.bashrc <<'EOF'
REPO=$HOME/sensing-j401
BSP=$REPO/jetpack-6.1-r36.4.2
EOF
source ~/.bashrc
echo "$REPO" "$BSP"
```

### 4.1 กรอกไฟล์ RELEASE

```bash
if [ ! -s $BSP/RELEASE ]; then
  head -n1 /etc/nv_tegra_release | grep -o '^# R[0-9]* (release), REVISION: [0-9.]*,' > $BSP/RELEASE
fi
cat $BSP/RELEASE
```

ดูค่า REVISION ที่ได้:

| ได้ | ทำต่อ |
|---|---|
| `REVISION: 4.2,` | ตรงกับชื่อโฟลเดอร์ ข้าม 4.2 ไปขั้นตอนที่ 5 ได้เลย |
| เลขอื่น เช่น `REVISION: 4.0,` | ทำ 4.2 ก่อน ห้ามข้าม |

### 4.2 ตรวจว่า binary โหลดได้บนเครื่องนี้ (ทำเมื่อ REVISION ไม่ใช่ 4.2)

R36.4.x ทุกรุ่นใช้ kernel `5.15.148-tegra` เหมือนกัน vermagic จึงแยกไม่ออก สคริปต์นี้เทียบ CRC ของ symbol ระหว่าง `.ko` ใน repo กับ kernel ของเครื่อง อ่านอย่างเดียว ไม่เปลี่ยนอะไรในเครื่อง

```bash
sudo apt-get install -y binutils
bash $REPO/common/helpers/check-abi.sh $BSP
```

ไม่ต้องติดตั้ง `nvidia-l4t-kernel-headers` เพิ่ม เพราะติดมากับการแฟลชแล้ว ถ้าสั่ง `apt-get install nvidia-l4t-kernel-headers` โดยไม่ระบุเวอร์ชัน apt จะพยายามดึงรุ่นใหม่กว่า (เช่น 36.4.7) แล้วขึ้น `unmet dependencies ... held broken packages` แปลว่า hold ในขั้นตอนที่ 2 ทำงานถูกต้อง ห้ามปลด hold

| บรรทัดสุดท้าย | ทำต่อ |
|---|---|
| `PASS: binary ชุดนี้โหลดได้บนเครื่องนี้` | ไปขั้นตอนที่ 5 ได้ ใช้ไฟล์ RELEASE ที่กรอกใน 4.1 ได้เลย **ห้าม commit** ไฟล์ RELEASE นี้ (โฟลเดอร์ยังชื่อ r36.4.2) ให้จดค่า REVISION ไว้ในตาราง "ผลทดสอบ" ท้ายไฟล์ |
| `FAIL: มี DIFF ห้ามติดตั้งต่อ` | หยุด ต้อง build โมดูลใหม่จาก source ของ L4T รุ่นที่เครื่องรายงาน หรือแฟลชเครื่องเป็นรุ่นที่ binary build มา ส่ง output ทั้งหมดให้ผู้ดูแล repo |
| `STOP: ...` | ทำตามข้อความ แล้วรันคำสั่งเดิมซ้ำ |

ถ้า REVISION เป็น 4.2 และอยากให้เครื่องถัดไปไม่ต้องกรอก RELEASE อีก ให้ commit ไฟล์นี้กลับเข้า repo (ต้องมีสิทธิ์ push):

```bash
cd $REPO
git add jetpack-6.1-r36.4.2/RELEASE
git -c user.name="nx_jp61" -c user.email="nx_jp61@jetson" commit -m "Set RELEASE from $(hostname)"
git push
```

## 5. ตรวจก่อนติดตั้ง

```bash
head -n1 /etc/nv_tegra_release
cat $BSP/RELEASE
test -s $BSP/RELEASE || echo "STOP: RELEASE ว่าง"
head -n1 /etc/nv_tegra_release | grep -qF "$(cat $BSP/RELEASE)" && echo "OK: L4T release ตรง" || echo "STOP: L4T release ไม่ตรง"

[ "$(uname -r)" = "5.15.148-tegra" ] && echo "OK: kernel" || echo "STOP: kernel"

(cd $BSP && sha256sum -c SHA256SUMS)

file $BSP/modules/*.ko $BSP/kernel/*.ko
file $REPO/common/loader/sensing-j401-load $REPO/common/capture/capture.sh $REPO/common/helpers/*.py

modinfo -F vermagic $BSP/modules/max96712.ko
modinfo -p $BSP/modules/sgx-yuv-gmsl2.ko | grep GMSLMODE_1

i2cdetect -l
ls /boot/dtb/
ls /lib/modules/5.15.148-tegra/updates/drivers/video/tegra/host/nvcsi/
```

ทุกข้อต้องผ่านก่อนไปต่อ:

| ตรวจ | ต้องได้ | ถ้าไม่ได้ |
|---|---|---|
| release | `OK: L4T release ตรง` และไม่มี `STOP: RELEASE ว่าง` | แฟลชผิดรุ่น หรือ `RELEASE` ไม่ตรงเครื่อง ดูหัวข้อ "ไฟล์ RELEASE" ท้ายไฟล์ |
| kernel | `OK: kernel` | หยุด |
| sha256sum | ทุกไฟล์ `OK` | `git lfs pull` ใหม่ หรือไฟล์ใน repo ถูกแก้ |
| `file` ของ .ko | `ELF ... aarch64` | ถ้าขึ้น `ASCII text` คือยังเป็น LFS pointer ให้ `git lfs pull` |
| `file` ของสคริปต์ | ไม่มีคำว่า `CRLF` | ไฟล์ถูกแก้บน Windows แล้ว commit แบบ CRLF ให้ตรวจ `.gitattributes` แล้ว clone ใหม่ |
| vermagic | ขึ้นต้นด้วย `5.15.148-tegra` | โมดูลไม่ใช่ของ kernel นี้ |
| GMSLMODE_1 | มีบรรทัด parameter | driver ไม่ใช่ชุด SENSING ที่รองรับ 3G |
| I2C | มี bus 9 ที่เป็น camera mux | ถ้าเลขต่าง ต้องแก้ `'9'` ใน helper ทั้งสองไฟล์ |
| โฟลเดอร์ `nvcsi/` | มี `nvhost-nvcsi-t194.ko` | ถ้าชื่อต่าง ให้ใช้ชื่อจริงในขั้นตอนที่ 6, 7, 14 |
| `/boot/dtb/` | มี `kernel_tegra234-p3768-0000+p3767-0000-nv.dtb` | ถ้าชื่อต่าง ใช้ชื่อจริงแทนในขั้นตอนที่ 9–10 |

## 6. สำรองของเดิม

```bash
B=$HOME/Downloads/sensing-before-install
mkdir -p $B
sudo cp -a /boot/extlinux/extlinux.conf $B/
sudo cp -a /boot/initrd $B/
sudo cp -a /lib/modules/5.15.148-tegra/updates/drivers/media/platform/tegra/camera/tegra-camera.ko $B/
sudo cp -a /lib/modules/5.15.148-tegra/updates/drivers/video/tegra/host/nvcsi/nvhost-nvcsi-t194.ko $B/
ls -l $B
```

## 7. ติดตั้ง camera stack

| ต้นทางใน repo | ปลายทางบน Jetson |
|---|---|
| `jetpack-6.1-r36.4.2/kernel/tegra-camera.ko` | `/lib/modules/5.15.148-tegra/updates/drivers/media/platform/tegra/camera/tegra-camera.ko` |
| `jetpack-6.1-r36.4.2/kernel/nvhost-nvcsi-t194.ko` | `/lib/modules/5.15.148-tegra/updates/drivers/video/tegra/host/nvcsi/nvhost-nvcsi-t194.ko` |

```bash
sudo install -m 644 $BSP/kernel/tegra-camera.ko /lib/modules/5.15.148-tegra/updates/drivers/media/platform/tegra/camera/tegra-camera.ko
sudo install -m 644 $BSP/kernel/nvhost-nvcsi-t194.ko /lib/modules/5.15.148-tegra/updates/drivers/video/tegra/host/nvcsi/nvhost-nvcsi-t194.ko
sudo depmod -a 5.15.148-tegra
sudo update-initramfs -u -k 5.15.148-tegra
```

## 8. ติดตั้ง SENSING driver, helper, loader และ service

| ต้นทางใน repo | ปลายทางบน Jetson | mode |
|---|---|---|
| `jetpack-6.1-r36.4.2/modules/max96712.ko` | `/usr/local/lib/sensing-j401/max96712.ko` | 644 |
| `jetpack-6.1-r36.4.2/modules/sgx-yuv-gmsl2.ko` | `/usr/local/lib/sensing-j401/sgx-yuv-gmsl2.ko` | 644 |
| `jetpack-6.1-r36.4.2/RELEASE` | `/usr/local/lib/sensing-j401/RELEASE` | 644 |
| `common/helpers/configure-2lane.py` | `/usr/local/lib/sensing-j401/configure-2lane.py` | 644 |
| `common/helpers/restore-serializer-address.py` | `/usr/local/lib/sensing-j401/restore-serializer-address.py` | 755 |
| `common/loader/sensing-j401-load` | `/usr/local/sbin/sensing-j401-load` | 755 |
| `common/systemd/sensing-camera-load.service` | `/etc/systemd/system/sensing-camera-load.service` | 644 |
| `common/capture/capture.sh` | `$HOME/Downloads/sensing-capture/capture.sh` | 755 |
| `common/capture/record-60s.py` | ใช้จาก repo ตรง ๆ | — |

```bash
sudo mkdir -p /usr/local/lib/sensing-j401
sudo install -m 644 $BSP/modules/max96712.ko $BSP/modules/sgx-yuv-gmsl2.ko $BSP/RELEASE /usr/local/lib/sensing-j401/
sudo install -m 644 $REPO/common/helpers/configure-2lane.py /usr/local/lib/sensing-j401/
sudo install -m 755 $REPO/common/helpers/restore-serializer-address.py /usr/local/lib/sensing-j401/
sudo install -m 755 $REPO/common/loader/sensing-j401-load /usr/local/sbin/sensing-j401-load
sudo install -m 644 $REPO/common/systemd/sensing-camera-load.service /etc/systemd/system/sensing-camera-load.service

mkdir -p $HOME/Downloads/sensing-capture
install -m 755 $REPO/common/capture/capture.sh $HOME/Downloads/sensing-capture/capture.sh
```

loader อ่าน `/usr/local/lib/sensing-j401/RELEASE` ตอนบูต ถ้าเครื่องถูกอัปเกรด L4T ไปรุ่นอื่น service จะหยุดก่อนโหลดโมดูล

## 9. Compile และติดตั้ง overlay

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

## 10. เพิ่ม boot entry ใน extlinux

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

## 11. เปิด service และ reboot

```bash
sudo systemctl daemon-reload
sudo systemctl enable sensing-camera-load.service
sudo reboot
```

## 12. ตรวจหลังบูต

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

## 13. ทดสอบภาพนิ่งและวิดีโอ

ภาพนิ่ง (สคริปต์ถาม sudo password แล้วสร้างโฟลเดอร์ใหม่ใต้ Downloads):

```bash
bash $HOME/Downloads/sensing-capture/capture.sh /dev/video2 1
```

วิดีโอ 60 วินาที (ผลอยู่ที่ `$HOME/Downloads/sensing-record-60s/`):

```bash
sudo python3 $REPO/common/capture/record-60s.py

gst-launch-1.0 -q \
  filesrc location=$HOME/Downloads/sensing-record-60s/capture.mkv ! \
  matroskademux ! jpegdec ! fakesink sync=false
```

เปิดดูภาพด้วยตาทุกครั้ง ไฟล์ขนาดครบหรือไม่มี error ยังไม่ใช่หลักฐานว่ารับภาพจริง คำสั่งแยกขั้นอยู่ในหัวข้อ 7–8 ของ `docs/SUCCESS-SETUP-jp62.md`

## 14. ถ้าต้องย้อนกลับ

ถ้าบูต entry `sensing-j9` ไม่ขึ้น เลือก `primary` จากเมนูทาง serial console (ttyTCU0) ภายใน 3 วินาที แล้ว:

```bash
B=$HOME/Downloads/sensing-before-install
sudo systemctl disable sensing-camera-load.service
sudo cp -a $B/extlinux.conf /boot/extlinux/extlinux.conf
sudo cp -a $B/initrd /boot/initrd
sudo cp -a $B/tegra-camera.ko /lib/modules/5.15.148-tegra/updates/drivers/media/platform/tegra/camera/tegra-camera.ko
sudo cp -a $B/nvhost-nvcsi-t194.ko /lib/modules/5.15.148-tegra/updates/drivers/video/tegra/host/nvcsi/nvhost-nvcsi-t194.ko
sudo depmod -a 5.15.148-tegra
sudo reboot
```

## 15. แก้ปัญหา

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
