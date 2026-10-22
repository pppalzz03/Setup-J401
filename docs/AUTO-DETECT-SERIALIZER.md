# Auto detect serializer address (branch `feature/auto-detect-serializer`)

> **ไม่ได้อยู่ใน `main`** สคริปต์ที่อธิบายในหน้านี้อยู่ใน branch `feature/auto-detect-serializer` เท่านั้น `main` ใช้ `restore-serializer-address.py` ตัวเดิม เพราะทดสอบบนเครื่องจริงแล้วว่า reconnect ใช้ได้โดยไม่ต้องใช้ตัวนี้ (ดู `docs/HOTPLUG-RECONNECT.md` หัวข้อ "ต้องใช้ restore-serializer-address.py ไหม") เก็บหน้านี้ไว้เป็นข้อมูลอ้างอิง

`common/helpers/restore-serializer-address.py` เวอร์ชันนี้ตรวจทั้ง 4 port ของ MAX96712 ว่าแต่ละ port มีกล้องหรือไม่ และ serializer (MAX96717F) ของกล้องนั้นอยู่ที่ address อะไร ถ้าอยู่ที่ address อื่นที่ไม่ใช่ `0x40` จะย้ายกลับให้ ชื่อไฟล์เหมือนเดิม จึงไม่ต้องแก้ loader หรือ service

## ทำงานยังไง

1. ตรวจว่า driver กล้องไม่ได้โหลดอยู่ และมี MAX96712 (ID `0x20`)
2. อ่านสถานะ lock ทั้ง 4 port (reg `0x1a`, `0x0a`, `0x0b`, `0x0c` บิต `0x08`) port ที่ lock คือ port ที่มีกล้องต่อ
3. ทีละ port ที่ lock:
   - เปิด link เฉพาะ port นั้น (reg `0x0006` บิต 0–3) เพื่อให้มองเห็น serializer ได้ทีละตัว
   - ตรวจว่าหลังเปิด lock เหลือแค่ port นั้นจริง ถ้าไม่ใช่ แปลว่า register ไม่ได้ทำงานตามที่คาด จะหยุดทันทีโดยไม่ย้าย address
   - หา serializer ที่ `0x40` ก่อน ถ้าไม่เจอจะค้นหาในช่วง `0x41–0x4F` (เช็กแบบอ่านอย่างเดียวก่อน แล้วยืนยันด้วย ID `0xc8` และ reg `0x00`)
   - ถ้าอยู่ที่ address อื่น ให้ย้ายกลับ `0x40` (`--dry-run` จะรายงานอย่างเดียว)
4. คืนค่า reg `0x0006` เดิมทุกครั้ง แม้จะเกิด error ระหว่างทาง แล้วรอให้ link กลับมา lock

serializer ทุกตัวกลับไปอยู่ที่ `0x40` เหมือนตอนเปิดกล้องครั้งแรก ซึ่งเป็นสถานะที่ driver คาดไว้ตอน probe

## ตัวอย่างผลลัพธ์

```text
GMSL link enable 0xff, locked ports: [1, 2]
port 0: no link
port 1: recovered serializer 0x44 -> 0x40
port 2: serializer at 0x40; no change
port 3: no link
```

| ข้อความของแต่ละ port | ความหมาย |
|---|---|
| `no link` | ไม่มีกล้อง หรือสายไม่ได้ต่อ |
| `serializer at 0x40; no change` | อยู่ที่ค่าเริ่มต้นแล้ว |
| `recovered serializer 0x.. -> 0x40` | ย้ายกลับแล้ว |
| `serializer at 0x..; dry run, would move to 0x40` | `--dry-run` เจอแล้ว แต่ยังไม่ได้ย้าย |
| `serializer none; no change` | port lock แต่ไม่มี serializer ตอบในช่วงที่ค้นหา |
| `serializer many: [...]; no change` | เจอหลายตัวใน port เดียว ไม่แน่ใจว่าตัวไหน จึงไม่แตะ |
| `isolation failed (locked ports [...])` | เปิด link ทีละ port ไม่ได้ตามที่คาด หยุดโดยไม่ย้าย address |
| `not checked` / `skipped (time limit)` | ไม่ได้ตรวจ เพราะ port ก่อนหน้าหยุด หรือเกินเวลา 45 วินาที |
| `WARN: after restoring link enable ...` | หลังคืนค่า link บาง port ยังไม่กลับมา lock ให้ดู dmesg และสาย |

