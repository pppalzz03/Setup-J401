# Hot-plug reconnect (branch `feature/hotplug-reconnect`)

> branch ทดลอง แตกมาจาก `feature/auto-detect-serializer` ห้าม merge เข้า `main` จนกว่าจะตัดสินใจเรื่องสคริปต์ address แบบ 4 port (ดู "สถานะการทดสอบ")

## สรุป

| คำถาม | คำตอบ |
|---|---|
| กล้อง GMSL2 ถอดเสียบสายแล้ว reconnect ได้ไหม | ได้ ด้วยการโหลด driver `sgx_yuv_gmsl2` ใหม่ ทดสอบบนเครื่องจริงผ่านแล้ว ทั้งถ่ายภาพนิ่งและภาพสด |
| reconnect อัตโนมัติได้ไหม | ได้ ใช้ `sensing-hotplug-watch` ทดสอบกับภาพสดผ่านแล้ว |
| reconnect เฉพาะ port ที่หลุดโดยไม่กระทบ port อื่นได้ไหม | ยังไม่ได้ Linux แยกทำราย port ได้ (unbind/bind) แต่ driver `sgx-yuv-gmsl2` v2.0.6 probe ทีละตัวไม่ผ่าน ต้องให้ SENSING แก้ driver (ดู "Reconnect ราย port") |

## ทำไมภาพค้างหลังถอดเสียบสาย

- **link GMSL2:** เมื่อเสียบสายกลับ MAX96712 กับ serializer จะ lock กันใหม่เอง ไม่ต้องสั่งอะไร
- **ตัวกล้อง:** ได้ไฟเลี้ยงผ่านสาย coax ถอดสายเท่ากับปิดกล้อง ค่าที่ driver ตั้งไว้ตอน probe จึงหายหมด (address ของ serializer, register ของ sensor, โหมดส่งภาพ)
- **driver:** `sgx-yuv-gmsl2` ไม่รู้ว่ากล้องถูกปิดเปิด ภาพจึงค้าง ต้องโหลด driver ใหม่ให้ตั้งค่ากล้องอีกรอบ
- **deserializer (MAX96712):** อยู่บนบอร์ด SG4A ไม่ดับตอนถอดสายกล้อง จึงไม่ต้องโหลด `max96712` ใหม่

## กล้องแต่ละ port

| port | I2C device | video | address ของ serializer หลัง probe |
|---|---|---|---|
| 0 | `9-001a` | `/dev/video0` | — (ยังไม่ได้ต่อกล้องทดสอบ) |
| 1 | `9-001b` | `/dev/video1` | `0x44` |
| 2 | `9-001c` | `/dev/video2` | `0x46` |
| 3 | `9-001d` | `/dev/video3` | — (ยังไม่ได้ต่อกล้องทดสอบ) |

ดูจากเครื่องด้วย:

```bash
for v in /dev/video*; do echo "$v: $(cat /sys/class/video4linux/$(basename $v)/name)"; done
```

overlay มีกล้องครบ 4 port (driver probe `9-001a`–`9-001d`) ส่วน loader ตรวจแค่ `cam_2@1c` ว่ามี overlay หรือไม่

ตอนกล้องเพิ่งเปิด serializer ทุกตัวตอบที่ `0x40` driver เปิด link ทีละ port (MAX96712 reg `0x0006`) แล้วย้าย serializer ไปที่ address ของ port นั้น ส่วนกล้องที่ไม่ได้ต่อจะขึ้น `detect error` ใน dmesg ซึ่งเป็นเรื่องปกติ

## Reconnect ด้วยมือ

ใช้ได้กับกล้องที่ port ไหนก็ได้ แต่ทุก port จะสะดุดพร้อมกัน

```bash
# ปิดโปรแกรมที่ใช้กล้องทุกตัวก่อน แล้ว
sudo rmmod sgx_yuv_gmsl2
sudo systemctl restart sensing-camera-load.service
lsmod | grep -e sgx -e max96712        # ต้องเห็นทั้งสองตัว และไม่มี -1
bash $HOME/Downloads/sensing-capture/capture.sh /dev/video2 1
```

> **ห้าม `rmmod max96712`** โมดูลจะค้างที่ refcount `-1` และไม่มี `/dev/video*` จนกว่าจะ reboot ทดสอบแล้วบนเครื่องจริง

## Reconnect อัตโนมัติ (`sensing-hotplug-watch`)

