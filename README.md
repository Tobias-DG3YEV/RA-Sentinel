# Project RA-Sentinel - a Radio Access Sentinel
FPGA-based Radio Receiver for securing Wifi an other access points against hacking attacks.

RA-Sentinel is an open-source project focused on creating a cost-effective, small, and low-power wide band radio receiver device that employs an FPGA to automatically detect malicious attacks on Wifi access points, such as Man in the Middle and Denial of Service attacks. By monitoring any Wifi cell, the device enhances internet safety for everyday users.
The device features low-cost receive-only chips that digitize 40 MHz of the Wifi radio spectrum at 2.4 GHz. An FPGA extracts relevant properties from demodulated and decoded packets in real-time without storage. These properties are then processed by a neural network, also implemented on the FPGA, to determine if the traffic is genuine or an attack.

## System architecture

![Alt text](/RAsentinel-Blockdiagram.JPG "RA-Sentinel Block Diagram")

## The hardware

The hardware is a wide band SDR receiver that receives at least one complete WiFi Channel on the 2.4GHz ISM band with high resolution (12 Bits) to be able to detect smallest anomalies in a transmitted signal. The initial evaluation hardware consists of a Downcoverter/Tranceiver Chip for 2.4GHz which is widelay used in older WIFi Acess Points (MAX2831). This is followed by a 12 Bit ADC (Texas Instruments ADC3222) which converts a 40MHz window of the 2.4GHZ radio spectrum into a 4 x 240 Bit/s LVDS streams (960kBit/s total) into a XILNIX/AMD Artix7 FPGA sitting on a evaluation board made by QMTECH. 

![Alt text](https://raw.githubusercontent.com/Tobias-DG3YEV/RA-Sentinel/main/RFFE2400_QMTech.png
 "First RA-Sentinel prototype with QM-tech board")
<sub>Picture 1: First RA-Sentinel prototype based on the QM-Tech Artix7 board and a new designed RF front end connected via PMOD connector.</sub>

Based on the experience collected with with first prototype, we designed a new SDR prototypr. Two boards of the RASBB and the RASRF2400 have arrived on 23th. Feb. 2025
Testing and bringing up is now ongoing. First results and findings can be found in the corresponding Findings_Rev*.md documents.

