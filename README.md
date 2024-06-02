# Project RA-Sentinel - a Radio Access Sentinel
FPGA-based Radio Receiver for securing Wifi an other access points against hacking attacks.

RA-Sentinel is an open-source project focused on creating a cost-effective, small, and low-power wide band radio receiver device that employs an FPGA to automatically detect malicious attacks on Wifi access points, such as Man in the Middle and Denial of Service attacks. By monitoring any Wifi cell, the device enhances internet safety for everyday users.
The device features low-cost receive-only chips that digitize 40 MHz of the Wifi radio spectrum at 2.4 GHz. An FPGA extracts relevant properties from demodulated and decoded packets in real-time without storage. These properties are then processed by a neural network, also implemented on the FPGA, to determine if the traffic is genuine or an attack.

## The hardware

The hardware is a wide band SDR receiver that receives at least one complete WiFi Channel on the 2.4GHz ISM band with high resolution (12 Bits) to be able to detect smallest anomalies in a transmitted signal. The initial evaluation hardware consists on an 12 Bit ADC (TI ADC3222) which is able to convert a 40MHz part of the 2.4GHZ radio spectrum into a 4 x 240 Bit/s LVDS streams into a XILNIX/AMD Artix7 FPGA evaluation board.

**/RFFE2400_PCB** in this folder of this repository you find the PCB design files in KiCAD format and gerbers for the 2.4GHz PMOD frontend evaluation/test board.

Link to the FPGA dev. board
[https://de.aliexpress.com/item/1005006473783593.html]


## The software

The vast majority of the code will be written in Verilog and run on the FPGA. There will also be some helper microcontrollers which helps controlling the frontend hardware and maybe the interconnctivity with other systems (alarm forwarding). This firmware is written in C. 

**/RASM2400_Verilog**

RASM2400 stands for Radio Access Spectrum Monitor. It offers a visual spectrum analyzer design that runs on the evaluation hardware set of RA-Sentinel the Artix7 XC7A100T Wukong board and the RFFE2400 front end board.
The folder contains the Verilog source files as well as a ready to program bit stream file. 

The following diagram shows the system architecture of the RASM2400.

![Alt text](/RASM2400_Blockdiagram.png "RASM2400 Block Diagram")

The output of the HDMI port of the QMTECH Wukong board.

![Alt text](/RASM2400_screenshot.png "Screenshot of the RASM2400 HDMI output")

## System architecture

![Alt text](/RAsentinel-Blockdiagram.JPG "RA-Sentinel Block Diagram")

Project Maintainer: Tobias Weber

Last updated: 1.6.2024

