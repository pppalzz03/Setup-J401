#!/bin/bash
# SENSING SG4A on Seeed J401 (JetPack 6.1) — one-shot setup.
# Does quicksetup steps 1-6 (README 1-11): check the Jetson, hold L4T packages,
# install packages, prepare the repo, pre-install checks, back up, install the
# camera stack / drivers / services, overlay + boot entry, enable services,
# then asks before rebooting. After the reboot run ./afterboot.sh.
#
# Run as the normal desktop user (not root):   bash ~/sensing-j401/setup.sh
# Safe to run again: backup, boot entry and RELEASE are not overwritten.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BSP=$REPO/jetpack-6.1-r36.4.2
KVER=5.15.148-tegra
LIB=/usr/local/lib/sensing-j401
MODDIR=/lib/modules/$KVER/updates/drivers
CAM_KO=$MODDIR/media/platform/tegra/camera/tegra-camera.ko
CSI_KO=$MODDIR/video/tegra/host/nvcsi/nvhost-nvcsi-t194.ko
DTB=/boot/dtb/kernel_tegra234-p3768-0000+p3767-0000-nv.dtb
DTBO=/boot/sensing-j401-j9-2lane.dtbo
EXTLINUX=/boot/extlinux/extlinux.conf
BACKUP=$HOME/Downloads/sensing-before-install
LOG=$HOME/sensing-setup.log
# L4T kernel packages to hold: every installed nvidia-l4t-kernel* plus the display
# kernel. Found from dpkg so a package name that this image does not have
# (e.g. nvidia-l4t-kernel-oot-module vs -oot-modules) does not stop the setup.
HOLD_PATTERNS=('nvidia-l4t-kernel*' nvidia-l4t-display-kernel)
PKGS=(git git-lfs i2c-tools v4l-utils device-tree-compiler gstreamer1.0-tools
      gstreamer1.0-plugins-base gstreamer1.0-plugins-good python3-pil python3-gi
      gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0 psmisc binutils)

STEP=""
step() { STEP=$1; echo; echo "=== $1"; }
ok()   { echo "  OK   $*"; }
info() { echo "  ..   $*"; }
fail() { echo "  FAIL $*"; echo; echo "หยุดที่: $STEP  (log: $LOG, ดู README ข้อ 15)"; exit 1; }
ask()  {   # ask "question" default(y|n) -> 0 for yes
  local a d=$2 hint="[y/N]"; [ "$d" = y ] && hint="[Y/n]"
  printf '  ? %s %s ' "$1" "$hint"; read -r a </dev/tty 2>/dev/null || { a=""; echo; }
  a=${a:-$d}; [[ $a =~ ^[Yy] ]]
}
trap 'echo; echo "  FAIL คำสั่งล้มเหลว (บรรทัด $LINENO) ใน: $STEP  (log: $LOG)"' ERR

[ "$(id -u)" != 0 ] || { echo "รันด้วย user ปกติ ไม่ใช่ sudo/root:  bash $REPO/setup.sh"; exit 1; }
exec > >(tee -a "$LOG") 2>&1
echo "sensing-j401 setup $(date '+%F %T')  user=$(whoami)  repo=$REPO"

sudo -v
while true; do sudo -n true; sleep 50; kill -0 $$ 2>/dev/null || exit; done 2>/dev/null &

# ---------------------------------------------------------------- 1
step "1/9 ตรวจเครื่อง"
REL=$(head -n1 /etc/nv_tegra_release)
echo "  $REL"
[[ $REL == "# R36 (release), REVISION: 4."* ]] && ok "L4T R36.4.x" || fail "ไม่ใช่ JetPack 6.1 (R36.4.x)"
[ "$(uname -r)" = "$KVER" ] && ok "kernel $KVER" || fail "kernel เป็น $(uname -r) ต้องเป็น $KVER"
ping -c 2 -W 3 github.com >/dev/null 2>&1 && ok "อินเทอร์เน็ต" || fail "ping github.com ไม่ได้ ตรวจเน็ต"
if ! timedatectl show -p NTPSynchronized --value | grep -q yes; then
  info "เวลายังไม่ซิงก์ เปิด NTP แล้วรอ"
  sudo timedatectl set-ntp true
  for _ in $(seq 30); do timedatectl show -p NTPSynchronized --value | grep -q yes && break; sleep 2; done
