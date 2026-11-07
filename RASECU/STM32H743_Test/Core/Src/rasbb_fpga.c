/*
 * rasbb_fpga.c - host-side driver for the OWIFI_RX frame read-out port.
 * See rasbb_fpga.h. Target: STM32H743VGT6 (IC12) on RASBB, SPI4 master.
 *
 * Deliberately BLOCKING, not DMA. A worst-case frame is ~2KB, which at
 * 12.5MHz takes 1.3ms - nothing against a 500ms frame interval - and going
 * blocking sidesteps the H7 D-cache/DMA coherency trap entirely. If this ever
 * needs DMA (a busy channel with thousands of frames/s), put the buffers in a
 * non-cacheable MPU region or invalidate after each transfer; a stale cache
 * line looks exactly like a corrupted frame and wastes a day.
 */
#include "rasbb_fpga.h"
#include "main.h"
#include <string.h>

extern SPI_HandleTypeDef hspi4;

/* ---- pin map (RASBB.kicad_pcb + STM32H743_Test.ioc labels) --------------
 * Override these in main.h / build flags if the labels move.
 *   PE11 CS   -> CS_FLASH_uC  -> FPGA1 E18   (software CS, NOT hardware NSS:
 *                one CS-low window must span a whole multi-hundred-byte burst)
 *   PB15 CS_MUX1  = SWITCH_FLASH_1  (IC12 pad 54)
 *   PA10 EN_MUX1  = MUX_EN1         (IC12 pad 69)
 */
#ifndef RASBB_CS_PORT
#define RASBB_CS_PORT      SPI4_NSS_GPIO_Port   /* PE11 */
#define RASBB_CS_PIN       SPI4_NSS_Pin
#endif
#ifndef RASBB_SWFLASH_PORT
#define RASBB_SWFLASH_PORT CS_MUX1_GPIO_Port    /* PB15 = SWITCH_FLASH_1 */
#define RASBB_SWFLASH_PIN  CS_MUX1_Pin
#endif
#ifndef RASBB_MUXEN_PORT
#define RASBB_MUXEN_PORT   EN_MUX1_GPIO_Port    /* PA10 = MUX_EN1 */
#define RASBB_MUXEN_PIN    EN_MUX1_Pin
#endif

#define RASBB_TIMEOUT_MS  100u

/* Chunked dummy source for read phases - avoids a 2KB zero buffer in RAM. */
static const uint8_t rasbb_dummy[64] = { 0 };

/* HAND EDIT 2026-09-19: the SPI4 lines and CS_FLASH_uC are the FPGAs' own
 * configuration/flash bus. FPGA1 reads its 3.8 MB bitstream from IC5 for
 * ~1 s after power-up; any ECU clock edge or CS activity in that window
 * corrupts the load (proven: flash verified OK, DONE=0 after every
 * power-cycle, but DONE=1 when the FPGA was rebooted with the ECU halted).
 * So: no transaction and no CS assertion for the first 3 s after power-up.
 * Callers see a failed transfer and retry later (presence logic). */
#define RASBB_BOOT_QUIET_MS 3000u
static inline bool boot_quiet(void) { return HAL_GetTick() < RASBB_BOOT_QUIET_MS; }
static inline void cs_low(void)  { if (!boot_quiet()) HAL_GPIO_WritePin(RASBB_CS_PORT, RASBB_CS_PIN, GPIO_PIN_RESET); }
static inline void cs_high(void) { HAL_GPIO_WritePin(RASBB_CS_PORT, RASBB_CS_PIN, GPIO_PIN_SET); }

static bool xfer(const uint8_t *tx, uint8_t *rx, uint16_t n)
{
    if (boot_quiet()) return false;
    return HAL_SPI_TransmitReceive(&hspi4, (uint8_t *)tx, rx, n,
                                   RASBB_TIMEOUT_MS) == HAL_OK;
}

/* Clock n bytes in while sending zeros, in <=64 byte chunks. CS is expected
 * to be held low by the caller for the whole burst. */
static bool read_bytes(uint8_t *dst, uint32_t n)
{
    while (n) {
        uint16_t chunk = (n > sizeof(rasbb_dummy)) ? sizeof(rasbb_dummy) : (uint16_t)n;
        if (!xfer(rasbb_dummy, dst, chunk)) return false;
        dst += chunk;
        n   -= chunk;
    }
    return true;
}

