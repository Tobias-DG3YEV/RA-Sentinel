# RA-Sentinel System Overview

The **RA-Sentinel** system consists of two main boards that work together to enable high-performance RF signal reception, digitization, and processing.

## RA-Sentinel Radio Front-End Board (RASRF)
The **RASRF** board is responsible for receiving and conditioning, and digitizing RF signals before transmitting them to the baseband processor.
 - The antenna is connected through a Balun to an RF front-end transceiver, which performs signal reception, downconversion, and filtering.
 - The downconverted signal is then conditioned using a driver circuit optimized for impedance matching and signal integrity.
 - A high-speed 12-bit ADC samples a 40 MHz portion of the 2.4 GHz radio spectrum, converting it into a 960 Mbit/s data stream (2 channels: I+Q, 12-bit each @ 40 
   MSPS). 
 - The digitized data is transmitted over a PCIe interface to the RASBB board for baseband processing.

## RA-Sentinel Baseband Board (RASBB)
The **RASBB** board processes the received digital RF data and manages higher-layer communication.
 - It performs baseband signal processing, extracting relevant information from the digitized RF data.
 - It transitions the processed data from OSI Layer 1 (Physical) to OSI Layer 2 (Data Link) for further communication and protocol handling.
 - The board integrates additional processing units and interfaces for system-level control, data management, and external communication.

Together, the **RASRF** and **RASBB** boards create a scalable, high-performance platform for RF signal acquisition and real-time processing.

Below is the block diagram illustrating the architecture of both boards and their interconnections:

<p align="center">
  <img src="https://github.com/MinDans/RA-Sentinel/blob/main/RASBB/RASBB-BlockDiagram.png?raw=true" alt="RASBB block diagram">
  <br>
  <em>RASBB block diagram</em>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/MinDans/RA-Sentinel/main/RASBB/RASRF-BlockDiagram.png" alt="RASRF block diagram">
  <br>
  <em>RASRF block diagram</em>
</p>

## The hardware

The PCB of the RASBB is constructed from an FR4 eight-layer PCB, which contains several processing units, sensors, and radio and wired interfaces.
Below is a list of its features:

- Two Artix-7 FPGAs with 100k Logic Elements each
- 4 Gigabit (512MB with 16-bit access) Low Voltage DDR3 RAM
- STM32H7 high-performance (up to 480MHz) ARM Cortex-M7 microcontroller
- x8 PCI Express slot
- HDMI port, with video generated in FPGA 1
- 40-bit (32+8) inter-processor communication bridge (accessible by external logic analyzers)
- Two separately usable 16M Flash chips for FPGA configuration, accessible by both FPGA and STM32
- Temperature and humidity sensor for physical environment supervision
- Audio DAC with a 1W output amplifier (for alarm and voice output)
- Audio ADC for capacitive microphone connection (for acoustic environment surveillance)
- Open-collector 30V/1A capable switching output (for alarming devices)
- USB-C port with virtual COM port support for debugging and updates
- 2.4GHz LoRaWAN™ modem chip for robust alarm distribution
- 100Mbit/s Ethernet port connected to the STM32H7 MCU
- 1Gbit/s Ethernet port connected to FPGA 2
- Power over Ethernet (PoE) Type 1 with a maximum power of 13W
- LEDs for indication
- Configuration button
- FPGAs and STM32 accessible through JTAG port

*The RA-Sentinel Baseband Board design will fit into a 100mm extrusion enclosure.* 

<p align="center">
  <img src="https://raw.githubusercontent.com/MinDans/RA-Sentinel/main/RASBB/RASBB_RevA_top.jpg" alt="RASBB Rev A — top view" width="420">
  &nbsp;&nbsp;
  <img src="https://raw.githubusercontent.com/MinDans/RA-Sentinel/main/RASBB/RASBB_RevA_back.JPG" alt="RASBB Rev A — bottom view" width="420">
  <br>
  <em>RASBB Rev A - top &nbsp;&nbsp;|&nbsp;&nbsp; bottom</em>
</p>


The PCB of the RASRF is constructed from an FR4 Four-layer PCB, which contains  processing unit, RF-transmitter, and an Analoge/to/Digital converter.

<p align="center">
  <img src="https://raw.githubusercontent.com/MinDans/RA-Sentinel/main/RASRF2400WB/Hardware/Images/RASRF2400WB_RevA_Front.JPG" alt="RASRF2400WB Rev A — top view" width="420">
  &nbsp;&nbsp;
  <img src="https://raw.githubusercontent.com/MinDans/RA-Sentinel/main/RASRF2400WB/Hardware/Images/RASRF2400WB_RevA_Bottom.JPG" alt="RASRF2400WB Rev A — bottom view" width="420">
  <br>
  <em>RASBB Rev A - top &nbsp;&nbsp;|&nbsp;&nbsp; bottom</em>
</p>


---

*Hardware design: Mina Daneshpajouh*
*Firmware / signal processing: Tobias Weber*
