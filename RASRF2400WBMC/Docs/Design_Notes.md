# 

>  This document is a living record of design decisions made during development. It will be updated as the design matures and bring-up begins.

---

## 1. Motivation and Design Goals

The single-channel RASRF2400WB board can detect the presence a WiFi attack (e.g. jamming, spoofing), but cannot determine where the attacker is physically located. In dense environments - offices, apartment buildings, public venues - this limits the usefulness of the detection: an alert without a direction is difficult to act on.

The RASRF2400WBMC adds a spatial dimension to RA-Sentinel's detection capability by implementing a 4-element antenna array with phase-coherent reception. From the phase differences measured across channels, the RASBB FPGA can compute the Angle of Arrival (AoA) of any detected transmission.

---

## 2. Angle of Arrival (AoA) Theory

### 2.1 Basic Principle

Angle of Arrival (AoA) allows the determination of the direction a wireless signal is coming from. Four directional antennas connected to four receivers are arranged to each "look" in a different direction, together covering the full 360° surroundings. When a device transmits a signal, each antenna receives it at a slightly different moment, and by precisely measuring those tiny timing differences the system can calculate the exact angle the signal came from. Using four antennas instead of just two or three improves accuracy and eliminates ambiguities. 

### 2.4 Algorithms Considered

To be added

---

## 3. Phase Coherence Strategy

All 4 MAX2831 transceivers must share a single reference clock to ensure phase coherence across channels. Any independent oscillator drift would introduce pseudo-random phase offsets that make AoA estimation impossible.

**Approach:**
- Route a single master clock (from RASBB or an on-board TCXO) to all four MAX2831 REF_CLK inputs
- Use matched-length PCB traces from the clock source to each transceiver
- Use matched-length traces from ADC outputs to the PCIe connector

The MAX2831 requires a 40 MHz reference clock. This is consistent with the 40 MHz TCXO already used on the RASRF2400WB board.

---

## 4. ADC and Data Path

Each MAX2831 produces a baseband I/Q analog output. Each of the 4 channels feeds an ADC for digitisation. The digitised streams are serialised for transport over the PCIe interface to the RASBB.

Data rate estimate per channel:
- 6-bit I, 6-bit Q @ 40 MSPS = 480 Mbit/s per channel (ADC3424 D0 only - D1 pairs not connected)
- 4 channels = 1.92 Gbit/s total

---

## 5. PCB Stack-up 

The RASRF2400WBMC PCB will use a **6-layer stack-up**:

| Layer | Function                     |
|-------|------------------------------|
| Top   | RF and signal routing        |
| L2    | Ground plane                 |
| L3    | Power plane/signal routing   |
| L4    | Power plane/signal routing   |
| L5    | Ground plane                 |
| L6    | Signal routing               |
