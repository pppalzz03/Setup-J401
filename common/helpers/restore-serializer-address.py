#!/usr/bin/python3
"""Check all 4 GMSL ports of the MAX96712 and report / recover the I2C
address of the MAX96717F serializer on each port before SENSING probe.

The sensor driver moves serializers away from the default 0x40 when it probes.
If cameras keep power while the Jetson reboots (or the driver is unloaded),
they stay at the moved address and the next probe fails. With several cameras
every serializer answers on the same bus, so each port is checked alone by
enabling only that GMSL link, then the original link setting is restored.

Usage:
  restore-serializer-address.py            check every port, move serializers back to 0x40
  restore-serializer-address.py --dry-run  check every port and report only (links are still
                                           switched one at a time, addresses are not changed)
"""
import subprocess
import sys
import time
from pathlib import Path

BUS = '9'
DES = 0x6b                     # MAX96712 deserializer
DES_ID = 0x20                  # MAX96712 ID at reg 0x4a
LINK_EN = 0x0006               # MAX96712 link enable, bit 0..3 = port 0..3 (checked at runtime)
LOCK_REGS = (0x1a, 0x0a, 0x0b, 0x0c)  # link lock for port 0..3, bit 0x08
DEFAULT = 0x40                 # MAX96717F default address
SER_ID = 0xc8                  # MAX96717F ID at reg 0x0d
CANDIDATES = range(0x41, 0x50)   # addresses searched when DEFAULT is silent
LOCK_WAIT = 2.0                # seconds to wait for a link to lock
DEADLINE = 45                  # seconds; stay inside the 60 s service timeout

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


def write(address, register, value):
    i2c(['w3@' + hex(address), hex(register >> 8), hex(register & 255),
         hex(value)]).check_returncode()


def locked_ports():
    values = [read(DES, r) for r in LOCK_REGS]
    if any(v is None for v in values):
        return None
    return [p for p, v in enumerate(values) if v & 8]


def wait_locked(expected):
    end = time.monotonic() + LOCK_WAIT
    while True:
        now = locked_ports()
        if now == expected or time.monotonic() > end:
            return now
        time.sleep(0.05)


def is_serializer(address):
    return read(address, 0x0d) == SER_ID and read(address, 0x00) == address << 1


def find_serializer():
    """Address of the one serializer visible now, 'none', or 'many: [...]'."""
    if is_serializer(DEFAULT):
        return DEFAULT
    found = [a for a in CANDIDATES if present(a) and is_serializer(a)]
    if len(found) == 1:
        return found[0]
    return 'none' if not found else 'many: %s' % [hex(a) for a in found]


if Path('/sys/module/sgx_yuv_gmsl2').exists():
    raise SystemExit('Refusing address change while sensor driver is loaded')

if read(DES, 0x4a) != DES_ID:
    raise SystemExit('Expected MAX96712 not found on camera bus ' + BUS)

original = read(DES, LINK_EN)
locked = locked_ports()
if original is None or locked is None:
    print('Cannot read MAX96712 link status; retaining addresses')
    sys.exit(0)
print('GMSL link enable 0x%02x, locked ports: %s' % (original, locked or 'none'))
if not locked:
    print('No camera link locked; retaining addresses')
    sys.exit(0)

results = {}
try:
    for port in locked:
        if time.monotonic() - START > DEADLINE:
            results[port] = 'skipped (time limit)'
            continue
        write(DES, LINK_EN, (original & ~0x0f) | (1 << port))
        now = wait_locked([port])
        if now != [port]:
            results[port] = 'isolation failed (locked ports %s)' % now
            break           # register layout not as expected; touch nothing else
        found = find_serializer()
        if not isinstance(found, int):
            results[port] = 'serializer %s; no change' % found
        elif found == DEFAULT:
            results[port] = 'serializer at 0x40; no change'
        elif DRY_RUN:
            results[port] = 'serializer at %s; dry run, would move to 0x40' % hex(found)
        else:
            write(found, 0x00, DEFAULT << 1)
            if read(DEFAULT, 0x00) != DEFAULT << 1:
                results[port] = 'serializer %s -> 0x40 readback FAILED' % hex(found)
            else:
                results[port] = 'recovered serializer %s -> 0x40' % hex(found)
finally:
    write(DES, LINK_EN, original)
    relocked = wait_locked(locked)

for port in range(4):
    if port in results:
        print('port %d: %s' % (port, results[port]))
    else:
        print('port %d: %s' % (port, 'not checked' if port in locked else 'no link'))
if relocked != locked:
    print('WARN: after restoring link enable, locked ports are %s (was %s)' % (relocked, locked))
if any('FAILED' in r for r in results.values()):
    raise SystemExit('Serializer address recovery readback failed')
