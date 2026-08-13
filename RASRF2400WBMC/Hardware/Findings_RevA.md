## Errors, Issues and improvements found in RASBB PCB design revision A.

| ID 	| State 	| Description 	                      | Solution          |
|----	|-------	|-------------	                      |-------            |
| 1  	| open  | Silkscreen misses ADC designators | add  |
| 2  	| open  | 10 kΩ pull-up from ADC1_CS to +1V8, mirroring R125 on ADC2_CS. | add |
| 3  	| open  | Pull resistors on SPI_SCLK / SPI_MOSI at U3's A-side — AXC inputs must not float, and there are none today. | add |
| 4  	| open  | Wire IC5/IC6 pin 24 (RESET) to spare STM32 GPIOs; optionally pin 37 (PDN) as well. | add |
| 5  	| open  | Add ferrite bead and decoupling C at the input of 3.3V to suppress 1.8MHz spurious signal | add |
| 6  	| open  | Add opening in solder mask at a PCB corner to allow connecting debug ground clamps | add |
| *7  	| open  | Replace the two 4 channel ADCs with one 8 channel ADC to have better phase alignement between all channels | exchange |
| **8     | open  | Replace MAX2831 should be exchange with MAX2837| exchange |

\* Items 7 and 8 are not cosmetic fixes like 1 to 6. Both came out of chasing phase
errors that would not calibrate away. Neither can be fixed by adding a component,
the parts themselves have to change.

## Findings behind items 7 and 8

### 7. Two ADC3424 -> one 8 channel ADC

Issue: two converters mean two clock paths and two LVDS links to length match, and
two startup alignments that both have to come up correctly. On top of that,
channels on the same chip match well and drift together, while channels on two
separate chips only match within the datasheet range, and that gap moves with
temperature.

Solution: one 8 channel converter. All eight channels sit on one die, in a single
timing and alignment domain. That removes an inter device calibration term and
halves the capture logic.


### 8. MAX2831 -> MAX2837

Issue: the MAX2831 leaves the PLL's most noise sensitive node unshielded, so
supply and neighbouring channel noise reaches it. Each channel has its own PLL, so
this noise is independent per channel and does not cancel when we compare phase
between antennas. It goes straight into the bearing as jitter, and the coupling is
inside the chip, so nothing on the board fixes it. The MAX2831 is also write only,
so with four chips that must be set identically we cannot confirm that they are.

Solution: MAX2837. Balanced wiring shields that node, and SPI readback lets us
verify all four chips.

