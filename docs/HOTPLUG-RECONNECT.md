# Hot-plug reconnect (branch `feature/hotplug-reconnect`)

> branch ทดลอง แตกมาจาก `feature/auto-detect-serializer` ห้าม merge เข้า `main` จนกว่าจะทดสอบบนเครื่องจริงผ่าน

## กล้อง GMSL2 reconnect ได้ไหม

ได้ แต่ต้องโหลด driver ใหม่ทุกครั้ง

- **link GMSL2:** เมื่อเสียบสายกลับ MAX96712 กับ serializer จะ lock กันใหม่เอง ไม่ต้องสั่งอะไร
- **ตัวกล้อง:** ได้ไฟเลี้ยงผ่านสาย coax ถอดสายเท่ากับปิดกล้อง ค่าที่ driver ตั้งไว้ตอน probe จึงหายหมด (address ของ serializer, register ของ sensor, โหมดส่งภาพ)
- **driver:** `sgx-yuv-gmsl2` ไม่รู้ว่ากล้องถูกปิดเปิด ภาพจึงค้าง ต้อง `rmmod` แล้วโหลดใหม่ให้มันตั้งค่ากล้องอีกรอบ

`sensing-hotplug-watch` ทำขั้นตอนนี้ให้อัตโนมัติ ถ้า driver หรือ SDK ของ SENSING รองรับ hot-plug เอง จะดีกว่าวิธีนี้ ควรสอบถาม SENSING ด้วย

## ทำงานยังไง

```text
ทุก 1 วินาที อ่าน lock ของ port 0–3 (MAX96712 reg 0x1a/0x0a/0x0b/0x0c บิต 0x08)
├─ port หาย        → log "cable lost" และหยุด APP_SERVICE
└─ port กลับมา lock นิ่ง 3 วินาที (หรือมี port ใหม่)
     → หยุด APP_SERVICE
     → rmmod sgx_yuv_gmsl2 (ไม่ถอด max96712)
     → systemctl restart sensing-camera-load.service
        (restore-serializer-address.py ตรวจทั้ง 4 port → insmod → ตั้ง 2-lane)
     → ตรวจว่ามี /dev/video2
     → เริ่ม APP_SERVICE
     ไม่สำเร็จ → ลองใหม่ทุก 15 วินาที สูงสุด 3 ครั้ง
```

ไม่ถอด `max96712` เพราะจากการทดสอบบนเครื่องจริง `rmmod max96712` ทำให้โมดูลค้างที่ refcount `-1` โหลดใหม่ไม่ได้จนกว่าจะ reboot และไม่มี `/dev/video2` ส่วน deserializer อยู่บนบอร์ด SG4A จึงไม่ดับตอนถอดสายกล้อง loader ตั้งค่า 2-lane ให้ใหม่อยู่แล้ว

ถอดแล้วเสียบกลับเร็วกว่า 3 วินาทีก็ยัง reconnect เพราะ watcher จำไว้ว่า port นั้นเคยหลุด

## ไฟล์

| ไฟล์ใน repo | ติดตั้งที่ |
|---|---|
| `common/hotplug/sensing-hotplug-watch` | `/usr/local/sbin/sensing-hotplug-watch` (755) |
| `common/systemd/sensing-hotplug-watch.service` | `/etc/systemd/system/sensing-hotplug-watch.service` (644) |
| `common/systemd/sensing-stream.service` (ตัวอย่าง APP_SERVICE) | `/etc/systemd/system/sensing-stream.service` (644) |
| `common/capture/stream.sh` | `/usr/local/lib/sensing-j401/stream.sh` (755) ใช้กับ `sensing-stream.service` |
| `common/helpers/restore-serializer-address.py` (ตรวจทั้ง 4 port) | `/usr/local/lib/sensing-j401/` (755) |

## ทดสอบ

ต้องผ่านการทดสอบใน `docs/AUTO-DETECT-SERIALIZER.md` และ reconnect ด้วยมือให้ได้ภาพก่อน

**1. ติดตั้งไฟล์** (ยังไม่ enable service)

```bash
git -C $REPO fetch && git -C $REPO checkout feature/hotplug-reconnect
sudo install -m 755 $REPO/common/helpers/restore-serializer-address.py /usr/local/lib/sensing-j401/
sudo install -m 755 $REPO/common/hotplug/sensing-hotplug-watch /usr/local/sbin/sensing-hotplug-watch
sudo install -m 644 $REPO/common/systemd/sensing-hotplug-watch.service /etc/systemd/system/
sudo systemctl daemon-reload
```

**2. dry run** ใช้ดูว่าตรวจเจอการถอดและเสียบสายถูกต้องหรือไม่ แต่ยังไม่ทำอะไรจริง

```bash
sudo /usr/local/sbin/sensing-hotplug-watch --dry-run
```

ถอดสายกล้อง → รอ 5 วินาที → เสียบกลับ → ต้องเห็น:

```text
link change: locked ports [2] -> none
  cable lost on port [2]
no camera link; waiting for a cable
link change: locked ports none -> [2]
cable back on port [2], stable 3s: reconnecting
  dry run: rmmod sgx_yuv_gmsl2
  ...
reconnect done
```

กด `Ctrl+C` เพื่อหยุด

**3. รันจริงใน terminal**

```bash
sudo /usr/local/sbin/sensing-hotplug-watch
```

