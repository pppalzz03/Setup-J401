# Quick Setup — SENSING SG4A บน Seeed J401 (JetPack 6.1)

ฉบับย่อของ `README.md` สำหรับคนที่เคยติดตั้งแล้ว รันบน Jetson ทีละกล่อง ตามลำดับ ดูผลที่ต้องได้ก่อนไปกล่องถัดไป ถ้าติดปัญหาให้ดูข้อเดียวกันใน `README.md`
<img src="img/diagramsystem.png" alt="รูปภาพตัวอย่าง" width="800" />

## 0. SSH เข้า Jetson

บน Jetson ดู user และ IP:

```bash
whoami
ifconfig
```

บนคอมพิวเตอร์ของเรา:

```bash
ssh user@ip
```

## 1. ตรวจเครื่อง + ล็อก package + ติดตั้ง dependencies

```bash
head -n1 /etc/nv_tegra_release
uname -r
ping -c 3 github.com
timedatectl

sudo apt-mark hold nvidia-l4t-display-kernel nvidia-l4t-kernel nvidia-l4t-kernel-dtbs nvidia-l4t-kernel-headers nvidia-l4t-kernel-oot-headers nvidia-l4t-kernel-oot-module
apt-mark showhold

sudo apt-get update
sudo apt-get install -y git git-lfs i2c-tools v4l-utils device-tree-compiler gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good python3-pil python3-gi gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0
git lfs install
```

ต้องได้:
- `# R36 (release), REVISION: 4.` และ `5.15.148-tegra`
- ping ได้ และ `System clock synchronized: yes` (ถ้า `no` รัน `sudo timedatectl set-ntp true` แล้วรันกล่องนี้ใหม่)
- `showhold` ครบ 6 package
- `Git LFS initialized.`

> ห้ามรัน `sudo apt upgrade` บนเครื่องนี้

## 2. Clone repo + ตั้งตัวแปร + กรอก RELEASE 

```bash
git clone https://github.com/pppalzz03/Setup-J401.git $HOME/sensing-j401
cd $HOME/sensing-j401
git lfs pull
git lfs ls-files

grep -q 'REPO=$HOME/sensing-j401' ~/.bashrc || cat >> ~/.bashrc <<'EOF'
REPO=$HOME/sensing-j401
BSP=$REPO/jetpack-6.1-r36.4.2
EOF
source ~/.bashrc
echo "$REPO" "$BSP"

if [ ! -s $BSP/RELEASE ]; then
  head -n1 /etc/nv_tegra_release | grep -o '^# R[0-9]* (release), REVISION: [0-9.]*,' > $BSP/RELEASE
fi
git -C $REPO update-index --skip-worktree jetpack-6.1-r36.4.2/RELEASE
cat $BSP/RELEASE
```

ต้องได้:
- `git lfs ls-files` มี `.ko` ครบ 4 ไฟล์
- `echo` แสดง path 2 ตัว (ไม่ว่าง)
- `cat` ได้บรรทัดเดียว เช่น `# R36 (release), REVISION: 4.0,`

**ถ้า REVISION ไม่ใช่ `4.2`** ต้องรันเพิ่ม และต้องได้ `PASS` ถ้าได้ `FAIL` ห้ามติดตั้งต่อ:

```bash
sudo apt-get install -y binutils
bash $REPO/common/helpers/check-abi.sh $BSP
```

## 3. ตรวจก่อนติดตั้ง 

```bash
test -s $BSP/RELEASE && head -n1 /etc/nv_tegra_release | grep -qF "$(cat $BSP/RELEASE)" && echo "OK: L4T release ตรง" || echo "STOP: RELEASE ว่าง หรือไม่ตรงกับเครื่อง (ทำ 4.1 ใหม่)"
[ "$(uname -r)" = "5.15.148-tegra" ] && echo "OK: kernel" || echo "STOP: kernel"
(cd $BSP && sha256sum -c SHA256SUMS)
file $BSP/modules/*.ko $BSP/kernel/*.ko
i2cdetect -l
ls /boot/dtb/
ls /lib/modules/5.15.148-tegra/updates/drivers/video/tegra/host/nvcsi/
```

ต้องได้:
- `OK: L4T release ตรง`, `OK: kernel`
- sha256sum ทุกไฟล์ `OK`, `.ko` ทุกไฟล์เป็น `ELF ... aarch64`
- มี bus `i2c-9`, มี `kernel_tegra234-p3768-0000+p3767-0000-nv.dtb`, มี `nvhost-nvcsi-t194.ko`

มีข้อไหนไม่ผ่าน หยุดแล้วดูตารางใน README ข้อ 5

## 4. สำรอง + ติดตั้ง camera stack + driver

> รันกล่องนี้ครั้งเดียว ถ้ารันซ้ำ ไฟล์สำรองจะถูกทับด้วยไฟล์ใหม่

