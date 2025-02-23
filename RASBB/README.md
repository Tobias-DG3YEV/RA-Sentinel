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

![image](https://github.com/user-attachments/assets/2e514202-3a31-4a70-a0d0-1be484fe567c)

![image](https://github.com/user-attachments/assets/06899e89-e307-487e-bd01-28fa4f841cfd)

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

![image](https://github.com/user-attachments/assets/bf05c6e6-3777-4b70-b960-ee0d89003453)
*RASBB Rev A (Top View)*

![image](https://github.com/user-attachments/assets/59683930-f7f0-46f2-9ada-83859a658bdf)
*RASBB Rev AB (Bottom View)*


The PCB of the RASRF is constructed from an FR4 Four-layer PCB, which contains  processing unit, RF-transmitter, and an Analoge/to/Digital converter.
![image](https://github.com/user-attachments/assets/e5c04499-7f3d-45e9-aef9-7aadf43681d6)
*RASRF Rev AB (Top View)*

![image](https://github.com/user-attachments/assets/0edbecd5-e06b-4ff3-950f-bfffeb38e53c)
*RASRF Rev AB (Bottom View)*


*Hardware designed by **Mina Daneshpajouh**.*