ถอดเสียบสายเหมือนข้อ 2 แล้วเปิด terminal อีกหน้าต่าง ถ่ายภาพ:

```bash
bash $HOME/Downloads/sensing-capture/capture.sh /dev/video2 1
```

ต้องเห็น `reconnect done` และภาพจริง ลองถอดเสียบหลายรอบติดกัน และลองถอดแล้วเสียบกลับเร็วๆ

**4. เปิดเป็น service**

```bash
sudo systemctl enable --now sensing-hotplug-watch.service
journalctl -u sensing-hotplug-watch.service -f
```

## ทดสอบกับภาพสด (stream)

ให้ watcher หยุดและเริ่ม stream ให้เอง ต้องให้ stream รันเป็น systemd service เพราะระหว่างที่ `stream.sh` เปิด `/dev/video2` อยู่ `rmmod sgx_yuv_gmsl2` จะไม่ผ่าน

ต้อง login หน้า desktop บนจอ Jetson ไว้ก่อน และใช้ `id -u` ดู uid ของ user นั้น ถ้าไม่ใช่ `1000` ให้แก้ `SUDO_UID` ใน `sensing-stream.service`

```bash
sudo install -m 755 $REPO/common/capture/stream.sh /usr/local/lib/sensing-j401/stream.sh
sudo install -m 644 $REPO/common/systemd/sensing-stream.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start sensing-stream.service
systemctl status sensing-stream.service --no-pager
```

ต้องมีหน้าต่างภาพสดบนจอ Jetson แล้วรัน watcher โดยบอกชื่อ service ของ stream:

```bash
sudo APP_SERVICE=sensing-stream.service /usr/local/sbin/sensing-hotplug-watch
```

ถอดสาย port 2 → หน้าต่างภาพปิด → เสียบกลับ → ประมาณ 5–10 วินาทีหน้าต่างภาพขึ้นใหม่ log ต้องเห็น:

```text
  cable lost on port [2]
  stop sensing-stream.service: ok
cable back on port [2], stable 3s: reconnecting
  stop sensing-stream.service: ok
  loader: SENSING drivers loaded in GMSL2/3G mode on ...
  loader: MAX96712: 2 lanes, MIPI output enabled
  start sensing-stream.service: ok
reconnect done
```

ใช้แบบถาวร: ตั้ง `Environment=APP_SERVICE=sensing-stream.service` ใน `sensing-hotplug-watch.service` แล้ว

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now sensing-stream.service sensing-hotplug-watch.service
```

หยุด stream: `sudo systemctl stop sensing-stream.service`

## ตั้งค่า

แก้ใน `/etc/systemd/system/sensing-hotplug-watch.service` แล้ว `sudo systemctl daemon-reload && sudo systemctl restart sensing-hotplug-watch.service`

| ค่า | ค่าเริ่มต้น | ความหมาย |
|---|---|---|
| `APP_SERVICE` | ว่าง | service ที่ใช้กล้อง watcher จะหยุดตอนสายหลุดและเริ่มใหม่หลัง reconnect ถ้าโปรแกรมไม่ได้รันเป็น service ต้องปิดเองก่อน ไม่อย่างนั้น `rmmod` จะไม่ผ่าน (log บอก PID ที่ใช้ `/dev/video2` อยู่) |
| `POLL` | 1 | ตรวจทุกกี่วินาที |
| `STABLE` | 3 | lock ต้องนิ่งกี่วินาทีก่อน reconnect |
| `RETRY` / `MAX_RETRY` | 15 / 3 | เวลารอและจำนวนครั้งที่ลองใหม่เมื่อ reconnect ไม่สำเร็จ |
| `VIDEO` | `/dev/video2` | อุปกรณ์ที่ต้องมีหลัง reconnect |
| `UNLOAD_MODULES` | `sgx_yuv_gmsl2` | โมดูลที่ถอดก่อนโหลดใหม่ ห้ามใส่ `max96712` |

## ข้อจำกัด

- reconnect คือโหลด driver ทั้งชุดใหม่ ถ้ามีหลายกล้อง เสียบสายใหม่ตัวเดียว ภาพของทุกกล้องจะหยุดชั่วครู่ด้วย
- overlay ตอนนี้มีแค่ `cam_2@1c` watcher เห็นทั้ง 4 port แต่ได้ภาพแค่กล้องที่ port 2
- ถ้า driver ไม่รองรับ `rmmod` ขณะทำงาน (`rmmod` ค้างหรือ dmesg มี error) วิธีนี้ใช้ไม่ได้ ต้อง reboot และถาม SENSING
- watcher อ่าน register ของ MAX96712 ขณะ driver โหลดอยู่ (อ่านอย่างเดียว ทุก 1 วินาที) ให้ดู dmesg ว่าไม่มี error ของ I2C bus 9 เพิ่มขึ้น
- ทดสอบด้วยการจำลองแล้ว ได้แก่ ถอดแล้วเสียบกลับ, เสียบกลับเร็วกว่า 3 วินาที, เพิ่มกล้องที่ port 1, `rmmod` ไม่ผ่านแล้วลองใหม่ และ dry run ยังไม่ได้ทดสอบบนฮาร์ดแวร์จริง

## ถอนการติดตั้ง

```bash
sudo systemctl disable --now sensing-hotplug-watch.service
sudo rm /etc/systemd/system/sensing-hotplug-watch.service /usr/local/sbin/sensing-hotplug-watch
sudo systemctl daemon-reload
```
