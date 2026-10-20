# Auto detect serializer address (branch `feature/auto-detect-serializer`)

`common/helpers/restore-serializer-address.py` เวอร์ชันนี้ค้นหา address ของ serializer (MAX96717F) ในกล้องเอง แทนการเช็กแค่ `0x46` ชื่อไฟล์เหมือนเดิม จึงไม่ต้องแก้ loader หรือ service

## เปลี่ยนอะไร

| เรื่อง | เดิม | ใหม่ |
|---|---|---|
| address ที่ตรวจเมื่อ `0x40` ไม่ตอบ | `0x46` อย่างเดียว | ค้นหาทุก address ใน `0x41–0x4F` |
| การค้นหา | — | เช็กว่ามีชิปตอบแบบอ่านอย่างเดียวก่อน (`r1@addr` ไม่เขียน register) แล้วจึงอ่าน ID |
| ยืนยันว่าเป็น serializer | ID `0xc8` + reg `0x00` = `0x8c` | ID `0xc8` + reg `0x00` = address ของตัวเองเลื่อนบิตซ้าย 1 |
| เจอหลายตัว / ไม่เจอ | — | ไม่แก้อะไร |
| เวลาค้นหา | — | จำกัด 20 วินาที (service timeout คือ 60) |
| log | ไม่บอกสถานะ link | บอก port ที่ lock เช่น `GMSL link locked ports: [2]` |
| ทดสอบโดยไม่เขียนค่า | ไม่มี | `--dry-run` |

กรณี `0x46` ได้ข้อความ log เหมือนเดิมทุกตัวอักษร

## ทดสอบบน Jetson

ดูว่าบน bus 9 มีชิปอะไรอยู่บ้าง ถ้ามีชิปอื่นในช่วง `0x41–0x4F` ให้ตัด `CANDIDATES` ในสคริปต์ให้แคบลงก่อน:

```bash
sudo rmmod sgx_yuv_gmsl2
sudo i2cdetect -y -r 9
```

ลองแบบไม่เขียนค่า:

```bash
sudo python3 $REPO/common/helpers/restore-serializer-address.py --dry-run
```

ผ่านแล้วติดตั้งและโหลด driver ใหม่:

```bash
sudo install -m 755 $REPO/common/helpers/restore-serializer-address.py /usr/local/lib/sensing-j401/
sudo rmmod max96712
sudo systemctl restart sensing-camera-load.service
journalctl -b -u sensing-camera-load.service --no-pager | tail -n 20
```

ควรทดสอบ 2 กรณี:

1. ถอดเสียบสายกล้อง → ต้องได้ `Default serializer address responds; no change`
2. `rmmod` แล้ว restart service โดยไม่ถอดสาย → ต้องได้ `Recovered retained MAX96717F address 0x46 -> 0x40 before probe`

หลังทั้งสองกรณี `capture.sh` ต้องได้ภาพ

## ข้อความใน log

| ข้อความ | ความหมาย |
|---|---|
| `GMSL link locked ports: [2]` | กล้องต่อที่ port 2 (ปกติ) |
| `Default serializer address responds; no change` | serializer อยู่ที่ `0x40` อยู่แล้ว |
| `Recovered retained MAX96717F address 0x.. -> 0x40 before probe` | เจอที่ address อื่นและย้ายกลับแล้ว |
| `Dry run: would move MAX96717F 0x.. -> 0x40` | `--dry-run` เจอแล้ว แต่ไม่ได้เขียนค่า |
| `No camera link on port 2; retaining addresses` | สายไม่ได้ต่อ หรือต่อผิด port |
| `More than one camera link; retaining addresses` | ต่อกล้องหลายตัว สคริปต์นี้ไม่รองรับ |
| `Serializer search found 0 match(es) []; no change` | หาไม่เจอในช่วงที่ค้นหา |
| `Serializer search found N match(es) [...]; no change` | เจอหลายตัว ไม่แน่ใจว่าตัวไหน จึงไม่แตะ |

## ย้อนกลับ

```bash
git -C $REPO checkout main
sudo install -m 755 $REPO/common/helpers/restore-serializer-address.py /usr/local/lib/sensing-j401/
```

## ข้อจำกัด

- รองรับกล้องตัวเดียวที่ port 2 ตาม overlay `cam_2@1c`
- ชิปอื่นที่ตอบในช่วง `0x41–0x4F` และใช้ register 8 บิต อาจถูกเขียน register pointer ระหว่างอ่าน ID ให้ตรวจด้วย `i2cdetect` ก่อนใช้
- ค่า `0xc8` และความหมายของ reg `0x00` มาจากสคริปต์เดิม ยังไม่ได้เทียบกับ datasheet
- ตรวจ logic ด้วย I2C จำลองแล้ว (กรณี `0x40`, `0x46`, `0x4a`, มีชิปอื่นในช่วง, สายหลุด, 2 port, ไม่เจอ, ไม่มี MAX96712) ยังไม่ได้ทดสอบบนฮาร์ดแวร์จริง
