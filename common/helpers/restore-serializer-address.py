#!/usr/bin/python3
"""Recover a retained port-2 MAX96717F address before SENSING probe."""
import subprocess
from pathlib import Path
if Path('/sys/module/sgx_yuv_gmsl2').exists():
    raise SystemExit('Refusing address change while sensor driver is loaded')
def read(address, register):
    p = subprocess.run(['i2ctransfer', '-f', '-y', '9', 'w2@'+hex(address),
                        hex(register >> 8), hex(register & 255), 'r1'],
                       capture_output=True, text=True, timeout=3)
    return int(p.stdout.strip(), 16) if p.returncode == 0 else None
if read(0x6b, 0x4a) != 0x20:
    raise SystemExit('Expected MAX96712 not found on camera bus 9')
locks = [read(0x6b, r) for r in (0x1a, 0x0a, 0x0b, 0x0c)]
if any(v is None for v in locks) or [bool(v & 8) for v in locks] != [False, False, True, False]:
    print('Single port-2 recovery not applicable; retaining addresses')
elif read(0x40, 0) is not None:
    print('Default serializer address responds; no change')
elif read(0x46, 0x0d) == 0xc8 and read(0x46, 0) == 0x8c:
    subprocess.run(['i2ctransfer', '-f', '-y', '9', 'w3@0x46',
                    '0', '0', '0x80'], check=True, timeout=3)
    if read(0x40, 0) != 0x80:
        raise SystemExit('Serializer address recovery readback failed')
    print('Recovered retained MAX96717F address 0x46 -> 0x40 before probe')
else:
    print('No recognized retained serializer address; no change')