void rasbb_fpga_init(void)
{
    cs_high();

    /* Resting mux state: both controls low (they have 10k pull-downs on the
     * board), which connects the config flash to the FPGA's CONFIGURATION
     * pins and leaves CS_FLASH_uC selecting only the FPGA. This is also the
     * state the board boots in - it is how the FPGA loads from flash with no
     * firmware running. */
    HAL_GPIO_WritePin(RASBB_SWFLASH_PORT, RASBB_SWFLASH_PIN, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(RASBB_MUXEN_PORT,   RASBB_MUXEN_PIN,   GPIO_PIN_RESET);

    /* Enforce the two settings CubeMX gets wrong for this link, so that a
     * regenerated .ioc cannot silently break it:
     *   DataSize - CubeMX defaults H7 SPI to 4BIT unless the .ioc names it.
     *              4-bit frames clock half of every byte; the symptom is a
     *              plausible-looking but self-contradictory status byte.
     *   Prescaler - the .ioc asks for /2 (50MBit/s). The FPGA slave
     *              oversamples SCLK in its 100MHz clock and needs 8 fabric
     *              clocks per bit, so 12.5MHz is the ceiling. */
    if (hspi4.Init.DataSize != SPI_DATASIZE_8BIT ||
        hspi4.Init.BaudRatePrescaler != SPI_BAUDRATEPRESCALER_8) {
        hspi4.Init.DataSize          = SPI_DATASIZE_8BIT;
        hspi4.Init.BaudRatePrescaler = SPI_BAUDRATEPRESCALER_8;  /* 100/8 = 12.5MHz */
        HAL_SPI_Init(&hspi4);
    }
}

uint8_t rasbb_fpga_status(void)
{
    uint8_t tx[2] = { RASBB_OP_NOP, 0x00 };
    uint8_t rx[2] = { 0 };
    bool ok;

    cs_low();
    ok = xfer(tx, rx, 2);
    cs_high();
    return ok ? rx[1] : 0xFFu;
}

bool rasbb_fpga_read_frame(rasbb_frame_t *out)
{
    uint8_t tx[2] = { RASBB_OP_READ_FRAME, 0x00 };
    uint8_t rx[2] = { 0 };
    uint8_t raw[sizeof(rasbb_frame_desc_t)];
    bool ok = false;

    if (!out) return false;

    cs_low();
    if (!xfer(tx, rx, 2))                       goto done;
    if (!read_bytes(raw, sizeof(raw)))          goto done;

    memcpy(&out->desc, raw, sizeof(out->desc));

    /* Never trust a length off the wire: a glitched read must not be allowed
     * to run off the end of the payload buffer. */
    if (out->desc.len == 0u || out->desc.len > RASBB_MAX_FRAME) goto done;

    ok = read_bytes(out->payload, out->desc.len);

done:
    cs_high();
    return ok;
}

bool rasbb_fpga_pop(void)
{
    uint8_t tx[2] = { RASBB_OP_POP, 0x00 };
    uint8_t rx[2];
    bool ok;

    cs_low();
    ok = xfer(tx, rx, 2);
    cs_high();
    return ok;
}

bool rasbb_fpga_poll_frame(rasbb_frame_t *out)
{
    uint8_t st = rasbb_fpga_status();

    if (st == 0xFFu || !(st & RASBB_ST_FRAME_READY)) return false;
    if (!rasbb_fpga_read_frame(out))                 return false;
    /* Only retire it once it is safely in our buffer. */
    return rasbb_fpga_pop();
}

bool rasbb_fpga_status_ext(rasbb_status_ext_t *out)
{
    uint8_t tx[2] = { RASBB_OP_STATUS_EXT, 0x00 };
    uint8_t rx[2];
    bool ok = false;

    if (!out) return false;
    cs_low();
    if (xfer(tx, rx, 2))
        ok = read_bytes((uint8_t *)out, sizeof(*out));
    cs_high();
    return ok;
}

bool rasbb_fpga_write_reg(uint8_t addr, uint32_t value)
{
    uint8_t tx[6], rx[6];
    bool ok;

    tx[0] = RASBB_OP_WRITE_REG;
    tx[1] = addr;
    tx[2] = (uint8_t)(value >> 24);
    tx[3] = (uint8_t)(value >> 16);
    tx[4] = (uint8_t)(value >> 8);
    tx[5] = (uint8_t)(value);

    cs_low();
    ok = xfer(tx, rx, sizeof(tx));
    cs_high();
    return ok;
}

bool rasbb_fpga_read_reg(uint8_t addr, uint32_t *value)
{
    uint8_t tx[6] = { RASBB_OP_READ_REG, addr, 0, 0, 0, 0 };
    uint8_t rx[6] = { 0 };
    bool ok;

    if (!value) return false;
    cs_low();
    ok = xfer(tx, rx, sizeof(tx));
    cs_high();
    if (ok)
        *value = ((uint32_t)rx[2] << 24) | ((uint32_t)rx[3] << 16) |
                 ((uint32_t)rx[4] << 8)  |  (uint32_t)rx[5];
    return ok;
}

bool rasbb_fpga_control(uint8_t ctrl_bits)
{
    uint8_t tx[2] = { RASBB_OP_CONTROL, ctrl_bits };
    uint8_t rx[2];
    bool ok;

    cs_low();
    ok = xfer(tx, rx, sizeof(tx));
    cs_high();
    return ok;
}

/* ---- config-flash bus borrowing ---------------------------------------
 * POLARITY IS INFERRED, NOT MEASURED: both mux controls have 10k pull-downs
 * and the board boots the FPGA from flash with no firmware running, so LOW
 * must be the "flash <-> FPGA config pins" position and HIGH the "flash <->
 * uC bus" position. Verify with a scope on TP22/TP19 before trusting this
 * for an actual flash write.
 */
void rasbb_flash_bus_take(void)
{
    cs_high();
    HAL_GPIO_WritePin(RASBB_SWFLASH_PORT, RASBB_SWFLASH_PIN, GPIO_PIN_SET);
}

void rasbb_flash_bus_release(void)
{
    HAL_GPIO_WritePin(RASBB_SWFLASH_PORT, RASBB_SWFLASH_PIN, GPIO_PIN_RESET);
    cs_high();
}

/* ---- FPGA2 (DFPGA) register slave, CS2 = PC12 (SPI4_NCS2 label) ---------- */
static inline void cs2_low(void)  { HAL_GPIO_WritePin(SPI4_NCS2_GPIO_Port, SPI4_NCS2_Pin, GPIO_PIN_RESET); }
static inline void cs2_high(void) { HAL_GPIO_WritePin(SPI4_NCS2_GPIO_Port, SPI4_NCS2_Pin, GPIO_PIN_SET); }

uint8_t rasbb_fpga2_status(void)
{
    uint8_t tx[2] = { RASBB_OP_NOP, 0x00 };
    uint8_t rx[2] = { 0 };
    bool ok;
    cs2_low();
    ok = xfer(tx, rx, 2);
    cs2_high();
    return ok ? rx[1] : 0u;
}

bool rasbb_fpga2_write_reg(uint8_t addr, uint32_t value)
{
    uint8_t tx[6], rx[6];
    bool ok;
    tx[0] = RASBB_OP_WRITE_REG;
    tx[1] = addr;
    tx[2] = (uint8_t)(value >> 24);
    tx[3] = (uint8_t)(value >> 16);
    tx[4] = (uint8_t)(value >> 8);
    tx[5] = (uint8_t)(value);
    cs2_low();
    ok = xfer(tx, rx, sizeof(tx));
    cs2_high();
    return ok;
}

bool rasbb_fpga2_read_reg(uint8_t addr, uint32_t *value)
{
    uint8_t tx[6] = { RASBB_OP_READ_REG, addr, 0, 0, 0, 0 };
    uint8_t rx[6] = { 0 };
    bool ok;
    if (!value) return false;
    cs2_low();
    ok = xfer(tx, rx, sizeof(tx));
    cs2_high();
    if (ok)
        *value = ((uint32_t)rx[2] << 24) | ((uint32_t)rx[3] << 16) |
                 ((uint32_t)rx[4] << 8)  |  (uint32_t)rx[5];
    return ok;
}