fi
timedatectl show -p NTPSynchronized --value | grep -q yes && ok "เวลา $(date '+%F %T')" \
  || fail "เวลาไม่ซิงก์ (apt จะ error) ตั้งเวลาให้ถูกแล้วรันใหม่"

# ---------------------------------------------------------------- 2
step "2/9 ล็อก package L4T + ติดตั้ง package"
mapfile -t HOLD < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' "${HOLD_PATTERNS[@]}" 2>/dev/null \
                    | awk '$1 ~ /^[ih]i/ {print $2}')
printf '%s\n' "${HOLD[@]}" | grep -qx nvidia-l4t-kernel || fail "ไม่พบ package nvidia-l4t-kernel (ไม่ใช่เครื่องที่แฟลชด้วย SDK Manager / L4T?)"
sudo apt-mark hold "${HOLD[@]}" >/dev/null
MISSING=$(comm -23 <(printf '%s\n' "${HOLD[@]}" | sort) <(apt-mark showhold | sort))
[ -z "$MISSING" ] && ok "hold ${#HOLD[@]} package: ${HOLD[*]}" || fail "hold ไม่ครบ: $MISSING"
info "apt-get update / install (หลายนาที)"
sudo apt-get update -q
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${PKGS[@]}"
git lfs install >/dev/null && ok "package + git-lfs"

