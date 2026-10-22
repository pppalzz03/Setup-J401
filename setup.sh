#!/bin/bash
# SENSING SG4A on Seeed J401 (JetPack 6.1) — one-shot setup.
# Does quicksetup steps 1-6 (README 1-11): check the Jetson, hold L4T packages,
# install packages, prepare the repo, pre-install checks, back up, install the
# camera stack / drivers / services, overlay + boot entry, enable services,
# then asks before rebooting. After the reboot run ./afterboot.sh.
#
# Run as the normal desktop user (not root):   bash ~/sensing-j401/setup.sh
# The screen shows a 0-100% progress line and a summary at the end; every
# command's output goes to ~/sensing-setup.log.
# Safe to run again: backup, boot entry and RELEASE are not overwritten.
set -Eeuo pipefail

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

# ------------------------------------------------------------------ screen / log
# fd 3 = screen, everything else = log
[ "$(id -u)" != 0 ] || { echo "รันด้วย user ปกติ ไม่ใช่ sudo/root:  bash $REPO/setup.sh"; exit 1; }
exec 3>&1
: > "$LOG"
TTY=0; [ -t 3 ] && TTY=1
PCT=0; MSG=""; SUMMARY=()

say()  { printf '%s\n' "$*" >&3; }
bar()  {   # redraw the progress line
  local w=30 n=$((PCT * 30 / 100)) spin=${1:-}
  local fill empty
  fill=$(printf '%*s' "$n" '' | tr ' ' '#'); empty=$(printf '%*s' $((w - n)) '' | tr ' ' '.')
  if [ $TTY = 1 ]; then printf '\r\033[K[%s%s] %3d%%  %s %s' "$fill" "$empty" "$PCT" "$MSG" "$spin" >&3
  else printf '[%3d%%] %s\n' "$PCT" "$MSG" >&3; fi
}
progress() { PCT=$1; MSG=$2; echo; echo "=== [$PCT%] $MSG"; bar; }
ok()   { echo "  OK   $*"; SUMMARY+=("$*"); }
info() { echo "  ..   $*"; }
fail() {
  echo "  FAIL $*"
  [ $TTY = 1 ] && printf '\n' >&3
  say ""
  say "FAIL  [$PCT%] $MSG"
  say "      $*"
  say ""
  say "----- log ล่าสุด ($LOG) -----"
  tail -n 15 "$LOG" | grep -v '^=== ' >&3 || true
  say "------------------------------"
  say "แก้แล้วรันใหม่ได้: bash $REPO/setup.sh   (ดู README ข้อ 15)"
  exit 1
}
trap 'fail "คำสั่งล้มเหลว (setup.sh บรรทัด $LINENO)"' ERR

run_long() {   # run_long "message" cmd... : spinner on screen, output to log
  local m=$1; shift
  MSG=$m; echo "  ..   $m"
  "$@" &
  local pid=$! s='|/-\' i=0
  while kill -0 $pid 2>/dev/null; do
    [ $TTY = 1 ] && bar "${s:i++%4:1}"
    sleep 0.3
  done
  wait $pid
}

ask()  {   # ask "question" default(y|n) -> 0 for yes
  local a d=$2 hint="[y/N]"; [ "$d" = y ] && hint="[Y/n]"
  printf '  ? %s %s ' "$1" "$hint" >&3
  read -r a 2>/dev/null </dev/tty || { a=""; echo >&3; }
  a=${a:-$d}; [[ $a =~ ^[Yy] ]]
}

# ------------------------------------------------------------------ questions first
say "SENSING J401 setup  —  log: $LOG"
say ""
sudo -v
say ""
say "ตอบ 2 ข้อก่อนเริ่ม (Enter = ค่าในวงเล็บที่เป็นตัวใหญ่):"
WATCH=n; ask "เปิด reconnect อัตโนมัติเมื่อถอดเสียบสายกล้อง (sensing-hotplug-watch)?" y && WATCH=y
BOOTCAM=n; ask "เปิดภาพสดกล้องเองทุกครั้งที่บูต (sensing-cameras.service)?" n && BOOTCAM=y
say ""
exec >>"$LOG" 2>&1
echo "sensing-j401 setup $(date '+%F %T')  user=$(whoami)  repo=$REPO  watch=$WATCH bootcam=$BOOTCAM"
while true; do sudo -n true; sleep 50; kill -0 $$ 2>/dev/null || exit; done &
KEEP=$!

