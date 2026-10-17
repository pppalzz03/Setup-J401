#!/bin/bash
# Read-only check: will the .ko files in $1 (BSP folder) load on this kernel?
# 1) tegra-camera.ko / max96712.ko imports vs this machine's kernel + nvidia-oot
# 2) nvhost-nvcsi / sgx-yuv-gmsl2 imports vs the repo's tegra-camera.ko exports
# 3) stock modules on this machine that depend on tegra-camera vs the repo's tegra-camera.ko
set -u
BSP=${1:?usage: check-abi.sh <BSP folder>}
K=/lib/modules/$(uname -r)
command -v nm >/dev/null || { echo "STOP: ไม่มี nm ให้รัน sudo apt-get install -y binutils"; exit 2; }
SYMVERS=$(find /usr/src -name Module.symvers 2>/dev/null)
if [ -z "$SYMVERS" ]; then
  V=$(dpkg-query -W -f='${Version}' nvidia-l4t-kernel)
  echo "STOP: ไม่พบ Module.symvers ให้รัน (ระบุเวอร์ชันให้ตรงกับ kernel ของเครื่อง):"
  echo "  sudo apt-get install -y nvidia-l4t-kernel-headers=$V nvidia-l4t-kernel-oot-headers=$V"
  exit 2
fi
T=$(mktemp -d)
cat $SYMVERS | awk '{print $1, $2}' > $T/base.crc
nm "$BSP/kernel/tegra-camera.ko" | awk '/ __crc_/{sub("__crc_","",$3); print $1, $3}' > $T/cam.crc
FAIL=0
check() { # $1=ko  $2=crc table
  /sbin/modprobe --dump-modversions "$1" | awk '
    function n(x){x=tolower(x);sub(/^0x/,"",x);sub(/^0+/,"",x);return x}
    NR==FNR{c[$2]=n($1);next}
    ($2 in c){k++; if(c[$2]!=n($1)){d++;print "    DIFF "$2}}
    END{printf "    checked=%d diff=%d\n",k,d; exit (d>0)}' "$2" -
}
run() { echo "== $1"; check "$2" "$3" || FAIL=1; }
echo "[1] โมดูลใน repo เทียบกับ kernel/nvidia-oot ของเครื่อง"
run tegra-camera.ko "$BSP/kernel/tegra-camera.ko" $T/base.crc
run max96712.ko     "$BSP/modules/max96712.ko"   $T/base.crc
echo "[2] โมดูลใน repo เทียบกับ tegra-camera.ko ใน repo"
run nvhost-nvcsi-t194.ko "$BSP/kernel/nvhost-nvcsi-t194.ko" $T/cam.crc
run sgx-yuv-gmsl2.ko     "$BSP/modules/sgx-yuv-gmsl2.ko"    $T/cam.crc
echo "[3] โมดูลเดิมของเครื่องที่ใช้ tegra-camera เทียบกับ tegra-camera.ko ใน repo"
awk -F: '$2 ~ /tegra-camera\.ko/ {print $1}' $K/modules.dep | while read m; do
  [ "$(basename "$m")" = nvhost-nvcsi-t194.ko ] && continue
  echo "== $m"
  if ! check "$K/$m" $T/cam.crc; then
    case "$m" in
      */media/i2c/*) echo "    WARN: driver กล้องของ NVIDIA ตัวนี้จะโหลดไม่ได้หลังติดตั้ง (ไม่ได้ใช้กับ SENSING)"; echo x >> $T/warn3 ;;
      *) echo "    FAIL: โมดูลหลักของ camera stack"; echo x > $T/fail3 ;;
    esac
  fi
done
[ -f $T/fail3 ] && FAIL=1
WARN=$( [ -f $T/warn3 ] && wc -l < $T/warn3 || echo 0 )
rm -rf $T
echo
[ "$WARN" -gt 0 ] && echo "WARN: driver กล้องของ NVIDIA $WARN ตัวจะใช้ไม่ได้หลังติดตั้ง (imx219, imx477 ฯลฯ) ห้ามเปิด overlay กล้อง NVIDIA ผ่าน Jetson-IO"
[ $FAIL = 0 ] && echo "PASS: binary ชุดนี้โหลดได้บนเครื่องนี้" || { echo "FAIL: มี DIFF ห้ามติดตั้งต่อ"; exit 1; }
