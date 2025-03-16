## Errors, Issues and improvements found in RASBB PCB design revision A.

| ID 	| State 	| Description 	                      | Solution          |
|----	|-------	|-------------	                      |-------            |
| 1  	| open  	| Footprint J5 and J6 are 1.0mm pitch | change to 1.27mm  |
| 2  	| open   	| Rename Pins of D11 to JTAG signal   | |
| 3  	| open  	| Add marking point of Pin 1 on headers  | |
| 4  	| open  	| J9 is smaller than expected         | needs to be shifted more towards PCB edge |
| 5  	| open  	| J12 needs a 180deg rotation         | |
| 6  	| open  	| DDR3 RAM VSSQ_5 connected to 1.35V  | |
| 7  	| open  	| Add LEDs to all DC DC Outputs       | |
| 8  	| open  	| Add shut restistors at the in/output of each DC DC | |
| 9  	| open  	| 1V DC DC EN voltage too low         | Remove R36 and R37, connect U3A Pin 21 to 5V LDO out Pin 22 |
| 10 	| open    | No Indication fur MCU if FPGA is on | Wire the two DONE lines from FPGAs to unused MCU pins |
| 11 	| open    | No visible feedback from FPGAs | Add some indication LEDS to each FPGA. If 4 have space, go with 4 per FPGA |
| 12	| open    | Rename DEBUG pins of FPGA           | Better call them ICON01 02 etc |
| 13	| open    | ICON does only have 32 lines        | Needs to be increased to 32+8 total of 40 lines |
| 14 	| open    | ICON has no protection resistor     | add 100R resistor arrays on each side |
| 15	| open    | MCU LEDs are very bright  	        | increase pre-diode resistors to 1k |
| 16	| open    | J16, J18 Non-Standard header spacing | increase spacing of J16, J18 to 0.1" / 2.54mm |
| 17 	| open    | Add human readable labels to pin headers | like "MCU JTAG", "AP JTAG" (for FPGA01) and "DP JRAG" für FPGA02 and add thermal isolation to drill holes |
| 18 	| open    | Rotate one JTAG pin header so the have the same orientation | |
| 19	| open    | Add one more button for FPGA internal Reset | Maybe use smaller ones and change thos of PROGRAM_B also to save space |
| 20	| open    | Change U12 to RTL8211FS with PTP support | |
| 21 	| open    | Cannot measure power requirements of DC sources | Add a dummy resistor (0 Ohms 0805 and a 1.27mm 2 pole header to measure volt. drop) to each output od each DC regulator |
|   	| open    |             	                      | |