# ------------------------------------------------------------------ 1
progress 2 "1/9 ตรวจเครื่อง"
REL=$(head -n1 /etc/nv_tegra_release)
echo "  $REL"
[[ $REL == "# R36 (release), REVISION: 4."* ]] && ok "L4T R36.4.x" || fail "ไม่ใช่ JetPack 6.1 (R36.4.x): $REL"
[ "$(uname -r)" = "$KVER" ] && ok "kernel $KVER" || fail "kernel เป็น $(uname -r) ต้องเป็น $KVER"
ping -c 2 -W 3 github.com && ok "อินเทอร์เน็ต" || fail "ping github.com ไม่ได้ ตรวจเน็ต"
if ! timedatectl show -p NTPSynchronized --value | grep -q yes; then
  info "เวลายังไม่ซิงก์ เปิด NTP แล้วรอ"
  sudo timedatectl set-ntp true
  for _ in $(seq 30); do timedatectl show -p NTPSynchronized --value | grep -q yes && break; sleep 2; done
fi
timedatectl show -p NTPSynchronized --value | grep -q yes && ok "เวลาซิงก์แล้ว" \
  || fail "เวลาไม่ซิงก์ (apt จะ error) ตั้งเวลาให้ถูกแล้วรันใหม่"

# ------------------------------------------------------------------ 2
progress 6 "2/9 ล็อก package L4T"
mapfile -t HOLD < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' "${HOLD_PATTERNS[@]}" 2>/dev/null \
                    | awk '$1 ~ /^[ih]i/ {print $2}')
printf '%s\n' "${HOLD[@]}" | grep -qx nvidia-l4t-kernel || fail "ไม่พบ package nvidia-l4t-kernel ในเครื่อง"
sudo apt-mark hold "${HOLD[@]}"
MISSING=$(comm -23 <(printf '%s\n' "${HOLD[@]}" | sort) <(apt-mark showhold | sort))
[ -z "$MISSING" ] && ok "hold ${#HOLD[@]} package L4T" || fail "hold ไม่ครบ: $MISSING"
echo "  held: ${HOLD[*]}"

progress 10 "2/9 apt-get update"
run_long "2/9 apt-get update" sudo apt-get update -q || fail "apt-get update ไม่ผ่าน (เน็ตหรือเวลาเครื่อง)"
progress 18 "2/9 ติดตั้ง package (หลายนาที)"
run_long "2/9 ติดตั้ง package (หลายนาที)" sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${PKGS[@]}" \
  || fail "apt-get install ไม่ผ่าน"
git lfs install && ok "ติดตั้ง package ${#PKGS[@]} ตัว + git-lfs"

