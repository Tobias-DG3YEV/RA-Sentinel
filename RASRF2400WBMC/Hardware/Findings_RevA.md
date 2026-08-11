## Errors, Issues and improvements found in RASBB PCB design revision A.

| ID 	| State 	| Description 	                      | Solution          |
|----	|-------	|-------------	                      |-------            |
| 1  	| open  | Silkscreen misses ADC designators | add  |
| 2  	| open  | 10 kΩ pull-up from ADC1_CS to +1V8, mirroring R125 on ADC2_CS. | add |
| 3  	| open  | Pull resistors on SPI_SCLK / SPI_MOSI at U3's A-side — AXC inputs must not float, and there are none today. | add |
| 4  	| open  | Wire IC5/IC6 pin 24 (RESET) to spare STM32 GPIOs; optionally pin 37 (PDN) as well. | add |
| 5  	| open  | Wire SYSREF_CLK of each ADC to a pin header | add |
| 6  	| open  | Add ferrite bead and decoupling C at the input of 3.3V to suppress 1.8MHz spurious signal | add |
| 7  	| open  | Add opening in solder mask at a PCB corner to allow connecting debug ground clamps | add |

