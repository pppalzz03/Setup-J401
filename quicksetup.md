# Quick Setup — SENSING SG4A บน Seeed J401 (JetPack 6.1)

## User Requirement

**อุปกรณ์**

- Jetson Orin NX บน Seeed J401 แฟลช JetPack 6.1 (L4T R36.4.x) และผ่าน first-boot setup แล้ว
- บอร์ด SG4A-NONX-G2Y-A1 พร้อมไฟเลี้ยง กล้อง SG3S-ISX031C-GMSL2F ต่อที่ port 0–3 ของบอร์ด
- สาย CSI 22 pin to 15 pin จากบอร์ด SG4A เข้าช่อง J9 ของ J401 (ต่อก่อนเปิดเครื่อง)
- จอ + คีย์บอร์ดต่อ Jetson ถ้าต้องการดูภาพสด (ต้อง login หน้า desktop)

**เครือข่าย**

- Jetson ต่ออินเทอร์เน็ตได้ (ต้องเข้า github.com และ apt ของ Ubuntu/NVIDIA)
- คอมพิวเตอร์ของเราและ Jetson อยู่ในเครือข่ายเดียวกันเพื่อใช้ SSH
  - macOS ใช้ Terminal
  - Windows 10/11 ใช้ PowerShell

**ข้อมูลที่ต้องมี**

- `username` และรหัสผ่านของ Jetson (ตั้งไว้ตอน first-boot ดูด้วย `whoami` บน Jetson) ใช้ SSH และ `sudo`
- `ip_address` ของ Jetson (ดูด้วย `ifconfig` บน Jetson หลังคำว่า `inet` ใต้ `eth0` หรือ `wlan0`) ใช้ SSH


## Device Connection

<img src="img/diagramsystem.png" alt="รูปภาพตัวอย่าง" width="800" />

## 1. SSH เข้า Jetson

บนคอมพิวเตอร์ของเรา:

```bash
ssh username@ip_address
```

ครั้งแรกตอบ `yes` แล้วใส่รหัสผ่านของ Jetson

## 2. ติดตั้ง git และ clone repo

```bash
sudo apt-mark hold $(dpkg-query -W -f='${Package}\n' 'nvidia-l4t-kernel*' nvidia-l4t-display-kernel)
sudo apt-get update && sudo apt-get install -y git git-lfs && git lfs install
git clone https://github.com/pppalzz03/Setup-J401.git $HOME/sensing-j401
```

- `apt-mark hold` ต้องทำก่อนใช้ apt ครั้งแรก กันเครื่องถูกอัปเกรดไป JetPack 6.2 (ห้ามรัน `sudo apt upgrade` บนเครื่องนี้) คำสั่งนี้ล็อกทุก package `nvidia-l4t-kernel*` ที่ติดตั้งอยู่ในเครื่อง ชื่อ package แต่ละ image ไม่เหมือนกัน
- ถ้า `apt-get update` error `Release file ... is not valid yet` แปลว่าเวลาเครื่องผิด ให้รัน `sudo timedatectl set-ntp true` รอ 10 วินาทีแล้วรันใหม่

## 3. ติดตั้งทั้งหมด `setup.sh`

```bash
bash $HOME/sensing-j401/setup.sh
```

รันด้วย user ปกติ (ไม่ต้องใส่ `sudo` หน้าคำสั่ง) ก่อนเริ่มสคริปต์ถามรหัสผ่าน sudo และ 2 คำถามแรกในตาราง จากนั้นติดตั้ง 9 ขั้นต่อกันโดยแสดงความคืบหน้าบรรทัดเดียว ครบ 100% แสดงสรุปแล้วถามคำถามสุดท้าย

**คำถามที่สคริปต์ถาม** (ตอบ `y` หรือ `n` แล้ว Enter, Enter เฉยๆ = ค่าเริ่มต้น)

| คำถาม | ค่าเริ่มต้น | ความหมาย |
|---|---|---|
| เปิด reconnect อัตโนมัติเมื่อถอดเสียบสายกล้อง? | `Y` | เปิด `sensing-hotplug-watch` ถอดสายแล้วเสียบกลับ ภาพจะกลับมาเอง |
| เปิดภาพสดกล้องเองทุกครั้งที่บูต? | `N` | เปิด `sensing-cameras.service` ต้อง login desktop บนจอ Jetson |
| reboot ตอนนี้เลยไหม? | `N` | `y` = reboot ทันที, `n` = reboot เองภายหลังด้วย `sudo reboot` |

ระหว่างติดตั้ง:

