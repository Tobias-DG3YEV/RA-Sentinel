
*** Project RASentinel ***

This project is meant to offer an open source
sentinel hardware based system that ia capable of
detecting suspicious activities in the radio spectrum.
THis data is fed into a machnine learning processor
that ahsll run on a FPGA. As a result, the device should
alarm wjen possible wireless hacker attacks occur.

The hardware:

The hardware is a wide band SDR receiver that
receives at least one komplete WiFi Channel
with high resolution (12 Bits) to be able to
detect smallest anomalies in a transmitted 
signal. The initial evaluation hardware consists
on an 12 Bit ADC which is able to convert a 40MHz
part of the 2.4GHZ radip spectrum that feeds this 
960MBit/s (2 channels I+Q * 12 bits @ 40MS) via
LVDS into a XLINIX Artix7 FPGA evaluation board.

The software:

The cast majority of the code will be written in Verilog
anbd run on the FPGA. There will also be some helper
microcontrollers which help controlling the frontend-hardware
and maybe the intercennctivity with other systems (alarm forwarding)

Project Maintainer:
Tobias Weber

Latest update of this file:
11.3.2024
