import subprocess
def read(reg):
    p=subprocess.run(['i2ctransfer','-f','-y','9','w2@0x6b',hex(reg>>8),hex(reg&255),'r1'],capture_output=True,text=True,check=True)
    return int(p.stdout.strip(),16)
def write(reg,v):
    subprocess.run(['i2ctransfer','-f','-y','9','w3@0x6b',hex(reg>>8),hex(reg&255),hex(v)],capture_output=True,check=True)
cfg={0x8a0:0x81,0x8a3:0x44,0x8a4:0x44,0x90a:0x40,0x94a:0x40,0x98a:0x40,0x9ca:0x40,
0x415:0x2f,0x418:0x2f,0x41b:0x2f,0x41e:0x2f,0x933:0x10,0x973:0x10,0x9b3:0x10,0x9f3:0x10,0x8a2:0xf0}
resets=[0x1c00,0x1d00,0x1e00,0x1f00]

if read(0x4a)!=0x20:raise SystemExit('Unexpected deserializer ID')
write(0x40b,read(0x40b)&~2)
for r in resets:write(r,0xf4)
for r,v in cfg.items():write(r,v)
for r in resets:write(r,0xf5)
write(0x40b,read(0x40b)|2)
for r,v in cfg.items():
    if read(r)!=v:raise SystemExit('Register readback mismatch '+hex(r))
print('MAX96712: 2 lanes, MIPI output enabled')
