# SETUP JetPack 6.1 (R36.4.x) — checklist

ไฟล์นี้เป็น checklist สั้นสำหรับติดตั้งบนเครื่องจริง คำสั่งเต็มอยู่ใน `README.md` (เลขขั้นตอนตรงกัน)

## ก่อน clone (บน Windows)

- [ ] push commit ล่าสุดขึ้น GitHub จากเครื่องที่ติดตั้ง git-lfs แล้ว (`git lfs ls-files` ต้องเห็น `.ko` ทั้ง 4 ไฟล์)

## บน Jetson ที่เพิ่งแฟลช

- [ ] 1. `nv_tegra_release` เป็น R36, `uname -r` = `5.15.148-tegra`, ต่อเน็ตได้, เวลาถูกต้อง
- [ ] 2. `apt-mark hold` ทุก package `nvidia-l4t-kernel*` ที่ติดตั้งอยู่ + `nvidia-l4t-display-kernel`
- [ ] 3. ติดตั้ง git, git-lfs, dependencies และ `git lfs install`
- [ ] 4. clone repo, `git lfs pull`, ตั้ง `REPO`/`BSP` ใน `~/.bashrc`
- [ ] 4.1 กรอก `RELEASE` จากเครื่องจริง
- [ ] 4.2 ถ้า REVISION ไม่ใช่ 4.2: `check-abi.sh` ต้องได้ `PASS`
- [ ] 5. ตรวจก่อนติดตั้ง — ทุกแถวในตารางผ่าน
- [ ] 6. สำรองของเดิมไว้ที่ `~/Downloads/sensing-before-install`
- [ ] 7. ติดตั้ง `tegra-camera.ko`, `nvhost-nvcsi-t194.ko`, `depmod`, `update-initramfs`
- [ ] 8. ติดตั้ง driver SENSING, helper, loader, service, `capture.sh`
- [ ] 9. compile overlay และ `fdtoverlay` ได้ `OK`
- [ ] 10. เพิ่ม entry `sensing-j9` ใน extlinux และตรวจตามรายการ
- [ ] 11. enable service แล้ว reboot
- [ ] 12. service `active (exited)`, `GMSLMODE_1 = 2,2,2,2`, `/dev/video2` NV16 1920×1536
- [ ] 13. ภาพนิ่งเห็นวัตถุจริง และวิดีโอ 60 วินาที decode ครบ
- [ ] กรอกตาราง "ผลทดสอบ" ท้าย README แล้ว commit

## บันทึกระหว่างติดตั้ง

| ขั้นตอน | วันที่ | ผล / ปัญหาที่เจอ |
|---|---|---|
| | | |
