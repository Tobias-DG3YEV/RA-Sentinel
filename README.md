# RA-Sentinel
FPGA-based Radio Receiver for securing Wifi against hacking attacks

RAsentinel is an open-source project focused on creating a cost-effective, small, and low-power wide band radio receiver device that employs an FPGA to automatically detect malicious attacks on Wifi access points, such as Man in the Middle and Denial of Service attacks. By monitoring any Wifi cell, the device enhances internet safety for everyday users.
The device features low-cost receive-only chips that digitize 40 MHz of the Wifi radio spectrum at 2.4 GHz. An FPGA extracts relevant properties from demodulated and decoded packets in real-time without storage. These properties are then processed by a neural network, also implemented on the FPGA, to determine if the traffic is genuine or an attack.

# The hardware:

The hardware is a wide band SDR receiver that receives at least one komplete WiFi Channel with high resolution (12 Bits) to be able to detect smallest anomalies in a transmitted signal. The initial evaluation hardware consists on an 12 Bit ADC which is able to convert a 40MHz part of the 2.4GHZ radip spectrum that feeds this 960MBit/s (2 channels I+Q * 12 bits @ 40MS) via LVDS into a XLINIX Artix7 FPGA evaluation board.

# The software:

The cast majority of the code will be written in Verilog anbd run on the FPGA. There will also be some helper microcontrollers which help controlling the frontend-hardware and maybe the intercennctivity with other systems (alarm forwarding)

Project Maintainer: Tobias Weber

Last update of this file: 11.3.2024


![Alt text](/RAsentinel-Blockdiagram.JPG "Optional title")
