## Bring-up and measurement results, RASRF2400WBMC revision A.

| ID | State | Description | Result |
|----|-------|-------------|--------|
| 1 | pass | MAX2831 PLL lock, all four channels | locked |
| 2 | pass | ADC3424 configuration verified over SDOUT, both devices | verified |
| 3 | pass | Deserialisation of all four channels to the RASPMO quad-split display | all four present |
| 4 | pass | Baseboard commands the array over I2C | responds |
| 5 | pass | Firmware identity, 32 KB read back over SWD against `Debug/RASRF2400BMC.elf` | byte-for-byte identical, stamp `097aab2` |
| 6 | pass | Live `s_rxGain` read from the running firmware | `68` |
| 7 | pass | I2C console commands `ID`, `ST`, `GG`, `SG`, `SF`, `GF` | all answered |
| 8 | pass | Retune time, command to settled | 56 ms |
| 9 | pass | Absolute calibration, −60 dBm CW at 2439 MHz | reads −18 dBFS |
| 10 | pass | Port referral derived from item 9 | 0 dBFS ≈ −42 dBm |
| 11 | pass | ADC clip point at the port | ≈ −42 dBm |
| 12 | pass | Ambient on-air signal recorded through the array | −45 dBFS ≈ −87 dBm |
| 13 | pass | RX gain code `0x68`, LNA high and VGA 16 dB, checked on air with the RASANT2400 | confirmed, left unchanged |
| 14 | pass | System power at 12 V, measured as an input delta | +2.92 W |
| 15 | pass | Image rejection, CH3 and CH4 | −45 dB |
| 16 | projected | Image rejection, CH1 and CH2 | −45 dB |
| 17 | pass | Four-channel amplitude match on air | −45 dBFS on all four |
| 18 | pass | Self-test register `0x08`, ramps either ADC on demand with the other live as a control | working |
| 19 | pass | `SR` / `GR` console commands, split a digital-path fault from an analogue one without a rebuild, a reflash, or moving the ST-LINK | working |
| 20 | pass | `SR` reads the register back rather than echoing the request | correct readback |
| 21 | — | Bring-up test video | https://www.youtube.com/watch?v=SnHPaw8y9vc |