![Alt text](https://raw.githubusercontent.com/Tobias-DG3YEV/RA-Sentinel/main/RASBB_RASRF2400WB.JPG "First RA-Sentinel prototype Revision A")
<sub>Picture 2: RA-Sentinel prototype Revision A with RF front end board RASRF2400WB.</sub>

### Design files

**/RFFE2400_PCB** in this folder of this repository you find the PCB design files in KiCAD format and gerbers for the 2.4GHz 2x PMOD connected RF frontend evaluation/test board.

Link to the FPGA dev. board
[https://de.aliexpress.com/item/1005006473783593.html]

## The software

The vast majority of the code will be written in Verilog and run on the FPGA. There is als a first supporting, or as I call it "house keeping unit" microcontroller (STM32C031) which programms and controlling the frontend chips. The may be another additional  and maybe the interconnctivity with other systems (alarm forwarding). This firmware is written in C. 

### Sub Projects / Project steps

The first step on this project was to have a reliable hardware basis. Initially I planned to have at least 40 Megasamples and with this 20 MHz bandwidth which is sufficient to capture the headers and the most common bandwitdhs used on 2.4GHz WiFi (802.11a,b,g) communications channel. But because 802.11n also defines the possibility to use 40MHz bandwith, I wanted the possibility to cover the complete possible channel bandwidth. This has been achieved with the first prototype hardware and prooved with the sub-project RASM2400, Radio Access Spectrum Monitor for 2400MHz. You can find all project details below.

## Sub project #1: RASM2400 - a spectrum monitor

RASM2400 stands for Radio Access Spectrum Monitor operationg on 2400MHZ. It offers a visual spectrum analyzer design that runs on the evaluation hardware set of RA-Sentinel the Artix7 XC7A100T Wukong board and the RFFE2400 front end board.
It shall proove that a 40MHz wide radio spectrum can be received and transported into the FPGA. Further, this project may already be useable for first RF forensics. Feel free to download all the stuff and build an RASM by yourself.

The following diagram shows the system architecture of the RASM2400.

![Alt text](https://raw.githubusercontent.com/Tobias-DG3YEV/RA-Sentinel/main//RASM2400_Blockdiagram.png "RASM2400 Block Diagram")

The output of the HDMI port of the QMTECH Wukong board.

![Alt text](https://raw.githubusercontent.com/Tobias-DG3YEV/RA-Sentinel/main//RASM2400_screenshot.png "Screenshot of the RASM2400 HDMI output")

Watch a short demonstration on Youtube by clicking on the thumbnail below.

[![Watch the video](https://img.youtube.com/vi/tnwXk62DtHw/0.jpg)](https://youtu.be/tnwXk62DtHw)

### Software

In this repository you'll find also all software paerts needed to get the project up and running.

**/RASM2400_Verilog**

This folder contains the Verilog source files as well as a ready to program bit stream file. 

**/RASM2400_HKU**

Here you find the firmware for the RF board housekeeping unit. It does not do much a the moment but initializing the Downconverter MAX2831 and the ADC3222. It is planned to receive commands via I2C to change basic parameters wil center frequency, sensitivity and AGC characteristics. This porject can be compiled with arm-gcc or with the free available and Eclipse based development environment (IDE) from ST called "STM32CubeIDE". You can download this IDE from ST.com [https://www.st.com/en/development-tools/stm32cubeide.html]

### Project update 13th Oct. 2024

The target of the next Milestone #2 was the „Identification and isolation of appropriate software components“ and also to „Additionally apply modifications to the openOFDM module to get extra meta data out of the frame demodulator to have a wider data basis for the later fingerprinting process.“

In the following points I describe how I achieved each step of this Milestone.

**1. compile/synthesize openWiFi on the target FPGA**

The code of openWiFi has been successfully ported from the project GitHub site [1] to the evaluation setup that I have designed and set up in the first Milestone. After gluing together the ADC LVDS deserializer block inside the FPGA with the parallel input of the openOFDM core, got rid of several timing constraint issues, I finally achieved to decode a WiFi Frame coming from an arbitrary signal generator. To accomplish this target, the code needed to be isolated from the original open WiFi demo project code. This original demo was based on SDR evaluation boards relying all on the AMD ZYNQ FPGA-ARM chip family. This family provides an FPGA part and an integrated ARM micro processor to which all communication of the FPGA part is connected to. Data from and to the integrated processor is exchanged through a common memory bus. This however is not working with my design idea which is based on a more powerful FPGA with an external ARM co-processor. I tried extracting the needed HDL (Verilog) parts and make this code running stand-alone. Finally I came the conclusion that only the project „openOFDM“ needs to be ported to my RA-Sentinel project hardware because the network layer and the transmit part implemented in openWiFi is not really needed by the RA-Sentinel project because there is no need in routing real data back and forth to a network. We are only interested in the lowest layer of a WiFi frame and its analog characteristics, not the routing of packets and also not in the frame containing payload as such.

First I adapted the test-bench provided in [2] for the Vivado simulation environment. To be able to simulate the complete RA-Sentinel hardware, I created a LVDS emulator that can stream artificial synthesized and recorded  RF data coming originally from the TI ADC 3221. After providing recorded RF data via this LVDS simulator and generating a appropriate, to the ADC phase-locked master clock of 100MHz to the openOFDM core and (see top_tb.v), this setup was able to decode a complete 802.11a/g frame in the AMD Vivado simulator. It took me quite some fiddling and playing with timings and implementation settings of the tool-chain to finally get it running properly on my own hardware. (AMD Artix7 development board my QM-Tech and my 2.4GHz ADC board designed in Milestone 1)


**2. Strip down openWiFi and open OFDM to the receive part**

First this was regarded as an easy task but as deeper I dived into the code  by the original author of the two projects, the more I realized the code provides almost no comments and wire and register definitions are quite ambiguous and non-intuitive. In my opinion the code needed desperately a rework to be better understandable which would also lead to a lower learning curve for others also trying to implement and adapt the existing code base to their needs. Two major things I tried improving with my fork of openOFDM: The introduction of directional prefixes for module ports. I have seen such in the code of another NLnet founded guy called Dan Nissselquist. Adding the prefix  „i_“ to  input ports (defined as wires/registers in Verilog) and „o_“ to the port definition makes it IMHO much easier when browsing through the code, allowing to instantly realize which wire or register is being exported from this current module and which is only a local element. I added these prefixes all over the code of openOFDM. See my fork of openOFDM on GitHub [1] for details. The next thing I found hard to understand, was the use of the ever repeating word „sample“ for all data along the signal path, from the input of the openOFDM core (ADC base-band data) up to near the exit (decoded data bytes). As there is a switch from time domain (endless sample stream) into frequency domain (blocks of 64 frequency bands) in the module „sync_long“, I changed the name of all wires and registers after this module and renamed them into „spectrum“.  Also some comments were added to clarify what a wire or register is doing at a certain point. This work is not yet regarded as being completed. Each time I dig into the original code, I will add comments and try to make the code more „barrier free“.


**3. Create a new fork of openOFDM**

This has been done and the new fork of openOFDm can be found here:

[1] https://github.com/Tobias-DG3YEV/openofdm

It contains comments and my code changes proposed earlier in this document.


**4. Try adding additional meta date stubs**

As I tried figuring out which meta data could be used to distinguish between  genuine transmitting device and a counterfeit device, I found an article at mathworks.com [3] reporting that they proved finding counterfeit, evil twins of a WiFi Access Point by feeding the raw sampled channel data of a transmission into a ML algorithm. For this purpose they followed a kind of a brute force approach by taking all samples of a received frame into account and fed into a ML algorithm. Even the smallest frame like an information or flow control frame that is only 100uS of duration will produce 16kBytes of data which is rather huge. This amount of data may be processable - if the SDR is directly connected to a powerful computer with multiple cores etc. The project RA-Sentinel does not follow this kind of big processing power approach. Amplitude, phase and frequency change due to several effects during the transmission of a frame, but all of these changes always result in a phase shift. So I thought, in  the first attempt identifying a WiFi transmitting device by characterizing (or say learning) the phase deviation over time may be sufficient. Because the RF receiver front end of the RA-Sentinel project has a low noise and high stability master clock (a 40MHz TXCO by Abracom) that is multiple times more accurate that standard commercial WiFi transmitters, I hope that a small amount of phase shift data received in the beginning of a WiFi frame may be enough to clearly identify counterfeit devices. 

**5. Redefine a new simplified interface to access meta parameters**

One thing I have learned throughout the project progress so far, is that even many may say that an FPGA is one of the most versatile digital programmable devices available today, allowing the implementation of any kind of parallel and sequential tasks up to integration of soft-core processors the fact is that all this integrated logic leads to a rather time consuming iterative development process. To optimize WiFi data reception on one side and to interpret and forward meta data on the other side all inside the FPGA leads to an extremely slow and challenging development process. For the analysis of meta data, an external, traditional single chip microprocessor running straight C/C++ code,  offers much more opportunities and most importantly, allows much a faster  development progress. Bit for that, I need a fast and reliable interconnection between the FPGA and the micro processor.

I identified and implemented two interfaces which allow to access 

The first interface I implemented into the FPGA was the SPI slave interface. This interface allows reading and writing 32 wide registers inside the FPGA by an external micro controller (in this case, I use a STM32H743 Cortex-M7)

The SPI interface allows access to the following parameters:

- Receiver characteristics like receiver center frequency, gain, power threshold, max. error rate etc.

- reading current receiver parameters like noise level, signal to noise ratio etc.

Further I needed an interface that is capable transferring header and  metadata that is produced with each WiFi 802.11 frame received to my  external ARM processor. As I cannot foresee at this point in the project how much meta data is needed to distinctly identify a sender hardware of a frame, I was looking for a method to reliably transport greater chunks of data from the FPGA directly into the memory of the external micro-controller without code intervention. Hence, I started evaluating the possibilities based on the peripheral capabilities of the STM32 device family.  After I had invested some effort into research and experiments, I found that SPI especially in a 4-Bit configuration might feasible as it is able transporting 25MByte/s. But the digital camera interface (DCMI) that many of those top range micro-controllers provide, offer 8 Bit parallel data transfer directly into the controller’s memory via DMA at a maximum rate of 80MBytes/s.

So the next step was to design a logic circuit into the FPGA that can mimic the signaling of a digital camera module with DCMI interface. This has been implemented on both sides, the FPGA in Verilog Code and on the STM32H7 in C language. 

The received 802.11 frame info packet that is streamed upon each complete frame reception has the following format:

**Resources:**

[1] https://github.com/open-sdr/openwifi-hw/

[2] https://github.com/Tobias-DG3YEV/openofdm

[3] https://de.mathworks.com/help/comm/ug/design-a-deep-neural-network-with-simulated-data-to-detect-wlan-router-impersonation.html

Project Maintainer: Tobias Weber

Last updated: 27. Feb. 2025