```text
ทุก 1 วินาที อ่าน lock ของ port 0–3 (MAX96712 reg 0x1a/0x0a/0x0b/0x0c บิต 0x08)
├─ port หาย        → log "cable lost" และหยุด APP_SERVICE
└─ port กลับมา lock นิ่ง 3 วินาที (หรือมี port ใหม่)
     → หยุด APP_SERVICE
     → rmmod sgx_yuv_gmsl2 (ไม่ถอด max96712)
     → systemctl restart sensing-camera-load.service
        (restore-serializer-address.py → insmod sgx-yuv-gmsl2 → ตั้ง 2-lane)
     → ตรวจว่ามี /dev/video2
     → เริ่ม APP_SERVICE
     ไม่สำเร็จ → ลองใหม่ทุก 15 วินาที สูงสุด 3 ครั้ง
```

ถอดแล้วเสียบกลับเร็วกว่า 3 วินาทีก็ยัง reconnect เพราะ watcher จำไว้ว่า port นั้นเคยหลุด

### ไฟล์

| ไฟล์ใน repo | ติดตั้งที่ |
|---|---|
| `common/hotplug/sensing-hotplug-watch` | `/usr/local/sbin/sensing-hotplug-watch` (755) |
| `common/systemd/sensing-hotplug-watch.service` | `/etc/systemd/system/sensing-hotplug-watch.service` (644) |
| `common/systemd/sensing-stream.service` (ตัวอย่าง APP_SERVICE) | `/etc/systemd/system/sensing-stream.service` (644) |
| `common/capture/stream.sh` | `/usr/local/lib/sensing-j401/stream.sh` (755) ใช้กับ `sensing-stream.service` |

### ติดตั้งและทดสอบ

**1. ติดตั้ง** (ยังไม่ enable service)

```bash
git -C $REPO fetch && git -C $REPO checkout feature/hotplug-reconnect
sudo install -m 755 $REPO/common/hotplug/sensing-hotplug-watch /usr/local/sbin/sensing-hotplug-watch
sudo install -m 644 $REPO/common/systemd/sensing-hotplug-watch.service /etc/systemd/system/
sudo systemctl daemon-reload
```

ไม่ต้องติดตั้ง `restore-serializer-address.py` จาก branch นี้ การทดสอบที่ผ่านใช้ตัวเดิมจาก `main`

**2. dry run** ดูว่าตรวจเจอการถอดเสียบสายถูกต้อง โดยยังไม่ทำอะไรจริง

```bash
sudo /usr/local/sbin/sensing-hotplug-watch --dry-run
```

ถอดสาย port 2 → รอ 5 วินาที → เสียบกลับ ผลบนเครื่องจริง (มีกล้องที่ port 1 และ 2):

```text
link change: locked ports [1, 2] -> [1]
  cable lost on port [2]
link change: locked ports [1] -> [1, 2]
cable back on port [2], stable 3s: reconnecting
  dry run: rmmod sgx_yuv_gmsl2
  dry run: systemctl restart sensing-camera-load.service
  ...
reconnect done
```

กด `Ctrl+C` เพื่อหยุด

**3. รันจริงใน terminal** ปิดโปรแกรมที่ใช้กล้องก่อน

```bash
sudo /usr/local/sbin/sensing-hotplug-watch
```

ถอดเสียบสาย รอ `reconnect done` แล้วเปิด terminal อีกหน้าต่าง:

```bash
bash $HOME/Downloads/sensing-capture/capture.sh /dev/video2 1
```

ต้องได้ `capture.nv16: 5,898,240 bytes` และภาพจริง ลองซ้ำหลายรอบ และลองเสียบกลับเร็วๆ

**4. ทดสอบกับภาพสด**

stream ต้องรันเป็น systemd service ให้ watcher หยุดและเริ่มได้ เพราะระหว่างที่ `stream.sh` เปิด `/dev/video2` อยู่ `rmmod sgx_yuv_gmsl2` จะไม่ผ่าน

login หน้า desktop บนจอ Jetson ไว้ก่อน ดู uid ด้วย `id -u` ถ้าไม่ใช่ `1000` ให้แก้ `SUDO_UID` และถ้า desktop ใช้ `:0` ให้แก้ `DISPLAY` ใน `sensing-stream.service`

```bash
sudo install -m 755 $REPO/common/capture/stream.sh /usr/local/lib/sensing-j401/stream.sh
sudo install -m 644 $REPO/common/systemd/sensing-stream.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start sensing-stream.service
sudo APP_SERVICE=sensing-stream.service /usr/local/sbin/sensing-hotplug-watch
```

ถอดสาย port 2 → หน้าต่างภาพปิด → เสียบกลับ → ภาพขึ้นใหม่ภายในประมาณ 5–10 วินาที:

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