# ---------------------------------------------------------------- 3
step "3/9 เตรียม repo + RELEASE"
git -C "$REPO" lfs pull
for f in "$BSP"/modules/*.ko "$BSP"/kernel/*.ko; do
  file "$f" | grep -q 'ELF 64-bit.*aarch64' || fail "$f ไม่ใช่ไฟล์ driver (ยังเป็น LFS pointer?)"
done
ok ".ko ครบ 4 ไฟล์"
grep -qs '^REPO=' ~/.bashrc || printf 'REPO=%s\nBSP=$REPO/jetpack-6.1-r36.4.2\n' "$REPO" >> ~/.bashrc
ok "ตัวแปร REPO / BSP ใน ~/.bashrc"
if [ ! -s "$BSP/RELEASE" ]; then
  echo "$REL" | grep -o '^# R[0-9]* (release), REVISION: [0-9.]*,' > "$BSP/RELEASE"
fi
git -C "$REPO" update-index --skip-worktree jetpack-6.1-r36.4.2/RELEASE
ok "RELEASE: $(cat "$BSP/RELEASE")"
if ! grep -q 'REVISION: 4.2,' "$BSP/RELEASE"; then
  info "REVISION ไม่ใช่ 4.2 ตรวจว่า binary โหลดได้ (check-abi)"
  bash "$REPO/common/helpers/check-abi.sh" "$BSP" || fail "check-abi ไม่ผ่าน ห้ามติดตั้ง ส่ง log ให้ผู้ดูแล repo"
fi

# ---------------------------------------------------------------- 4
step "4/9 ตรวจก่อนติดตั้ง"
echo "$REL" | grep -qF "$(cat "$BSP/RELEASE")" && ok "RELEASE ตรงกับเครื่อง" || fail "RELEASE ไม่ตรงกับเครื่อง"
(cd "$BSP" && sha256sum --quiet -c SHA256SUMS) && ok "sha256sum" || fail "sha256sum ไม่ผ่าน (git lfs pull ใหม่)"
for f in common/loader/sensing-j401-load common/capture/*.sh common/helpers/*.py common/hotplug/*; do
  file "$REPO/$f" | grep -q CRLF && fail "$f เป็น CRLF (clone ใหม่)"
done
ok "สคริปต์ไม่มี CRLF"
modinfo -F vermagic "$BSP/modules/max96712.ko" | grep -q "^$KVER" && ok "vermagic" || fail "vermagic ไม่ใช่ $KVER"
modinfo -p "$BSP/modules/sgx-yuv-gmsl2.ko" | grep -q GMSLMODE_1 && ok "driver รองรับ GMSLMODE_1" || fail "ไม่มี GMSLMODE_1"
i2cdetect -l | grep -q '^i2c-9' && ok "I2C bus 9" || fail "ไม่มี I2C bus 9"
[ -f "$DTB" ] && ok "base DTB" || fail "ไม่มี $DTB"
[ -f "$CSI_KO" ] && [ -f "$CAM_KO" ] && ok "โมดูล camera เดิมของเครื่อง" || fail "ไม่มี $CSI_KO หรือ $CAM_KO"

# ---------------------------------------------------------------- 5
step "5/9 สำรองของเดิม"
if [ -s "$BACKUP/extlinux.conf" ] && [ -s "$BACKUP/tegra-camera.ko" ]; then
  ok "มีสำรองอยู่แล้วที่ $BACKUP (ไม่ทับ)"
else
  mkdir -p "$BACKUP"
  sudo cp -a "$EXTLINUX" /boot/initrd "$CAM_KO" "$CSI_KO" "$BACKUP/"
  ok "สำรอง 4 ไฟล์ไว้ที่ $BACKUP"
fi

# ---------------------------------------------------------------- 6
step "6/9 ติดตั้ง camera stack + driver + service"
sudo install -m 644 "$BSP/kernel/tegra-camera.ko" "$CAM_KO"
sudo install -m 644 "$BSP/kernel/nvhost-nvcsi-t194.ko" "$CSI_KO"
sudo depmod -a "$KVER"
info "update-initramfs (ประมาณ 1 นาที)"
sudo update-initramfs -u -k "$KVER" >/dev/null
ok "tegra-camera.ko, nvhost-nvcsi-t194.ko, initrd"

sudo mkdir -p "$LIB"
sudo install -m 644 "$BSP/modules/max96712.ko" "$BSP/modules/sgx-yuv-gmsl2.ko" "$BSP/RELEASE" \
                    "$REPO/common/helpers/configure-2lane.py" "$LIB/"
sudo install -m 755 "$REPO/common/helpers/restore-serializer-address.py" "$REPO/common/capture/stream.sh" "$LIB/"
sudo install -m 755 "$REPO/common/loader/sensing-j401-load" /usr/local/sbin/
sudo install -m 755 "$REPO/common/hotplug/sensing-cameras" "$REPO/common/hotplug/sensing-hotplug-watch" /usr/local/sbin/
sudo install -m 644 "$REPO"/common/systemd/sensing-camera-load.service \
                    "$REPO"/common/systemd/sensing-hotplug-watch.service \
                    "$REPO"/common/systemd/sensing-cameras.service \
                    "$REPO"/common/systemd/sensing-stream@.service /etc/systemd/system/
sudo sed -i "s/^Environment=SUDO_UID=.*/Environment=SUDO_UID=$(id -u)/" /etc/systemd/system/sensing-stream@.service
mkdir -p "$HOME/Downloads/sensing-capture"
install -m 755 "$REPO/common/capture/capture.sh" "$HOME/Downloads/sensing-capture/"
ok "driver, loader, sensing-cameras, watcher, service (SUDO_UID=$(id -u))"

# ---------------------------------------------------------------- 7
step "7/9 compile + ทดสอบ + ติดตั้ง overlay"
dtc -q -@ -I dts -O dtb -o /tmp/sensing-j401-j9-2lane.dtbo "$REPO/common/dts/sensing-j401-j9-2lane.dts"
fdtoverlay -i "$DTB" -o /tmp/sensing-merged-check.dtb /tmp/sensing-j401-j9-2lane.dtbo \
  || fail "overlay apply กับ base DTB ไม่ได้ ห้ามใส่ใน extlinux"
N=$(dtc -I dtb -O dts /tmp/sensing-merged-check.dtb 2>/dev/null | grep -c -e 'cam_2@1c' -e 'serial_c' || true)
[ "$N" -gt 0 ] && ok "overlay apply ได้ (พบ node กล้อง $N)" || fail "ไม่พบ node กล้องหลัง apply"
sudo install -m 644 /tmp/sensing-j401-j9-2lane.dtbo "$DTBO"
ok "ติดตั้ง $DTBO"

