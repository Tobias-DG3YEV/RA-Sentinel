/*
 * iqcap_nv_h7.c - non-volatile store for iqcap_cfg on the STM32H743VG:
 * flash bank 2, sector 3 (0x08160000, 128 KB), i.e. the last sector of the
 * 1 MB part. The firmware image lives in bank 1 (linker FLASH region, 512 KB),
 * so erasing this sector never touches running code. Written as 32-byte
 * flash words; the D-cache is invalidated on the sector before reading.
 */
#include "iqcap_cfg.h"
#include "stm32h7xx_hal.h"
#include <string.h>

#define NV_ADDR   0x08160000u
#define NV_BANK   FLASH_BANK_2
#define NV_SECTOR FLASH_SECTOR_3
#define NV_WORD   32u                       /* H7 flash word = 256 bit */

bool iqcap_nv_h7_load(void *buf, size_t n)
{
    SCB_InvalidateDCache_by_Addr((uint32_t *)NV_ADDR, (int32_t)((n + 31u) & ~31u));
    memcpy(buf, (const void *)NV_ADDR, n);
    return true;
}

bool iqcap_nv_h7_save(const void *buf, size_t n)
{
    static uint8_t chunk[NV_WORD] __attribute__((aligned(32)));
    FLASH_EraseInitTypeDef er;
    uint32_t sector_error = 0;
    HAL_StatusTypeDef st;
    size_t off = 0;

    if (HAL_FLASH_Unlock() != HAL_OK) return false;
    er.TypeErase    = FLASH_TYPEERASE_SECTORS;
    er.Banks        = NV_BANK;
    er.Sector       = NV_SECTOR;
    er.NbSectors    = 1;
    er.VoltageRange = FLASH_VOLTAGE_RANGE_3;
    st = HAL_FLASHEx_Erase(&er, &sector_error);
    while (st == HAL_OK && off < n) {
        size_t m = (n - off < NV_WORD) ? (n - off) : NV_WORD;
        memset(chunk, 0xFF, NV_WORD);
        memcpy(chunk, (const uint8_t *)buf + off, m);
        st = HAL_FLASH_Program(FLASH_TYPEPROGRAM_FLASHWORD, NV_ADDR + off, (uint32_t)chunk);
        off += NV_WORD;
    }
    HAL_FLASH_Lock();
    SCB_InvalidateDCache_by_Addr((uint32_t *)NV_ADDR, (int32_t)((n + 31u) & ~31u));
    return st == HAL_OK && memcmp((const void *)NV_ADDR, buf, n) == 0;
}