```text
[#####.........................]  18%  2/9 ติดตั้ง package (หลายนาที) /
```

- รายละเอียดทุกคำสั่งอยู่ใน `~/sensing-setup.log` ไม่แสดงบนหน้าจอ
- ถ้าไม่ผ่าน สคริปต์หยุดและแสดง `FAIL` ขั้นที่หยุด เหตุผล และ log 15 บรรทัดล่าสุด แก้แล้วรันใหม่ได้ (ไม่ทับไฟล์สำรอง, boot entry และ RELEASE)

หลัง reboot รอ 1–2 นาทีแล้ว `ssh username@ip_address` เข้าใหม่


## 4. หลังบูต `afterboot.sh`

```bash
bash $HOME/sensing-j401/afterboot.sh
```

ตรวจระบบก่อน แล้วถามว่าจะทดลองใช้กล้องไหม:

1. **ตรวจ** L4T, kernel, overlay, service, driver (`max96712` ไม่ค้าง `-1`, `GMSLMODE_1=2,2,2,2`), dmesg และสถานะกล้องรายตัว port
2. **ถ่ายภาพนิ่งทดสอบ** ทุก port ที่มีกล้อง ต้องได้ `5,898,240 bytes`
3. **เปิดภาพสดจาก service** port ที่เลือก (ค่าเริ่มต้นคือ 2 port แรกที่มีกล้อง)



- `link no` + `detect error` = port นั้นไม่มีกล้อง ปกติ
- เปิด `frame-00.png` ดูด้วยตาทุกครั้ง ไฟล์ขนาดครบยังไม่ใช่หลักฐานว่าเห็นภาพจริง

ตัวเลือก:

```bash
bash $HOME/sensing-j401/afterboot.sh --check          # ตรวจอย่างเดียว
bash $HOME/sensing-j401/afterboot.sh --start "1 2"    # ตรวจแล้วเปิดภาพสด port 1, 2 เลย
```

## 5. ใช้งานกล้อง

กล้องแต่ละตัวเป็น service แยกกัน `sensing-stream@videoN` (N = port)

```bash
sudo sensing-cameras status          # port ไหนมีกล้อง / stream อยู่ไหม
sudo sensing-cameras start 1 2       # เปิดภาพสด port 1 และ 2 (ไม่ใส่เลข = ทุก port ที่มีกล้อง)
sudo sensing-cameras stop 2          # หยุด port 2 (ไม่ใส่เลข = หยุดทุกตัว)
sudo sensing-cameras restart 1       # เปิด port 1 ใหม่
```

- หยุดด้วย `sensing-cameras stop` หรือ `systemctl stop` เท่านั้น ถ้าปิดหน้าต่างภาพเอง service จะเปิดใหม่ภายใน 3 วินาที
- stream พร้อมกันได้ราว 2 กล้อง (CSI 2 lane)

ภาพนิ่งและวิดีโอ (port ที่จะใช้ต้องไม่ได้ stream อยู่):

```bash
bash $HOME/Downloads/sensing-capture/capture.sh /dev/video2 1    # ภาพนิ่ง port 2
sudo python3 $REPO/common/capture/record-60s.py                    # วิดีโอ 60 วินาที (port 2)
```

## 6. Reconnect เมื่อถอดเสียบสาย

ถ้าตอบ `y` เรื่อง reconnect ตอน `setup.sh` ถอดสายกล้องแล้วเสียบกลับ ภาพจะกลับมาเองภายในประมาณ 5–10 วินาที กล้องทุกตัวที่ stream อยู่จะสะดุดพร้อมกันชั่วครู่ เพราะ driver ตัวเดียวดูแลทั้ง 4 port

```bash
journalctl -u sensing-hotplug-watch.service -f                     # ดูการทำงาน
sudo systemctl enable --now sensing-hotplug-watch.service          # เปิดภายหลัง
sudo systemctl disable --now sensing-hotplug-watch.service         # ปิด
```

reconnect ด้วยมือ: `sudo sensing-cameras stop` → `sudo rmmod sgx_yuv_gmsl2` → `sudo systemctl restart sensing-camera-load.service` → `sudo sensing-cameras start` (**ห้าม `rmmod max96712`** โมดูลจะค้างจนกว่าจะ reboot)

รายละเอียด: `docs/HOTPLUG-RECONNECT.md`

---

`setup.sh` FAIL ดู `~/sensing-setup.log` · บูตไม่ขึ้นหรือถอนการติดตั้ง ดู README ข้อ 14 · ติดตั้งทีละคำสั่งด้วยมือ ดู `README.md`