```bash
B=$HOME/Downloads/sensing-before-install
mkdir -p $B
sudo cp -a /boot/extlinux/extlinux.conf $B/
sudo cp -a /boot/initrd $B/
sudo cp -a /lib/modules/5.15.148-tegra/updates/drivers/media/platform/tegra/camera/tegra-camera.ko $B/
sudo cp -a /lib/modules/5.15.148-tegra/updates/drivers/video/tegra/host/nvcsi/nvhost-nvcsi-t194.ko $B/
ls -l $B

sudo install -m 644 $BSP/kernel/tegra-camera.ko /lib/modules/5.15.148-tegra/updates/drivers/media/platform/tegra/camera/tegra-camera.ko
sudo install -m 644 $BSP/kernel/nvhost-nvcsi-t194.ko /lib/modules/5.15.148-tegra/updates/drivers/video/tegra/host/nvcsi/nvhost-nvcsi-t194.ko
sudo depmod -a 5.15.148-tegra
sudo update-initramfs -u -k 5.15.148-tegra

sudo mkdir -p /usr/local/lib/sensing-j401
sudo install -m 644 $BSP/modules/max96712.ko $BSP/modules/sgx-yuv-gmsl2.ko $BSP/RELEASE /usr/local/lib/sensing-j401/
sudo install -m 644 $REPO/common/helpers/configure-2lane.py /usr/local/lib/sensing-j401/
sudo install -m 755 $REPO/common/helpers/restore-serializer-address.py /usr/local/lib/sensing-j401/
sudo install -m 755 $REPO/common/loader/sensing-j401-load /usr/local/sbin/sensing-j401-load
sudo install -m 644 $REPO/common/systemd/sensing-camera-load.service /etc/systemd/system/sensing-camera-load.service

mkdir -p $HOME/Downloads/sensing-capture
install -m 755 $REPO/common/capture/capture.sh $HOME/Downloads/sensing-capture/capture.sh
```

ต้องได้:
- `ls -l $B` มีครบ 4 ไฟล์
- `update-initramfs` ไม่มี error
- ไม่มี `cannot stat`

## 5. Overlay + boot entry

**5.1 compile และทดสอบ overlay**

```bash
dtc -@ -I dts -O dtb -o /tmp/sensing-j401-j9-2lane.dtbo $REPO/common/dts/sensing-j401-j9-2lane.dts

fdtoverlay \
  -i /boot/dtb/kernel_tegra234-p3768-0000+p3767-0000-nv.dtb \
  -o /tmp/sensing-merged-check.dtb \
  /tmp/sensing-j401-j9-2lane.dtbo && echo "OK: overlay apply ได้"

dtc -I dtb -O dts /tmp/sensing-merged-check.dtb 2>/dev/null | grep -c -e 'cam_2@1c' -e 'serial_c'
```

ต้องได้ `OK: overlay apply ได้` และตัวเลขมากกว่า 0 (warning ของ dtc ไม่เป็นไร) ถ้าไม่ได้ หยุด

**5.2 ติดตั้ง overlay + ดึงบรรทัด APPEND**

```bash
sudo install -m 644 /tmp/sensing-j401-j9-2lane.dtbo /boot/sensing-j401-j9-2lane.dtbo
sudo cp -a /boot/extlinux/extlinux.conf /boot/extlinux/extlinux.conf.before-sensing
APPEND_LINE=$(awk '/^LABEL primary/{f=1} f && /APPEND/{print; exit}' /boot/extlinux/extlinux.conf)
echo "$APPEND_LINE"
```

ต้องได้บรรทัด `APPEND ${cbootargs} root=PARTUUID=...` ถ้าว่าง หยุด

**5.3 เพิ่ม entry** (terminal เดียวกับ 5.2 รันครั้งเดียว)

```bash
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

ต้องได้:
- `DEFAULT sensing-j9`
- มี entry `sensing-j9` แค่ entry เดียว และมีบรรทัด `APPEND`
- ยังมี `LABEL primary`

## 6. เปิด service + reboot (README ข้อ 11)

```bash
sudo systemctl daemon-reload
sudo systemctl enable sensing-camera-load.service
sudo reboot
```

รอ 1–2 นาที แล้ว `ssh user@ip` เข้าใหม่

## 7. ตรวจหลังบูต 

```bash
systemctl status sensing-camera-load.service --no-pager
sudo dmesg | grep -i -e disagrees -e 'Invalid module'
cat /sys/module/sgx_yuv_gmsl2/parameters/GMSLMODE_1
v4l2-ctl -d /dev/video2 --get-fmt-video
```

ต้องได้:
- `Active: active (exited)`
- `dmesg` ไม่แสดงอะไร
- `2,2,2,2`
- `Width/Height : 1920/1536` และ `Pixel Format : 'NV16'`

## 8. ทดสอบภาพ

ภาพนิ่ง:

```bash
bash $HOME/Downloads/sensing-capture/capture.sh /dev/video2 1
```

ต้องได้ `capture.nv16: 5,898,240 bytes (expected 5,898,240)` แล้วเปิด `frame-00.png` ใน `~/Downloads/sensing-photo/<วันเวลา>/` ดูว่าเห็นภาพจริง

วิดีโอ 60 วินาที (ไม่บังคับ):

```bash
sudo python3 $REPO/common/capture/record-60s.py
```

ต้องได้ `"errors": []` และ `average_fps` ใกล้ 30

ภาพสดบนจอ Jetson (ไม่บังคับ ต้อง login หน้า desktop ก่อน กด `Ctrl+C` เพื่อหยุด):

```bash
bash $REPO/common/capture/stream.sh
```

---

บูตไม่ขึ้นหรืออยากถอนการติดตั้ง ดู README ข้อ 14 · เจอ error ดู README ข้อ 15
