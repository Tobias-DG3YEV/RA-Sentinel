/*
 * rasrf.c - host-side driver for the RF frontend's I2C register file.
 * See rasrf.h. Target: STM32H743VGT6 (IC12) on RASBB, I2C1 master.
 *
 * Deliberately BLOCKING. The longest transaction here is the 8-byte build
 * stamp: ~11 bytes on the wire at 100kHz is ~1ms, and everything else is one
 * or two bytes. Nothing on this bus justifies DMA, and staying blocking
 * sidesteps the H7 D-cache/DMA coherency trap that the SPI read-out path
 * documents at length in rasbb_fpga.c.
 *
 * I2C1 has no other user on this board (the AHT20 is on I2C3), so there is no
 * mutex here. If a second task ever talks to the frontend, guard whole
 * register transactions - not the individual HAL calls - or one caller's index
 * phase will be followed by another's data phase.
 */
#include "rasrf.h"
#include "main.h"
#include <string.h>

extern I2C_HandleTypeDef hi2c1;

/* Generous next to the ~1ms a worst-case transaction takes. It has to absorb
 * the frontend stretching SCL while its interrupt serves a byte, and it is
 * also how long a call blocks when no frontend is fitted at all. */
#define RASRF_TIMEOUT_MS 50u

bool rasrf_read_regs(uint8_t idx, uint8_t *buf, uint16_t n)
{
    return HAL_I2C_Mem_Read(&hi2c1, RASRF_I2C_ADDR, idx, I2C_MEMADD_SIZE_8BIT,
                            buf, n, RASRF_TIMEOUT_MS) == HAL_OK;
}

bool rasrf_write_regs(uint8_t idx, const uint8_t *buf, uint16_t n)
{
    return HAL_I2C_Mem_Write(&hi2c1, RASRF_I2C_ADDR, idx, I2C_MEMADD_SIZE_8BIT,
                             (uint8_t *)buf, n, RASRF_TIMEOUT_MS) == HAL_OK;
}

bool rasrf_read_reg(uint8_t idx, uint8_t *val)
{
    return rasrf_read_regs(idx, val, 1u);
}

bool rasrf_write_reg(uint8_t idx, uint8_t val)
{
    return rasrf_write_regs(idx, &val, 1u);
}

bool rasrf_identify(rasrf_ident_t *out)
{
    uint8_t id[4];

    memset(out, 0, sizeof(*out));

    if (!rasrf_read_regs(RASRF_REG_BOARD_MODEL, id, sizeof(id))) return false;

    out->model     = id[0];
    out->revision  = id[1];
    out->ver_major = id[2];
    out->ver_minor = id[3];

    /* A frontend that predates the build-stamp block answers this range with
     * zeros, which lands as an empty string - not an error. */
    if (!rasrf_read_regs(RASRF_REG_GIT_VER, (uint8_t *)out->build,
                         RASRF_GIT_VER_LEN))
    {
        return false;
    }
    out->build[RASRF_GIT_VER_LEN] = '\0';

    return true;
}

bool rasrf_status(uint8_t *st)
{
    return rasrf_read_reg(RASRF_REG_STATUS, st);
}

bool rasrf_set_freq_mhz(uint16_t mhz)
{
    uint8_t pair[2];

    if ((mhz < RASRF_FREQ_MHZ_MIN) || (mhz > RASRF_FREQ_MHZ_MAX)) return false;

    pair[0] = (uint8_t)(mhz & 0xFFu);        /* 0x11: staged            */
    pair[1] = (uint8_t)(mhz >> 8);           /* 0x12: commits the pair  */

    /* One transaction, low byte first: the frontend's pointer walks 0x11->0x12
     * and only the second byte reaches its tuner. Two separate transactions
     * would work identically, but this way the commit cannot be left undone by
     * a failure between them. */
    return rasrf_write_regs(RASRF_REG_FREQ_MHZ_L, pair, sizeof(pair));
}

bool rasrf_get_freq_mhz(uint16_t *mhz)
{
    uint8_t pair[2];

    if (!rasrf_read_regs(RASRF_REG_FREQ_MHZ_L, pair, sizeof(pair))) return false;

    *mhz = (uint16_t)(((uint16_t)pair[1] << 8) | pair[0]);

    return true;
}

bool rasrf_set_rx_gain(uint8_t code)
{
    return rasrf_write_reg(RASRF_REG_RX_GAIN, code);
}

bool rasrf_get_rx_gain(uint8_t *code)
{
    return rasrf_read_reg(RASRF_REG_RX_GAIN, code);
}

bool rasrf_set_test_mode(uint8_t mask)
{
    return rasrf_write_reg(RASRF_REG_TEST_MODE, mask);
}

bool rasrf_get_test_mode(uint8_t *mask)
{
    return rasrf_read_reg(RASRF_REG_TEST_MODE, mask);
}

bool rasrf_get_rssi(uint16_t *raw)
{
    uint8_t pair[2];

    /* Must start at the low byte: reading 0x06 is what freezes the pair at the
     * frontend, so that a burst cannot straddle one of its 1Hz resamples and
     * return two halves of different conversions. */
    if (!rasrf_read_regs(RASRF_REG_RSSI_L, pair, sizeof(pair))) return false;

    *raw = (uint16_t)(((uint16_t)pair[1] << 8) | pair[0]);

    return true;
}
