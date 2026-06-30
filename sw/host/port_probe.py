import serial, time
from serial.tools import list_ports
ports = [p.device for p in list_ports.comports()]
print("PORTS:", ports, flush=True)
for p in ports:
    try:
        print("trying", p, "...", flush=True)
        s = serial.Serial(p, 115200, timeout=0.8, write_timeout=0.8)
        time.sleep(0.2)
        try: s.reset_input_buffer()
        except Exception: pass
        s.write(b'p\r\n'); time.sleep(0.3); r1 = s.read(200)
        s.write(b't\r\n'); time.sleep(0.3); r2 = s.read(200)
        s.close()
        print(p, " p->", repr(r1[:100]), " t->", repr(r2[:100]), flush=True)
    except Exception as e:
        print(p, "ERR", str(e)[:70], flush=True)
print("PROBE-DONE", flush=True)
