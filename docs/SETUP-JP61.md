# SETUP JetPack 6.1 (R36.4.x) — checklist

ไฟล์นี้เป็น checklist สั้นสำหรับติดตั้งบนเครื่องจริง คำสั่งเต็มอยู่ใน `README.md` (อ้างเลขขั้นตอนเดียวกัน)

## ก่อน clone

- [ ] แฟลช JetPack 6.1 แล้ว `head -n1 /etc/nv_tegra_release` ขึ้น `R36` และ `uname -r` = `5.15.148-tegra`
- [ ] กรอก `jetpack-6.1-r36.4.2/RELEASE` ด้วยค่าจากเครื่องจริง (ดู "ไฟล์ RELEASE" ใน README) แล้วสร้าง `SHA256SUMS` ใหม่
- [ ] ชื่อโฟลเดอร์ `jetpack-6.1-r36.4.<rev>` ตรงกับ REVISION ใน RELEASE
- [ ] commit และ push จากเครื่องที่ติดตั้ง git-lfs แล้ว (`git lfs ls-files` ต้องเห็น `.ko` ทั้ง 4 ไฟล์)

## บน Jetson

- [ ] 1. `apt-mark hold` package L4T
- [ ] 2. ติดตั้ง dependencies, `git lfs pull`
- [ ] 3. ตรวจก่อนติดตั้ง — ทุกแถวในตารางผ่าน
- [ ] 4. สำรองของเดิมไว้ที่ `~/Downloads/sensing-before-install`
- [ ] 5. ติดตั้ง `tegra-camera.ko`, `nvhost-nvcsi-t194.ko`, `depmod`, `update-initramfs`
- [ ] 6. ติดตั้ง driver SENSING, helper, loader, service, `capture.sh`
- [ ] 7. compile overlay และ `fdtoverlay` ได้ `OK`
- [ ] 8. เพิ่ม entry `sensing-j9` ใน extlinux และตรวจตามรายการ
- [ ] 9. enable service แล้ว reboot
- [ ] 10. service `active (exited)`, `GMSLMODE_1 = 2,2,2,2`, `/dev/video2` NV16 1920×1536
- [ ] 11. ภาพนิ่งเห็นวัตถุจริง และวิดีโอ 60 วินาที decode ครบ
- [ ] กรอกตาราง "ผลทดสอบ" ท้าย README แล้ว commit

## บันทึกระหว่างติดตั้ง

| ขั้นตอน | วันที่ | ผล / ปัญหาที่เจอ |
|---|---|---|
| | | |
