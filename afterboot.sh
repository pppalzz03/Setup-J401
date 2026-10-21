#!/bin/bash
# SENSING SG4A on Seeed J401 — check after reboot, then try the cameras.
#
#   bash afterboot.sh                 check, then ask: test capture / start live view
#   bash afterboot.sh --check         check only
#   bash afterboot.sh --start "1 2"   check, then start live view on port 1 and 2
#
# Run as the normal desktop user (not root). Uses sudo where needed.
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB=/usr/local/lib/sensing-j401
CAPTURE=$HOME/Downloads/sensing-capture/capture.sh
LOCK_REG=(0x1a 0x0a 0x0b 0x0c)
DT_CAM=${SENSING_DT_CAM:-/proc/device-tree/bus@0/cam_i2cmux/i2c@1/cam_2@1c}   # override for tests
SYSMOD=${SENSING_SYSMOD:-/sys/module}
DEV=${SENSING_DEV:-/dev}
MODE=ask; START_PORTS=""
case ${1:-} in
  --check) MODE=check ;;
  --start) MODE=start; START_PORTS=${2:-} ;;
  -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) echo "ไม่รู้จัก $1 (ดู --help)"; exit 2 ;;
esac
[ "$(id -u)" != 0 ] || { echo "รันด้วย user ปกติ ไม่ใช่ sudo/root:  bash $REPO/afterboot.sh"; exit 1; }

FAILS=0; WARNS=0
ok()   { echo "  OK   $*"; }
bad()  { echo "  FAIL $*"; FAILS=$((FAILS + 1)); }
warn() { echo "  WARN $*"; WARNS=$((WARNS + 1)); }
ask()  {
  local a d=$2 hint="[y/N]"; [ "$d" = y ] && hint="[Y/n]"
  printf '  ? %s %s ' "$1" "$hint"; read -r a </dev/tty 2>/dev/null || { a=""; echo; }
  a=${a:-$d}; [[ $a =~ ^[Yy] ]]
}
locked() {
  local v; v=$(sudo i2ctransfer -f -y 9 w2@0x6b 0x00 "${LOCK_REG[$1]}" r1 2>/dev/null) || return 1
  (( v & 8 ))
}

sudo -v || exit 1
echo "=== ตรวจระบบหลังบูต  $(date '+%F %T')"

# --- release / boot entry / overlay
REL=$(head -n1 /etc/nv_tegra_release)
if [ -s $LIB/RELEASE ] && grep -qF "$(cat $LIB/RELEASE)" <<<"$REL"; then ok "L4T ยังเป็นรุ่นเดิม: $(cat $LIB/RELEASE)"
else bad "L4T ไม่ตรงกับ $LIB/RELEASE (เครื่องถูกอัปเกรด? ตรวจ apt-mark showhold)"; fi
[ "$(uname -r)" = 5.15.148-tegra ] && ok "kernel 5.15.148-tegra" || bad "kernel $(uname -r)"
if [ -d "$DT_CAM" ]; then ok "overlay กล้องทำงาน (บูตด้วย sensing-j9)"
else bad "ไม่มี overlay กล้อง บูตด้วย entry อื่น? ตรวจ DEFAULT ใน /boot/extlinux/extlinux.conf"; fi

# --- loader service / drivers
if systemctl is-active --quiet sensing-camera-load.service; then ok "sensing-camera-load: active"
else bad "sensing-camera-load: $(systemctl is-active sensing-camera-load.service) (journalctl -b -u sensing-camera-load.service)"; fi
U=$(lsmod | awk '$1=="max96712"{print $3}')
case $U in
  "") bad "max96712 ไม่ได้โหลด" ;;
  -1) bad "max96712 ค้าง (refcount -1) ต้อง reboot ห้าม rmmod max96712" ;;
  *)  ok "max96712 โหลดแล้ว" ;;
esac
if [ -r $SYSMOD/sgx_yuv_gmsl2/parameters/GMSLMODE_1 ]; then
  M=$(cat $SYSMOD/sgx_yuv_gmsl2/parameters/GMSLMODE_1)
  [ "$M" = 2,2,2,2 ] && ok "sgx_yuv_gmsl2 โหลดแล้ว GMSLMODE_1=$M" || bad "GMSLMODE_1=$M ต้องเป็น 2,2,2,2"
else bad "sgx_yuv_gmsl2 ไม่ได้โหลด"; fi
E=$(sudo dmesg | grep -c -e 'disagrees about version of symbol' -e 'Invalid module format')
[ "$E" = 0 ] && ok "dmesg ไม่มี error ของโมดูล" || bad "dmesg มี error ของโมดูล $E บรรทัด (โมดูลกับ kernel ไม่ใช่ชุดเดียวกัน)"