# ------------------------------------------------------------------ 3
progress 42 "3/9 ดึงไฟล์ driver (git lfs)"
run_long "3/9 ดึงไฟล์ driver (git lfs)" git -C "$REPO" lfs pull || fail "git lfs pull ไม่ผ่าน"
for f in "$BSP"/modules/*.ko "$BSP"/kernel/*.ko; do
  file "$f" | grep -q 'ELF 64-bit.*aarch64' || fail "$(basename "$f") ไม่ใช่ไฟล์ driver (ยังเป็น LFS pointer?)"
done
ok "ไฟล์ .ko ครบ 4 ไฟล์"
progress 46 "3/9 ตั้งค่า repo + RELEASE"
grep -qs '^REPO=' ~/.bashrc || printf 'REPO=%s\nBSP=$REPO/jetpack-6.1-r36.4.2\n' "$REPO" >> ~/.bashrc
if [ ! -s "$BSP/RELEASE" ]; then
  echo "$REL" | grep -o '^# R[0-9]* (release), REVISION: [0-9.]*,' > "$BSP/RELEASE"
fi
git -C "$REPO" update-index --skip-worktree jetpack-6.1-r36.4.2/RELEASE
ok "RELEASE: $(cat "$BSP/RELEASE")"
if ! grep -q 'REVISION: 4.2,' "$BSP/RELEASE"; then
  progress 48 "3/9 ตรวจ binary กับ kernel (check-abi)"
  run_long "3/9 ตรวจ binary กับ kernel (check-abi)" bash "$REPO/common/helpers/check-abi.sh" "$BSP" \
    || fail "check-abi ไม่ผ่าน ห้ามติดตั้ง ส่ง $LOG ให้ผู้ดูแล repo"
  ok "check-abi: PASS"
fi

# ------------------------------------------------------------------ 4
progress 52 "4/9 ตรวจก่อนติดตั้ง"
echo "$REL" | grep -qF "$(cat "$BSP/RELEASE")" || fail "RELEASE ไม่ตรงกับเครื่อง"
(cd "$BSP" && sha256sum -c SHA256SUMS) || fail "sha256sum ไม่ผ่าน (git lfs pull ใหม่)"
for f in common/loader/sensing-j401-load common/capture/*.sh common/helpers/*.py common/hotplug/*; do
  file "$REPO/$f" | grep -q CRLF && fail "$f เป็น CRLF (clone ใหม่)"
done
modinfo -F vermagic "$BSP/modules/max96712.ko" | grep -q "^$KVER" || fail "vermagic ของ driver ไม่ใช่ $KVER"
modinfo -p "$BSP/modules/sgx-yuv-gmsl2.ko" | grep -q GMSLMODE_1 || fail "driver ไม่มี GMSLMODE_1"
i2cdetect -l | grep -q '^i2c-9' || fail "ไม่มี I2C bus 9"
[ -f "$DTB" ] || fail "ไม่มี $DTB"
[ -f "$CSI_KO" ] && [ -f "$CAM_KO" ] || fail "ไม่มีโมดูล camera เดิมของเครื่อง"
ok "ตรวจก่อนติดตั้ง 9 ข้อ (RELEASE, sha256, CRLF, vermagic, GMSLMODE_1, I2C 9, DTB, โมดูลเดิม)"

# ------------------------------------------------------------------ 5
progress 56 "5/9 สำรองของเดิม"
if [ -s "$BACKUP/extlinux.conf" ] && [ -s "$BACKUP/tegra-camera.ko" ]; then
  ok "มีไฟล์สำรองอยู่แล้ว ไม่ทับ: $BACKUP"
else
  mkdir -p "$BACKUP"
  sudo cp -a "$EXTLINUX" /boot/initrd "$CAM_KO" "$CSI_KO" "$BACKUP/"
  ok "สำรอง 4 ไฟล์: $BACKUP"
fi

# ------------------------------------------------------------------ 6
progress 60 "6/9 ติดตั้ง camera stack"
sudo install -m 644 "$BSP/kernel/tegra-camera.ko" "$CAM_KO"
sudo install -m 644 "$BSP/kernel/nvhost-nvcsi-t194.ko" "$CSI_KO"
sudo depmod -a "$KVER"
progress 63 "6/9 สร้าง initrd ใหม่ (ประมาณ 1 นาที)"
run_long "6/9 สร้าง initrd ใหม่ (ประมาณ 1 นาที)" sudo update-initramfs -u -k "$KVER" || fail "update-initramfs ไม่ผ่าน"
ok "camera stack + initrd"

progress 76 "6/9 ติดตั้ง driver, loader, service"
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
ok "driver, loader, sensing-cameras, watcher, service"

# ------------------------------------------------------------------ 7
progress 82 "7/9 overlay"
dtc -q -@ -I dts -O dtb -o /tmp/sensing-j401-j9-2lane.dtbo "$REPO/common/dts/sensing-j401-j9-2lane.dts"
fdtoverlay -i "$DTB" -o /tmp/sensing-merged-check.dtb /tmp/sensing-j401-j9-2lane.dtbo \
  || fail "overlay apply กับ base DTB ไม่ได้ ห้ามใส่ใน extlinux"
N=$(dtc -I dtb -O dts /tmp/sensing-merged-check.dtb 2>/dev/null | grep -c -e 'cam_2@1c' -e 'serial_c' || true)
[ "$N" -gt 0 ] || fail "ไม่พบ node กล้องหลัง apply overlay"
sudo install -m 644 /tmp/sensing-j401-j9-2lane.dtbo "$DTBO"
ok "overlay ทดสอบกับ base DTB ผ่าน และติดตั้งแล้ว"

# ------------------------------------------------------------------ 8
progress 88 "8/9 boot entry (extlinux)"
if grep -q '^LABEL sensing-j9' "$EXTLINUX"; then
  E="มีอยู่แล้ว"
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
  E="เพิ่มใหม่"
fi
sudo sed -i 's/^DEFAULT .*/DEFAULT sensing-j9/' "$EXTLINUX"
grep -q '^DEFAULT sensing-j9' "$EXTLINUX" || fail "ตั้ง DEFAULT sensing-j9 ไม่ได้"
[ "$(grep -c '^LABEL sensing-j9' "$EXTLINUX")" = 1 ] || fail "entry sensing-j9 ซ้ำ (คืน $EXTLINUX.before-sensing แล้วรันใหม่)"
grep -q '^LABEL primary' "$EXTLINUX" || fail "ไม่มี LABEL primary"
PARTUUID=$(sudo blkid -s PARTUUID -o value "$(findmnt -no SOURCE /)")
awk '/^LABEL sensing-j9/{f=1} f && /APPEND/{print; exit}' "$EXTLINUX" | grep -q "$PARTUUID" \
  || fail "PARTUUID ใน entry sensing-j9 ไม่ตรงกับเครื่อง ($PARTUUID)"
