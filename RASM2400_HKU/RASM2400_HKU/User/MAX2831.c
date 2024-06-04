/*CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
 *
 *  Elektronik-idee Weber GmbH (c)
 *
 *  File: MAX2831.c
 *
 *  Version 1.0
 *
 *  Project: RASentinel
 *
 *  Description:
 *
 *  tw@elektronik-idee.com
 *
 *  Copyright (C) 2021 - 2022 Elektronik-Idee
 *  All rights reserved, alle Rechte vorbehalten.
 *
 CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC*/
/****************************************************************************
*                              ERROR LOGGING LEVEL
*****************************************************************************/
#define LOG_LEVEL_RELEASE   LOG_LEVEL_MAJOR
#define LOG_LEVEL_DEBUG     LOG_LEVEL_INFO
/****************************************************************************
*                              INCLUDES
*****************************************************************************/
#include "platform_types.h"
#include "main.h"
#include "config.h"
#include "spi.h"
#include "MAX2831.h"
/****************************************************************************
*                              DEFINES
*****************************************************************************/

#define REG_PLLMODE             0
#define PLLMODE_DEFAULT     0x1740
#define PLLMODE_FRACT       (1<<10) /* Fractional-N PLL Mode Enable.  */
#define PLLMODE_INTEG       (0<<10) /* Enable the integer-N PLL. */

#define REG_LOCKDET_OUT         1
#define LOCKDET_OUT_DEFAULT 0x119A
#define LOCKDET_OUT_CMOS    (1<<12)
#define LOCKDET_OUT_OPCOL   (0<<12)

#define REG_2                   2
#define REG_2_DEFAULT           0x1003

#define REG_DIVIDERA            3
#define DIVIDERA_DEFAULT        0x1A79 /* 2422M */

#define REG_DIVIDERB            4
#define DIVIDERB_DEFAULT        0x0666 /* 2422M */

#define REG_LD_SETUP            5
#define LD_SETUP_DEFAULT        0x00A4

#define REG_CALIBMODE           6
#define CALIBMODE_DEFAULT       0x0060

#define REG_FILTER              7
#define FILTER_DEFAULT          0x0022

#define REG_LEVEL               8
#define LEVEL_DEFAULT           0x3423
#define LEVEL_11B               0
#define LEVEL_11G               1
#define LEVEL_TURBO1            2
#define LEVEL_TURBO2            3

#define REG_TXGAIN              9
#define TXGAIN_DEFAULT          0x02B5

#define REG_PASETUP             10
#define PASETUP                 0x1DA4

#define REG_RXSETUP             11
#define RXSETUP_DEFAULT         0x0000
#define RXSETUP_LNAGAIN_HIGH    3         
#define RXSETUP_LNAGAIN_MEDIUM  2 /* -16dB */
#define RXSETUP_LNAGAIN_LOW     0 /* -33dB */
#define RXSETUP_VGAGAIN(x)      (x & 0x1F) /* a value between */

#define REG_TXVGASETUP          12
#define TXVGASETUP_DEFAULT      0x0140
#define TXVGASETUP_GAIN(x)      (x & 0x3F)

#define REG_13                  13
#define REG_13_DEFAULT          0x0E92

#define REG_CLKOUTPUT           14
#define CLKOUTPUT_DEFAULT       0x300 /* Ref. Out Enabled */
#define CLKOUTPUT_REFCLKDIV2    (1<<10) /* Reference Clock Output Divider Ratio. Set 1 to divide by 2 or set 0 to divide by 1 */
#define CLKOUTPUT_REFCLKEN      (1<<9)  /* Ref. Out Enable */

#define REG_IQOUTCMV            15 /* Receiver I/Q Output Common-Mode Voltage Adjustment */
#define IQOUTCMV                0x0145

/****************************************************************************
*                              MACROS
*****************************************************************************/
/****************************************************************************
*                              LOCAL VARIABLES
*****************************************************************************/
/****************************************************************************
*                              GLOBAL VARIABLES
*****************************************************************************/
/****************************************************************************
*                              LOCAL FUNCTIONS
*****************************************************************************/


static u32 _readReg(u8 addr)
{
	/***** DEFINITION *******/
  u32 retval;
  u8 txData[3];
  u8 rxData[3];
	/**** PARAMETER CHECK ***/
	/**** INITIALIZATION ****/
	/**** PROGRAM CODE ******/
  SPI_SET_ADC_ACTIVE();
  HAL_SPI_TransmitReceive(&hspi1, txData, rxData, sizeof(txData), 1000);
  SPI_SET_ADC_INACTIVE();

  return rxData[0];
}

/*

  

*/

static void _writeReg(u8 addr, u16 data)
{
	/***** DEFINITION *******/
  u8 txData[3]; /* must store 18 bits */
	/**** PARAMETER CHECK ***/
	/**** INITIALIZATION ****/
  /* MSB and lowest Byte will be send out first */
  txData[0] = 0x3 &  (data >> 12); /* get the upper 4 bits */
  txData[1] = 0xFF & (data >> 4); /* */
  txData[2] = (addr & 0x0F) | (data << 4);
  
	/**** PROGRAM CODE ******/
  SPI_SET_ADC_ACTIVE();
  HAL_SPI_Transmit(&hspi1, txData, sizeof(txData), 1000);
  SPI_SET_ADC_INACTIVE();

  /* read back */
  DELAYMS(10);
}


/****************************************************************************
*                             GLOBAL FUNCTIONS
*****************************************************************************/

/****************************************************************************
* FUNC:		MAX2831_init
* PARAM:	void
* RET:		int
* DESC:		returns <0 if failed to init the chip
*****************************************************************************/
int MAX2831_init(void)
{
	/***** DEFINITION *******/
	/**** PARAMETER CHECK ***/
	/**** INITIALIZATION ****/
	/**** PROGRAM CODE ******/

  _writeReg(REG_PLLMODE, PLLMODE_DEFAULT);
  _writeReg(REG_LOCKDET_OUT, LOCKDET_OUT_DEFAULT);
  _writeReg(REG_2, REG_2_DEFAULT);
  _writeReg(REG_DIVIDERA, DIVIDERA_DEFAULT);
  _writeReg(REG_DIVIDERB, DIVIDERB_DEFAULT);
  _writeReg(REG_LD_SETUP, LD_SETUP_DEFAULT);
  _writeReg(REG_CALIBMODE, CALIBMODE_DEFAULT);
  _writeReg(REG_FILTER, FILTER_DEFAULT);
  _writeReg(REG_LEVEL, LEVEL_DEFAULT);
  _writeReg(REG_TXGAIN, TXGAIN_DEFAULT);
  _writeReg(REG_PASETUP, PASETUP);
  _writeReg(REG_RXSETUP, RXSETUP_DEFAULT|RXSETUP_LNAGAIN_LOW|RXSETUP_VGAGAIN(8));
  _writeReg(REG_TXVGASETUP, TXVGASETUP_DEFAULT);
  _writeReg(REG_13, REG_13_DEFAULT);
  _writeReg(REG_CLKOUTPUT, CLKOUTPUT_DEFAULT);
  _writeReg(CLKOUTPUT_REFCLKDIV2, CLKOUTPUT_DEFAULT);
  
  
  return 0;
}

/*** EOF ***/
