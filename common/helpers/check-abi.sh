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
[ -n "$SYMVERS" ] || { echo "STOP: ไม่พบ Module.symvers ให้รัน sudo apt-get install -y nvidia-l4t-kernel-headers nvidia-l4t-kernel-oot-headers"; exit 2; }
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
  echo "== $m"; check "$K/$m" $T/cam.crc || echo FAIL > $T/fail3
done
[ -f $T/fail3 ] && FAIL=1
rm -rf $T
echo
[ $FAIL = 0 ] && echo "PASS: binary ชุดนี้โหลดได้บนเครื่องนี้" || { echo "FAIL: มี DIFF ห้ามติดตั้งต่อ"; exit 1; }
