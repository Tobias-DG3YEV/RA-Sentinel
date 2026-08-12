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


Items 7 and 8 are not cosmetic or convenience fixes like 1–6. Both came out of the same investigation: we were chasing phase errors that would not calibrate away, and traced them to two structural properties of the rev A signal chain. Neither can be fixed by adding a component — the parts themselves have to change. Detail below.

##
Findings behind items 7 and 8:

7 - Two 4-channel ADCs -> one 8-channel ADC

Four transceivers × I/Q = 8 ADC inputs. Split across two converters, the two devices run from independent internal timing - dividers, startup state, reset sequencing. Inter-device sample skew is therefore an unknown that must be measured and calibrated out, and it can change on any power cycle. 

A single 8-channel part puts all eight channels behind one sampling clock and one internal timing domain. Channel-to-channel skew reduces to a fixed, characterizable device parameter instead of a per-boot variable. This is the reason the change is needed - it converts a moving error into a constant one.

8 - MAX2831 -> MAX2837

The MAX2837's balanced loop-filter wiring shields the PLL's most noise-sensitive node from supply and neighbouring-channel interference, giving a more robust loop filter and therefore lower phase noise.

That is what we observed in rev A, and it is why the exchange is needed: the noise path is internal to the part, so no amount of filtering or layout work on our side closes it. The result of the change is more accurate, more stable bearings and far fewer intermittent one-channel faults, which are expensive to chase.

