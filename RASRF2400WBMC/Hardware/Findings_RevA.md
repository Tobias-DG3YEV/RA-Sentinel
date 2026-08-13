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
| 9   | open  | Add Tx capabilites to one MAX. With this reference signal it produces, we can calibrate amplitudes between channels. Highest accuracy is needed for AOA. | add |
| 10  | open  | Add RF switch in front of each MAX RF input to make it switchable to the reference signal | add |
| 11  | open  | Add additional DAC including LVDS wiring to FPGA for MAX test signal generator facility | add |

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

### 9 to 11. Received signal amplitude improvement

Issue: The MAX sensitivity and amplification varies over its channels. 
With this effect, an estimation of bearing foa WiFi node is difficult
based on received signal amplitude. We need that function as a complement and
fallback for phase AOA detection. 

Technical details: It looks like it has a class C amplifier and as we know, the bias current is sensitive for drift
over temperature. There might me a correction circuit inside the MAX but that is not doing
well. We hope to get better reception results with the MAX2837.
The variation is also caused by internal part tolerances amplified by different temperatures
we have at different board areas. To calibrate this away,
we need a reference signal. As the MAX family aready contains a complete 2.4GHz tranceiver,
it makes sense to make this assiable to all 4 input channels through tiny RF switches.
With a reference level transmitted from one max at different levels, we can also calibrate away non-linearities
in the amplification of the complete Rx path.

Solution: Add Tx and switching matrix capabilites to MAX tranceiver chip.
