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
| 11 	| open    |             	                      | |
|   	| open    |             	                      | |