ok "boot entry sensing-j9 ($E) เป็น DEFAULT, PARTUUID ตรง, ยังมี primary"

# ------------------------------------------------------------------ 9
progress 95 "9/9 เปิด service"
sudo systemctl daemon-reload
sudo systemctl enable sensing-camera-load.service
if [ $WATCH = y ]; then sudo systemctl enable sensing-hotplug-watch.service; W=เปิด
else sudo systemctl disable sensing-hotplug-watch.service || true; W=ปิด; fi
if [ $BOOTCAM = y ]; then sudo systemctl enable sensing-cameras.service; C=เปิด
else sudo systemctl disable sensing-cameras.service || true; C=ปิด; fi
ok "service: โหลด driver ตอนบูต=เปิด, reconnect อัตโนมัติ=$W, ภาพสดตอนบูต=$C"

trap - ERR
kill $KEEP 2>/dev/null || true
progress 100 "เสร็จ"
[ $TTY = 1 ] && printf '\n' >&3
echo "setup finished $(date '+%F %T')"

# ------------------------------------------------------------------ summary
say ""
say "=== ผลการติดตั้ง"
for s in "${SUMMARY[@]}"; do say "  OK  $s"; done
say ""
say "  log ทั้งหมด:    $LOG"
say "  ไฟล์สำรอง:     $BACKUP"
say "  ถ้าบูตไม่ขึ้น:  เลือก primary จาก serial console แล้วดู README ข้อ 14"
say ""
say "ต้อง reboot เพื่อใช้ driver, initrd และ overlay ใหม่ หลังบูตรัน:  bash $REPO/afterboot.sh"
if ask "reboot ตอนนี้เลยไหม?" n; then
  say "  reboot ... รอ 1-2 นาทีแล้ว ssh เข้าใหม่"
  sleep 2
  sudo reboot
else
  say "  ยังไม่ reboot  รันเองเมื่อพร้อม:  sudo reboot"
fi
