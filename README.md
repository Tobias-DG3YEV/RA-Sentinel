# RA-Sentinel
FPGA-based Radio Receiver for securing Wifi against hacking attacks

RAsentinel is an open-source project focused on creating a cost-effective, small, and low-power wide band radio receiver device that employs an FPGA to automatically detect malicious attacks on Wifi access points, such as Man in the Middle and Denial of Service attacks. By monitoring any Wifi cell, the device enhances internet safety for everyday users.
The device features low-cost receive-only chips that digitize 40 MHz of the Wifi radio spectrum at 2.4 GHz. An FPGA extracts relevant properties from demodulated and decoded packets in real-time without storage. These properties are then processed by a neural network, also implemented on the FPGA, to determine if the traffic is genuine or an attack.



![Alt text](/RAsentinel-Blockdiagram.JPG "Optional title")
