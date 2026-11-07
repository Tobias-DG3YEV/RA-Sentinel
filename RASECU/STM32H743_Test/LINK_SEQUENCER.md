# Link sequencer (ported from LOTAG/LOGW/Firmware/ECU, 2026-08-29)

`Core/Src/logw_seq.c` runs as its own task and brings the receive chain up in
order: front end (I2C 0x42, model 0x21 = RASRF6000, STATUS INIT_DONE +
CLK_LOCK) → FPGA1 bitstream present (SPI STATUS signature `101` in bits 7:5)
→ HKU register 0x09 ramp ON → FPGA CONTROL RETRAIN → wait for trained →
ramp OFF → RUN, and re-runs the cycle when the FPGA disappears and comes back
(bitstream reload), when the front-end clock lock drops, or when the capture
loses "trained" for more than 2 s. Full description and the state table:
`LOTAG/LOGW/Firmware/ECU/README.md` (the authority, keep the copies in step).

Works with the FPGA designs that carry `spi_ctrl_if.v`: RASM2400
`top_LVDSTEST` (both capture modes) and LOGW. OWIFI_RX's `spi_frame_if` has
LINK_OK/FE_VALID but neither the signature nor a RETRAIN control, so with an
OWIFI bitstream the sequencer stays in WAIT_FPGA and touches nothing; the
frame read-out task keeps working (it now holds `logw_bus_lock()` around each
poll so it cannot tear a sequencer transaction).

Console (USART3): `LS` state + both statuses + lane taps + event history,
`LR` force one training cycle, `LP 0|1|2` automatic / park with ramp on / off.

Build: `STM32CubeIDE/Debug` (`make -j8 all` with the ST toolchain first on
PATH) - `subdir.mk`, `objects.list` and `.project` carry `logw_seq.c`.
