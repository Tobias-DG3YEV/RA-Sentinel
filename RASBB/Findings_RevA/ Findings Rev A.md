## Errors, Issues and improvements found in RASBB PCB design revision A.

| ID 	| State 	| Description 	                      | Solution          |
|----	|-------	|-------------	                      |-------            |
| 1  	| closed  | Footprint J5 and J6 are 1.0mm pitch | change to 1.27mm  |
| 2  	| closed  | Rename Pins of D11 to JTAG signal   | |
| 3  	| closed  | Add marking point of Pin 1 on headers  | |
| 4  	| closed  | J9 is smaller than expected         | needs to be shifted more towards PCB edge |
| 5  	| closed 	| J12 needs a 180deg rotation         | |
| 6  	| closed 	| DDR3 RAM VSSQ_5 connected to 1.35V  | |
| 7  	| closed  | Add LEDs to all DC DC Outputs       | |
| 8  	| closed  	| Add shut restistors at the in/output of 1V DC DC | |
| 9  	| closed 	| 1V DC DC EN voltage too low         | Modify the value of resistor divider R36 and R37|
| 10 	| closed  | No Indication fur MCU if FPGA is on | Wire the two DONE lines from FPGAs to unused MCU pins |
| 11 	| closed  | No visible feedback from FPGAs | Add some indication LEDS to each FPGA |
| 12	| rejected    | Rename DEBUG pins of FPGA           | Better call them ICON01 02 etc |
| 13	| closed (Rev C)  | ICON change from J5/J6 to one 50pin 0.5mm FPC | also pin count needs to be increased to 32+8, a total of 40 lines |
| 14 	| closed (Rev C)    | ICON has no protection resistor     | add 47R resistor arrays on each side towards FPGA |
| 15	| closed  | MCU LEDs are very bright  	        | increase pre-diode resistors to 1k |
| 16	| closed  | J16, J18 Non-Standard header spacing | increase spacing of J16, J18 to 0.1" / 2.54mm |
| 17 	| closed  | Add human readable labels to pin headers | like "MCU JTAG", "AP JTAG" (for FPGA01) and "DP JRAG" für FPGA02 and add thermal isolation to drill holes |
| 18 	| closed  | Rotate one JTAG pin header so the have the same orientation | |
| 19	| open    | Add one more button for FPGA internal Reset | Connect the line also to the STM32 so this can also pull the reset of the FPGA. Maybe use smaller ones and change thos of PROGRAM_B also to save space |
| 20	| rejected    | Change U12 to RTL8211FS with PTP support | |
| 21	| closed  | Add JTAG header target to silkscreen Text | like "STM32", "FPGA 1", "FPGA 2"|
| 22	| closed  | Correct second flash signals to FPGA2 | SO and SI connection should be swapped |
| 23	| closed  | Terminate all LVSD signals with 100Ohm |  |
| 24	| closed  | Pin out of ethernet jacks are wrong. | Pins 17-20 are mixed with 13-16 |
| 25	| closed  | DDR3 RAM A14 not connected | wire to free pin on same bank as A13 |
| 26  | open | Add 40MHz and 1MHz sync clock over Ethernet. One pair of the 100MBit connection to the STM32 receives 40MHz and 1MHz clock via line receivers and send it (unbalanced is good enogh) into the U10 FPGA 1 and 2 (1MHz) and the 40MHz shall be provided via SMA/SMB jack via coax wire to the FE. Do not popuilate the jack, i will solder by hand.
| 28  | open  (Rev C) | Connect an output pin of FPGA2 to a RC low pas filter (mimics a PWM DAC)
| 29  | closed  | Add shunt resistor (0805) and 2 pin header paralell in front of PCIE connector to be able to measure front end power consumption.
| 30  | open  | WP# and #RESET of FPGA config flashes is unconnected | Add 10 kΩ pull-up to VCC3V3 
| 31  | open  | Add solder mask opening squares at the edges to support ground connection for flying probes
| 32  | open  | Enable Voltage U3 uncertain | Change R36 from 100k to 220k to have a safe window 2.0 V < EN < 5.3 V across the full 10.8–13.2 V input
