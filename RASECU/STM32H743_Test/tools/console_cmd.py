#!/usr/bin/env python3
"""console_cmd.py - send console commands to the RASBB ECU over /dev/ttyUSB0 and print the replies.
   usage: console_cmd.py "NL" "CS" "RW 10 10"   (each argument is one command line)"""
import serial, sys, time
port = "/dev/ttyUSB0"
cmds = sys.argv[1:]
with serial.Serial(port, 115200, timeout=0.2) as s:
    s.reset_input_buffer()
    for c in cmds:
        s.write((c + "\r\n").encode()); time.sleep(0.15)
        t0 = time.time(); out = b""
        while time.time() - t0 < 1.5:
            d = s.read(4096)
            if d: out += d
        print(f">>> {c}"); print(out.decode(errors="replace").strip())