**5. ใช้แบบถาวร** ตั้ง `Environment=APP_SERVICE=sensing-stream.service` ใน `/etc/systemd/system/sensing-hotplug-watch.service` แล้ว

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now sensing-stream.service sensing-hotplug-watch.service
journalctl -u sensing-hotplug-watch.service -f
```

### ตั้งค่า

แก้ใน `/etc/systemd/system/sensing-hotplug-watch.service` แล้ว `sudo systemctl daemon-reload && sudo systemctl restart sensing-hotplug-watch.service`

| ค่า | ค่าเริ่มต้น | ความหมาย |
|---|---|---|
| `APP_SERVICE` | ว่าง | service ที่ใช้กล้อง watcher จะหยุดตอนสายหลุดและเริ่มใหม่หลัง reconnect ถ้าโปรแกรมไม่ได้รันเป็น service ต้องปิดเองก่อน ไม่อย่างนั้น `rmmod` จะไม่ผ่าน (log บอก PID ที่ใช้ `/dev/video2` อยู่) |
| `POLL` | 1 | ตรวจทุกกี่วินาที |
| `STABLE` | 3 | lock ต้องนิ่งกี่วินาทีก่อน reconnect |
| `RETRY` / `MAX_RETRY` | 15 / 3 | เวลารอและจำนวนครั้งที่ลองใหม่เมื่อ reconnect ไม่สำเร็จ |
| `VIDEO` | `/dev/video2` | อุปกรณ์ที่ต้องมีหลัง reconnect |
| `UNLOAD_MODULES` | `sgx_yuv_gmsl2` | โมดูลที่ถอดก่อนโหลดใหม่ ห้ามใส่ `max96712` |

## Reconnect ราย port

ต้องการ: stream `/dev/video0` อยู่แล้วสาย port 0 หลุด ให้ reconnect เฉพาะ port 0 โดยภาพของ port อื่นไม่สะดุด

### ทำไม watcher ตัวปัจจุบันทำไม่ได้

- `rmmod sgx_yuv_gmsl2` ปิดกล้องทุก port เพราะ driver ตัวเดียวดูแลทั้ง 4 ตัว
- `configure-2lane.py` reset ทั้ง 4 link (`0x1c00`–`0x1f00`) และปิดเปิด MIPI output (`0x40b`) ภาพของทุก port จะสะดุด

### ผลทดสอบ unbind/bind ทีละ port

Linux สั่งให้ driver ปล่อยแล้ว probe ใหม่เฉพาะอุปกรณ์ตัวเดียวได้:

```bash
echo 9-001c | sudo tee /sys/bus/i2c/drivers/sgx-yuv-gmsl2/unbind
echo 9-001c | sudo tee /sys/bus/i2c/drivers/sgx-yuv-gmsl2/bind
```

| สิ่งที่ตรวจ | ผล |
|---|---|
| unbind | ผ่าน หายเฉพาะ `/dev/video2` ส่วน video0, 1, 3 ยังอยู่ |
| bind | ผ่าน probe ใหม่เฉพาะ `9-001c` และได้ `/dev/video2` คืน |
| ตรวจเจอกล้อง | ไม่ผ่าน `dser_link_check link:0x00` → `detect error` |
| ถ่ายภาพ | ไม่ผ่าน ได้ 0 byte |

สาเหตุจาก dmesg:

```text
โหลดทั้งชุด (ได้ภาพ):    max96712 9-006b: 0x00d6-w: 0x0006 = 0xF7 → link:0xc8 → detected
bind ทีละตัว (ไม่ได้ภาพ): max96712 9-006b: 0x00d6-w: 0x0006 = 0x03 → link:0x00 → detect error
```

ตอน probe ทีละตัว driver เขียน reg `0x0006` (ตัวเปิด link ของทั้ง 4 port) เป็น `0x03`:

- ปิด link ของ port 2 เอง จึงตรวจไม่เจอกล้อง
- ล้างบิตครึ่งบน (`0xF0`) ที่มีตอนโหลดปกติ ซึ่งดูเหมือนเกี่ยวกับโหมด GMSL2 (อนุมาน ยังไม่ได้เทียบ datasheet) อาจกระทบ port อื่นที่ stream อยู่

ค่านี้ driver คำนวณจากสถานะภายในของตัวเอง ซึ่งถูกเฉพาะตอน probe ครบ 4 ตัวตามลำดับ จึงแก้จากภายนอก driver ไม่ได้

### ถ้าทดสอบ unbind/bind แล้วกล้องใช้ไม่ได้

```bash
sudo i2ctransfer -f -y 9 w2@0x6b 0x00 0x06 r1     # ได้ 0x03 = ค่าค้างจาก bind
sudo rmmod sgx_yuv_gmsl2
sudo systemctl restart sensing-camera-load.service
sudo i2ctransfer -f -y 9 w2@0x6b 0x00 0x06 r1     # ควรกลับเป็น 0xff หรือ 0xf7
```

ยังไม่ได้ภาพ ให้ reboot (ห้าม `rmmod max96712`)

### ทางเลือก

| ทาง | สถานะ |
|---|---|
| ให้ SENSING แก้ driver ให้ probe ทีละ port โดยคงค่า `0x0006` ของ port อื่น หรือขอ source ของ driver มาแก้แล้ว build ใหม่ | แนะนำ รอข้อมูลจาก SENSING |
| เขียน `0x0006` แก้ทับระหว่าง probe (ต้องทันในช่วงประมาณ 200 ms ก่อน driver ตรวจ link) | ไม่แนะนำ เป็นการแข่งเวลา ไม่เสถียร |
| ใช้ watcher ตัวปัจจุบัน (โหลด driver ทั้งชุด) | ใช้ได้แล้ว ทุก port สะดุดพร้อมกันตอน reconnect |

ถ้าได้ driver ที่ probe ทีละ port ได้แล้ว watcher ราย port จะทำงานแบบนี้: port หลุด → หยุด `sensing-stream@videoN` เฉพาะตัวนั้น → unbind/bind `9-001X` → ตั้งค่า 2-lane เฉพาะ port นั้น (ไม่ใช้ `configure-2lane.py` ที่ reset ทุก link) → เริ่ม `sensing-stream@videoN` ใหม่

### ข้อมูลสำหรับแจ้ง SENSING

- driver `sgx-yuv-gmsl2` v2.0.6, JetPack 6.1 (R36.4.0), Jetson Orin NX บน Seeed J401, SG4A-NONX-G2Y-A1, CSI 2-lane
- ต้องการ reconnect ราย port หลังถอดเสียบสาย โดยไม่กระทบ port อื่นที่ stream อยู่
- unbind/bind `9-001c` ทีละตัวแล้ว probe เขียน MAX96712 reg `0x0006 = 0x03` (ตอนโหลดทั้งชุดเขียน `0xF7`) ทำให้ link ของ port 2 ถูกปิด และขึ้น `dser_link_check link:0x00` / `sensor_probe ... detect error`
- `rmmod max96712` ค้างที่ refcount `-1` ต้อง reboot
- ขอ driver ที่ probe หรือ reinit ทีละ port ได้ หรือขอ source ของ driver

## จำนวนกล้องที่ stream พร้อมกัน

กล้องหนึ่งตัวที่ 1920×1536 NV16 30 fps ใช้ประมาณ 1.42 Gbps สองตัวประมาณ 2.8 Gbps ใกล้เพดานของ CSI 2 lane ที่ตั้งค่าไว้ ต่อได้ 4 port แต่ stream พร้อมกันได้ราว 2 ตัว (คำนวณ ยังไม่ได้วัดจริง)

## สถานะการทดสอบ

| เรื่อง | ผล |
|---|---|
| reconnect ด้วยมือ (`rmmod sgx_yuv_gmsl2` + restart loader) | ผ่าน บนเครื่องจริง ได้ 5,898,240 bytes |
| `rmmod max96712` | ไม่ผ่าน ค้างที่ refcount `-1` จนกว่าจะ reboot |
| watcher `--dry-run` | ผ่าน บนเครื่องจริง ตรวจเจอการถอดเสียบ port 2 ขณะที่ port 1 lock อยู่ |
| watcher + ภาพสด (`sensing-stream.service`) | ผ่าน บนเครื่องจริง |
| reconnect ราย port (unbind/bind) | ไม่ผ่าน driver probe ทีละตัวไม่ได้ |
| `restore-serializer-address.py` แบบ 4 port | ทดสอบด้วยการจำลองเท่านั้น การทดสอบบนเครื่องจริงใช้ตัวเดิม |

## ข้อจำกัด

- reconnect คือโหลด driver กล้องทั้งชุดใหม่ เสียบสายใหม่ตัวเดียว ภาพของทุกกล้องจะสะดุดพร้อมกัน
- watcher ตรวจแค่ `VIDEO` ตัวเดียว (ค่าเริ่มต้น `/dev/video2`) และ `APP_SERVICE` ได้ตัวเดียว
- watcher อ่าน register ของ MAX96712 ทุก 1 วินาทีขณะ driver โหลดอยู่ (อ่านอย่างเดียว) ให้ดู dmesg ว่าไม่มี error ของ I2C bus 9 เพิ่มขึ้น

## ถอนการติดตั้ง

```bash
sudo systemctl disable --now sensing-hotplug-watch.service sensing-stream.service
sudo rm /etc/systemd/system/sensing-hotplug-watch.service /etc/systemd/system/sensing-stream.service /usr/local/sbin/sensing-hotplug-watch
sudo systemctl daemon-reload
```
