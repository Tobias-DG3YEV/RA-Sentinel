# RASRF2400WBMC - Hardware Description

## What this board does

The RASRF2400WBMC is the RF front end for the directional extension of RA-Sentinel. Where the original single-channel board can tell you *that* a WiFi attack is happening, this one can tell you *where it's coming from*. It does that by receiving the same signal on four separate antennas simultaneously and measuring the phase difference between channels - from which the RASBB can calculate the Angle of Arrival (AoA).

The board was designed to plug into the same PCIe slot as the single-channel RASRF_2400WB. No changes to the RASBB are needed; the baseboard already has enough ADC inputs and the FPGA handles the rest.

---

## Signal chain

Four antennas connect through balun transformers (HHM1902B1) directly into four MAX2831 transceivers. The MAX2831 is a direct-conversion 2.4 GHz chip - it downconverts the incoming signal to baseband I/Q, which comes out as a differential analog signal. Those analog outputs feed two ADC3424 converters (Texas Instruments, 12-bit capable - **6-bit effective**, quad-channel, 40 MSPS). Only the D0 LVDS output pairs are connected; D1 pairs are left unconnected. Each ADC handles two channels (I+Q each), so ADC #1 digitises CH1 and CH2, and ADC #2 handles CH3 and CH4. The resulting LVDS streams go through the PCIe connector to the RASBB, where the FPGA picks them up.

Total digital data rate: four channels x 6-bit I/Q x 40 MSPS = ~ 1.92 Gbit/s.

```
ANT 1 --+
ANT 2 --+--[ 4x MAX2831 ]-[ I/Q analog ]-[ ADC3424 #1 ]-[ LVDS D0 ]-|
ANT 3 --+                                  [ ADC3424 #2 ]-[ LVDS D0 ]-|-[ PCIe ] -> RASBB
ANT 4 --+                                                              +
```

---

## Clock distribution

Phase coherence across the four channels depends entirely on all four MAX2831 chips and both ADCs sharing a single reference clock. A 5PB1206NDGK8 clock fanout buffer takes the 40 MHz reference from an onboard TCXO and distributes it to six outputs: one per MAX2831 and one per ADC. PCB trace lengths from the fanout to each chip are matched.

---

## Housekeeping MCU

A STM32C031K6U6 manages startup and configuration. It talks to all four MAX2831 chips and both ADC3424s over a shared SPI bus, with individual chip selects per device. A level shifter (SN74AXC4T774RSVR) handles the voltage translation between the STM32 and the ADCs SPIs pins. The STM32 also has an I2C interface connected to the RASBB, so the RASBB can send configuration commands or read status without the STM32 needing a standalone firmware update for each parameter change.

---

## Power supply

The board takes 3.3 V from the PCIe connector and generates the additional rails locally:

- **1.8 V** - LD1117 LDO, for the ADC3424 core supply
- **3 V** - ADP7154 LDO, for the MAX2831 supply rails

---

## Key components

| Part | Function |
|------|----------|
| Maxim MAX2831 x4 | 2.4 GHz direct-conversion transceiver, RX only in this design |
| TI ADC3424 x2 | 12-bit capable (6-bit effective, D0 only), quad-channel ADC, 40 MSPS, LVDS output |
| 5PB1206NDGK8 | 6-output clock fanout buffer, drives all four transceivers and both ADCs |
| STM32C031K6U6 | Housekeeping MCU - SPI config, I2C to RASBB |
| SN74AXC4T774RSVR | 4-bit dual-supply level shifter (3.3 V <-> 1.8 V) |
| HHM1902B1 x4 | 2.4 GHz balun, single-ended to differential conversion at antenna input |
| LD1117DT18  | 1.8 V LDO regulator |
| ADP7156ACPZ-3.0-R7 | Adjustable LDO, set to 3V |

---

## Block diagram
![Block Diagram](https://raw.githubusercontent.com/MinDans/RA-Sentinel/main/RASRF2400WBMC/Images/RASRF2400WBMC_BlockDiagram.svg)

---

## PCBA
<div align="center">
  <img src="https://raw.githubusercontent.com/MinDans/RA-Sentinel/main/RASRF2400WBMC/Images/RASRF2400WBMC_RevA_front.jpg" width="400">
  <br><em>RASRF2400WBMC Top-side</em>
  <br><br>
  <img src="https://raw.githubusercontent.com/MinDans/RA-Sentinel/main/RASRF2400WBMC/Images/RASRF2400WBMC_RevA_back.jpg" width="400">
  <br><em>RASRF2400WBMC Bottom-side</em>
</div>

---

## Design notes

See [Design Notes](https://github.com/MinDans/RA-Sentinel/blob/main/RASRF2400WBMC/Docs/Design_Notes.md) for antenna spacing derivation, AoA algorithm selection, phase coherence strategy, and the open questions list being worked through during the design phase.

---

*Hardware design: Mina Daneshpajouh*
*Firmware / signal processing: Tobias Weber*
