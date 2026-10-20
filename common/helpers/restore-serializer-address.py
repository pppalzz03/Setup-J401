#!/usr/bin/python3
"""Find the port-2 MAX96717F on camera bus 9 and move it back to its default
address before SENSING probe.

The sensor driver moves the serializer away from 0x40 when it probes. If the
camera keeps power while the Jetson reboots (or the driver is unloaded), the
serializer stays at the moved address and the next probe fails. Earlier
versions only knew 0x46; this version searches CANDIDATES for it.

Usage:
  restore-serializer-address.py            detect and recover (used by loader)
  restore-serializer-address.py --dry-run  detect and report only, no I2C write
"""
import subprocess
import sys
import time
from pathlib import Path

BUS = '9'
DES = 0x6b                    # MAX96712 deserializer
DES_ID = 0x20                 # MAX96712 ID at reg 0x4a
DEFAULT = 0x40                # MAX96717F default address
SER_ID = 0xc8                 # MAX96717F ID at reg 0x0d
CANDIDATES = range(0x41, 0x50)  # addresses searched when DEFAULT is silent
LOCK_REGS = (0x1a, 0x0a, 0x0b, 0x0c)  # link lock for port 0..3, bit 0x08
PORT = 2                      # port used by the overlay (cam_2@1c)
DEADLINE = 20                 # seconds; stay well inside the service timeout

DRY_RUN = '--dry-run' in sys.argv[1:]
START = time.monotonic()


def i2c(args):
    return subprocess.run(['i2ctransfer', '-f', '-y', BUS] + args,
                          capture_output=True, text=True, timeout=3)


def present(address):
    """Read-only presence check: one byte read, no register write."""
    try:
        return i2c(['r1@' + hex(address)]).returncode == 0
    except subprocess.TimeoutExpired:
        return False


def read(address, register):
    try:
        p = i2c(['w2@' + hex(address), hex(register >> 8), hex(register & 255), 'r1'])
    except subprocess.TimeoutExpired:
        return None
    return int(p.stdout.strip(), 16) if p.returncode == 0 else None


def is_serializer(address):
    return read(address, 0x0d) == SER_ID and read(address, 0x00) == address << 1


if Path('/sys/module/sgx_yuv_gmsl2').exists():
    raise SystemExit('Refusing address change while sensor driver is loaded')

if read(DES, 0x4a) != DES_ID:
    raise SystemExit('Expected MAX96712 not found on camera bus ' + BUS)

locks = [read(DES, r) for r in LOCK_REGS]
if any(v is None for v in locks):
    print('Cannot read GMSL link lock; retaining addresses')
    sys.exit(0)
locked = [i for i, v in enumerate(locks) if v & 8]
print('GMSL link locked ports: %s' % (locked or 'none'))

if locked != [PORT]:
    if PORT not in locked:
        print('No camera link on port %d; retaining addresses' % PORT)
    else:
        print('More than one camera link; retaining addresses')
elif read(DEFAULT, 0) is not None:
    print('Default serializer address responds; no change')
else:
    found = []
    for a in CANDIDATES:
        if time.monotonic() - START > DEADLINE:
            print('Serializer search stopped at %s (time limit); no change' % hex(a))
            sys.exit(0)
        if present(a) and is_serializer(a):
            found.append(a)
    if len(found) != 1:
        print('Serializer search found %d match(es) %s; no change'
              % (len(found), [hex(a) for a in found]))
    elif DRY_RUN:
        print('Dry run: would move MAX96717F %s -> %s' % (hex(found[0]), hex(DEFAULT)))
    else:
        old = found[0]
        i2c(['w3@' + hex(old), '0', '0', hex(DEFAULT << 1)]).check_returncode()
        if read(DEFAULT, 0) != DEFAULT << 1:
            raise SystemExit('Serializer address recovery readback failed')
        print('Recovered retained MAX96717F address %s -> %s before probe'
              % (hex(old), hex(DEFAULT)))