# ---------------------------------------------------------------- 8
step "8/9 boot entry (extlinux)"
if grep -q '^LABEL sensing-j9' "$EXTLINUX"; then
  ok "มี entry sensing-j9 อยู่แล้ว (ไม่เพิ่มซ้ำ)"
else
  [ -f "$EXTLINUX.before-sensing" ] || sudo cp -a "$EXTLINUX" "$EXTLINUX.before-sensing"
  APPEND_LINE=$(awk '/^LABEL primary/{f=1} f && /APPEND/{print; exit}' "$EXTLINUX")
  [[ $APPEND_LINE == *APPEND* ]] || fail "หา APPEND ของ entry primary ไม่เจอ"
  sudo tee -a "$EXTLINUX" >/dev/null <<EOF

LABEL sensing-j9
      MENU LABEL SENSING J401 J9 2-lane
      LINUX /boot/Image
      FDT $DTB
      INITRD /boot/initrd
${APPEND_LINE}
      OVERLAYS $DTBO
EOF
  ok "เพิ่ม entry sensing-j9"
fi
sudo sed -i 's/^DEFAULT .*/DEFAULT sensing-j9/' "$EXTLINUX"
grep -q '^DEFAULT sensing-j9' "$EXTLINUX" && ok "DEFAULT sensing-j9" || fail "ตั้ง DEFAULT ไม่ได้"
[ "$(grep -c '^LABEL sensing-j9' "$EXTLINUX")" = 1 ] && ok "entry sensing-j9 มีอันเดียว" || fail "entry sensing-j9 ซ้ำ"
grep -q '^LABEL primary' "$EXTLINUX" && ok "ยังมี LABEL primary (ทางหนี)" || fail "ไม่มี LABEL primary"
PARTUUID=$(sudo blkid -s PARTUUID -o value "$(findmnt -no SOURCE /)")
awk '/^LABEL sensing-j9/{f=1} f && /APPEND/{print; exit}' "$EXTLINUX" | grep -q "$PARTUUID" \
  && ok "root=PARTUUID=$PARTUUID" || fail "PARTUUID ใน entry sensing-j9 ไม่ตรงกับเครื่อง"

# ---------------------------------------------------------------- 9
step "9/9 เปิด service"
sudo systemctl daemon-reload
sudo systemctl enable sensing-camera-load.service >/dev/null 2>&1
ok "sensing-camera-load (โหลด driver ตอนบูต)"
if ask "เปิด reconnect อัตโนมัติเมื่อถอดเสียบสายกล้อง (sensing-hotplug-watch)?" y; then
  sudo systemctl enable sensing-hotplug-watch.service >/dev/null 2>&1; ok "sensing-hotplug-watch: enable"
else
  sudo systemctl disable sensing-hotplug-watch.service >/dev/null 2>&1 || true; info "sensing-hotplug-watch: ไม่เปิด"
fi
if ask "เปิดภาพสดกล้องเองทุกครั้งที่บูต (sensing-cameras.service)?" n; then
  sudo systemctl enable sensing-cameras.service >/dev/null 2>&1; ok "sensing-cameras: enable"
else
  sudo systemctl disable sensing-cameras.service >/dev/null 2>&1 || true; info "sensing-cameras: ไม่เปิดตอนบูต (เปิดเองด้วย afterboot.sh)"
fi

echo
echo "=== ติดตั้งเสร็จ  (log: $LOG)"
echo "  ต้อง reboot เพื่อใช้ driver, initrd และ overlay ใหม่"
echo "  ถ้าบูตไม่ขึ้น: เลือก primary จาก serial console แล้วดู README ข้อ 14"
echo "  หลังบูต:  bash $REPO/afterboot.sh"
trap - ERR
if ask "reboot ตอนนี้เลยไหม?" n; then
  echo "  reboot ... รอ 1-2 นาทีแล้ว ssh เข้าใหม่"
  sleep 2
  sudo reboot
else
  echo "  ยังไม่ reboot  รันเองเมื่อพร้อม:  sudo reboot"
fi
