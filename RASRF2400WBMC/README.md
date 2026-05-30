# RASRF2400WBMC - 4-Channel Directional RF Front End

Licensed under **CERN-OHL-S**. See LICENSE.TXT for details.

## Overview

The **RASRF2400WBMC** is a 4-channel, 2.4 GHz RF front-end board designed as a directional extension to the RA-Sentinel WiFi intrusion detection system. While the single-channel RASRF2400WB board can detect malicious WiFi attacks, this board adds the ability to determine the **direction from which an attack originates**.

By receiving the same signal across four spatially separated antennas in a phase-coherent manner, the system can estimate the **Angle of Arrival (AoA)** of incoming RF signals. This enables **threat localization** - helping to physically identify and locate sources of jamming, spoofing, Man-in-the-Middle, or Denial of Service attacks.

This board connects to the existing [RASBB](https://github.com/MinDans/RA-Sentinel/tree/main/RASBB) (RA-Sentinel Base Band Board) via a PCIe connector, making use of its multiple ADC input lines without requiring any changes to the base band hardware.

---

## System Architecture

```
ANT 1 --+
ANT 2 --+--[ 4x MAX2831 ]-[ I/Q analog ]-[ ADC3424 #1 ]-[ LVDS D0 ]-|
ANT 3 --+                                  [ ADC3424 #2 ]-[ LVDS D0 ]-|-[ PCIe ] -> RASBB
ANT 4 --+
```

All four channels are **phase-coherent**, meaning the RASBB can compare the phase difference between channels to compute the Angle of Arrival of a detected signal.

---

## Hardware Specifications

| Parameter            | Value                                        |
|----------------------|----------------------------------------------|
| Frequency            | 2.4 GHz ISM band                             |
| Number of channels   | 4 (phase-coherent)                           |
| Transceiver          | Maxim MAX2831 (x4)                           |
| Digitization         | TI ADC3424 x2 - 6-bit eff. - 40 MSPS        |
| Interface to RASBB   | PCIe connector                               |
| Antenna              | [RASANT2400](https://github.com/MinDans/RA-Sentinel/tree/main/RASANT2400/Hardware/KiCad) |
| Primary function     | Angle of Arrival (AoA) estimation            |
| Status               | Sent for manufacturing - not yet delivered   |

---

## Repository Structure

```
RASRF2400WBMC/
+-- README.md                          This file
+-- Hardware/
|   +-- KiCad/                         Source design files
|   |   +-- RASRF2400WBMC.kicad_pro
|   |   +-- RASRF2400WBMC.kicad_sch
|   |   +-- RASRF2400WBMC.kicad_pcb
|   |   +-- Libraries/
|   |       +-- Footprints/           KiCad footprints
|   |       +-- Symbols/              KiCad symbols
|   +-- Production/
|       +-- RevA.0/                   Manufacturing outputs for Revision A.0
|           +-- Gerbers/              Gerber + drill files (.gbr, .drl)
|           +-- PickAndPlace/         Component placement files (.csv)
|           +-- BoM/                  Bill of Materials (.csv)
+-- Images/                           Board renders, photos, block diagrams
+-- Docs/
    +-- Design_Notes.md               Design decisions, antenna spacing, AoA theory
```

---

## Relationship to Other RA-Sentinel Boards

| Board                | Antennas | Purpose                       | Interface        |
|----------------------|----------|-------------------------------|------------------|
| [RASRF2400WB](https://github.com/MinDans/RA-Sentinel/tree/main/RASRF2400WB)          | 1        | Wideband detection            | PCIe -> RASBB    |
| [RASRF2400WBMC](https://github.com/MinDans/RA-Sentinel/tree/main/RASRF2400WBMC)        | 4        | Detection + direction finding | PCIe -> RASBB    |
| [RASBB](https://github.com/MinDans/RA-Sentinel/tree/main/RASBB)                | -        | Base band processing (shared) | -                |
| [RASANT2400](https://github.com/MinDans/RA-Sentinel/tree/main/RASANT2400/Hardware/KiCad) | - | 2.4 GHz antenna for RF front ends | - |

Both RF front-end boards are designed to work with the same RASBB.

---

## Status

>  This board has been sent for manufacturing and not yet delivered. A bring-up log will be added to `/Docs/` once the first boards arrive.

---

## Funding

This project was funded through the **NGI0 Commons Fund**, a fund established by NLnet with financial support from the European Commission's Next Generation Internet programme, under the aegis of DG Communications Networks, Content and Technology under grant agreement No 101135429. Additional funding is made available by the Swiss State Secretariat for Education, Research and Innovation (SERI).

<a href="https://nlnet.nl/commonsfund/"><img src="https://nlnet.nl/image/logos/NGI0_tag.svg" alt="NGI0 Commons Fund" width="20%"></a>
<a href="https://nlnet.nl/project/RA-Sentinel-directional/"><img src="https://nlnet.nl/logo/banner.svg" alt="NLnet" width="20%"></a>

---

## Project Maintainer

Mina Daneshpajouh, Tobias Weber

