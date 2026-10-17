import gi,time,json,subprocess,signal,os
from pathlib import Path
gi.require_version('Gst','1.0')
from gi.repository import Gst,GLib
Gst.init(None)
import pwd
user=pwd.getpwnam(os.environ.get('SUDO_USER') or pwd.getpwuid(os.getuid()).pw_name)
out=Path(user.pw_dir)/'Downloads'/'sensing-record-60s'
out.mkdir(parents=True,exist_ok=True)
(out/'capture.pid').write_text(str(os.getpid()))
subprocess.run(['python3','/usr/local/lib/sensing-j401/configure-2lane.py'],check=True)
subprocess.run(['v4l2-ctl','-d','/dev/video2','--set-ctrl=sensor_mode=1,bypass_mode=0','--set-fmt-video=width=1920,height=1536,pixelformat=NV16'],check=True)
pipeline=Gst.parse_launch('v4l2src device=/dev/video2 io-mode=mmap name=camera ! video/x-raw,format=NV16,width=1920,height=1536,framerate=30/1 ! queue ! videoconvert ! jpegenc quality=95 name=encoder ! matroskamux ! filesink location='+str(out/'capture.mkv'))
loop=GLib.MainLoop()
stats={'frames':0,'encoded_frames':0,'errors':[],'warnings':[],'first_pts':None,'last_pts':None,'max_frame_gap_ms':0}
start=[None]; lastjpg=[None]; stopped=[False]
def stop():
 if not stopped[0]:
  stopped[0]=True
  pipeline.send_event(Gst.Event.new_eos())
 return False
def probe(pad,info):
 b=info.get_buffer()
 if b:
  if start[0] is None:
   start[0]=time.monotonic()
   GLib.timeout_add(60000,stop)
   stats['first_pts']=b.pts
  if stats['last_pts'] is not None:
   stats['max_frame_gap_ms']=max(stats['max_frame_gap_ms'],(b.pts-stats['last_pts'])/1e6)
  stats['last_pts']=b.pts
  stats['frames']+=1
 return Gst.PadProbeReturn.OK
def jpeg(pad,info):
 b=info.get_buffer()
 if b:
  data=b.extract_dup(0,b.get_size());lastjpg[0]=data
  stats['encoded_frames']+=1
  if stats['encoded_frames']==1:(out/'first.jpg').write_bytes(data)
  if start[0] is not None and time.monotonic()-start[0]>=30 and not (out/'middle.jpg').exists():(out/'middle.jpg').write_bytes(data)
 return Gst.PadProbeReturn.OK
pipeline.get_by_name('camera').get_static_pad('src').add_probe(Gst.PadProbeType.BUFFER,probe)
pipeline.get_by_name('encoder').get_static_pad('src').add_probe(Gst.PadProbeType.BUFFER,jpeg)
def message(bus,msg):
 if msg.type==Gst.MessageType.ERROR:
  e,d=msg.parse_error();stats['errors'].append(str(e)+' '+str(d));loop.quit()
 elif msg.type==Gst.MessageType.WARNING:
  e,d=msg.parse_warning();stats['warnings'].append(str(e)+' '+str(d))
 elif msg.type==Gst.MessageType.EOS:loop.quit()
bus=pipeline.get_bus();bus.add_signal_watch();bus.connect('message',message)
GLib.timeout_add_seconds(85,lambda:(stats['errors'].append('Watchdog timeout'),loop.quit(),False)[-1])
signal.signal(signal.SIGTERM,lambda *_:GLib.idle_add(stop))
signal.signal(signal.SIGINT,lambda *_:GLib.idle_add(stop))
print('OUTPUT '+str(out),flush=True)
try:
 pipeline.set_state(Gst.State.PLAYING);loop.run()
finally:
 pipeline.set_state(Gst.State.NULL)
 if lastjpg[0]:(out/'last.jpg').write_bytes(lastjpg[0])
 if start[0] is not None:stats['wall_seconds']=time.monotonic()-start[0]
 if stats['frames']>1:
  stats['frame_span_seconds']=(stats['last_pts']-stats['first_pts'])/1e9
  stats['average_fps']=(stats['frames']-1)/stats['frame_span_seconds']
 stats['video_bytes']=(out/'capture.mkv').stat().st_size if (out/'capture.mkv').exists() else 0
 (out/'report.json').write_text(json.dumps(stats,indent=2))
 (out/'capture.pid').unlink(missing_ok=True)
 os.chown(out,user.pw_uid,user.pw_gid)
 for f in out.iterdir():os.chown(f,user.pw_uid,user.pw_gid)
 print(json.dumps(stats,indent=2),flush=True)