# --- cameras per port
echo
echo "  port  link  probe          video        stream"
LINKED=""
for p in 0 1 2 3; do
  link=no; locked "$p" && { link=yes; LINKED="$LINKED $p"; }
  probe=$(sudo dmesg | grep -e "camera sgx-yuv-gmsl2-$p been detected" -e "camera sgx-yuv-gmsl2-$p detect error" | tail -1)
  case $probe in *detected*) probe=detected ;; *error*) probe="detect error" ;; *) probe="-" ;; esac
  [ -e "$DEV/video$p" ] && v=/dev/video$p || v=missing
  s=$(systemctl is-active sensing-stream@video$p.service 2>/dev/null); s=${s:-inactive}
  printf '  %-5s %-5s %-14s %-12s %s\n' "$p" "$link" "$probe" "$v" "$s"
  if [ $link = yes ] && [ "$probe" = "detect error" ]; then warn "port $p มีสายแต่ driver ตรวจไม่เจอกล้อง (dmesg: detect error)"; fi
done
LINKED=${LINKED# }
[ -n "$LINKED" ] && ok "พบกล้องที่ port: $LINKED" || bad "ไม่พบกล้องที่ port ไหนเลย ตรวจสาย GMSL และไฟเลี้ยงบอร์ด SG4A"

# --- extras
command -v fuser >/dev/null && ok "fuser (psmisc)" || warn "ไม่มี fuser: sudo apt-get install -y psmisc"
W=$(systemctl is-active sensing-hotplug-watch.service 2>/dev/null)
[ "$W" = active ] && ok "reconnect อัตโนมัติ: active" \
  || warn "reconnect อัตโนมัติ: ${W:-inactive} (เปิด: sudo systemctl enable --now sensing-hotplug-watch.service)"
XA=/run/user/$(id -u)/gdm/Xauthority
[ -f "$XA" ] && ok "login desktop บนจอ Jetson แล้ว (ภาพสดใช้ได้)" \
  || warn "ยังไม่ได้ login desktop บนจอ Jetson ภาพสดจะเปิดไม่ได้ (ถ่ายภาพนิ่งได้)"

echo
if [ $FAILS -gt 0 ]; then
  echo "=== ไม่ผ่าน $FAILS ข้อ ดู README ข้อ 15 (บูตไม่ขึ้น/ถอนการติดตั้ง: README ข้อ 14)"
  exit 1
fi
echo "=== ผ่าน (WARN $WARNS)"
[ $MODE = check ] && exit 0

# --- capture test
if [ $MODE = ask ] && [ -n "$LINKED" ] && ask "ถ่ายภาพนิ่งทดสอบทุก port ที่มีกล้อง ($LINKED)?" y; then
  for p in $LINKED; do
    if systemctl is-active --quiet sensing-stream@video$p.service; then echo "  port $p: กำลัง stream อยู่ ข้าม"; continue; fi
    R=$(bash "$CAPTURE" /dev/video$p 1 2>&1)
    B=$(grep -o 'capture.nv16: [0-9,]* bytes' <<<"$R")
    D=$(grep -o 'Output: .*' <<<"$R" | cut -d' ' -f2)
    if grep -q '5,898,240 bytes (expected' <<<"$R"; then ok "port $p: $B  ภาพ: $D/frame-00.png"
    else bad "port $p: ถ่ายภาพไม่ได้ ${B:-$(tail -1 <<<"$R")}"; fi
  done
  echo "  เปิด frame-00.png ดูด้วยตาว่าเห็นภาพจริง"
fi

# --- live view from service
if [ $MODE = ask ] && [ -n "$LINKED" ]; then
  DEF=$(echo $LINKED | cut -d' ' -f1-2)
  printf '  ? เปิดภาพสดจาก service port ไหน (เว้นวรรค, Enter = %s, n = ไม่เปิด) ' "$DEF"
  read -r START_PORTS </dev/tty 2>/dev/null || { START_PORTS=n; echo; }
  START_PORTS=${START_PORTS:-$DEF}
  [[ $START_PORTS =~ ^[Nn] ]] && START_PORTS=""
fi
if [ -n "$START_PORTS" ]; then
  [ -f "$XA" ] || warn "ยังไม่ได้ login desktop บนจอ Jetson ภาพสดอาจไม่ขึ้น"
  sudo sensing-cameras start $START_PORTS
fi

cat <<EOF

=== ใช้งานกล้อง
  sudo sensing-cameras status          ดูสถานะ
  sudo sensing-cameras start 1 2       เปิดภาพสด port 1, 2
  sudo sensing-cameras stop 2          หยุด port 2   (stop = หยุดทุกตัว)
  bash $CAPTURE /dev/videoN 1   ถ่ายภาพนิ่ง port N
EOF
[ "$FAILS" -eq 0 ]