## ทดสอบบน Jetson

ทุกคำสั่งต้องรันตอนที่ driver ไม่ได้โหลด:

```bash
sudo rmmod sgx_yuv_gmsl2
sudo i2cdetect -y -r 9
sudo python3 $REPO/common/helpers/restore-serializer-address.py --dry-run
```

`--dry-run` ไม่ย้าย address แต่ยังสลับเปิด link ทีละ port ชั่วคราว แล้วคืนค่าเดิมให้

ถ้าผลถูกต้อง ให้ติดตั้งแล้วโหลด driver ใหม่:

```bash
sudo install -m 755 $REPO/common/helpers/restore-serializer-address.py /usr/local/lib/sensing-j401/
sudo systemctl restart sensing-camera-load.service
journalctl -b -u sensing-camera-load.service --no-pager | tail -n 20
bash $HOME/Downloads/sensing-capture/capture.sh /dev/video2 1
```

กรณีที่ควรทดสอบ:

1. รัน `--dry-run` ตามการต่อสายปัจจุบัน ดูว่ารายงานกล้องตรงกับที่ต่ออยู่จริงทุก port
2. `rmmod` แล้ว restart service โดยไม่ถอดสาย ต้องได้ `recovered ... -> 0x40` และ capture ได้
3. ถอดเสียบสาย ต้องได้ `serializer at 0x40; no change` และ capture ได้
4. reboot แล้ว capture ได้

## ย้อนกลับ

```bash
git -C $REPO show main:common/helpers/restore-serializer-address.py > /tmp/old.py
sudo install -m 755 /tmp/old.py /usr/local/lib/sensing-j401/restore-serializer-address.py
```

## ข้อจำกัด

- reg `0x0006` บิต 0–3 = link enable ของ port 0–3 ยังไม่ได้ยืนยันกับ datasheet สคริปต์จะตรวจตอนรันว่าหลังเขียนแล้ว lock เหลือ port เดียวจริง ถ้าไม่ใช่จะหยุดและคืนค่าเดิม
- `0xc8` (ID) และความหมายของ reg `0x00` มาจากสคริปต์เดิม
- สคริปต์นี้แค่ตรวจและคืน address ให้ serializer กลับไปอยู่ที่ `0x40` เหมือนตอนเปิดกล้อง overlay มีครบ 4 port แล้ว (driver probe `9-001a`–`9-001d` = `/dev/video0`–`/dev/video3`)
- บนเครื่องจริง driver ย้าย serializer ของ port 1 ไป `0x44` และ port 2 ไป `0x46` และใช้ reg `0x0006` เปิด link ทีละ port เหมือนที่สคริปต์นี้ใช้ (ดู dmesg ใน `docs/HOTPLUG-RECONNECT.md`)
- ชิปอื่นที่ตอบในช่วง `0x41–0x4F` อาจถูกเขียน register pointer ระหว่างอ่าน ID ให้ตรวจด้วย `i2cdetect` ก่อนใช้
- ทดสอบด้วย I2C จำลองแล้ว ได้แก่ กล้อง 1, 2, 4 ตัว, address ปนกัน, ทุกตัวอยู่ที่ `0x40`, มีชิปอื่นในช่วง, port lock แต่ serializer ไม่ตอบ และ register ไม่ทำงานตามที่คาด ยังไม่ได้ทดสอบบนฮาร์ดแวร์จริง
