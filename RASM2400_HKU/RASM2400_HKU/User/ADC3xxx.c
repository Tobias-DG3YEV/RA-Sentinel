/*CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
 *
 *  Elektronik-idee Weber GmbH (c)
 *
 *  File: ADC34xx.c
 *
 *  Version 1.0
 *
 *  Project: LoPo4
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
#include "ADC3xxx.h"
/****************************************************************************
*                              DEFINES
*****************************************************************************/

#define REG_DITHER        0x001
#define REG_DITHER_DIS_CHA (3<<4) /* 11 = Dither is disabled for channel A. In this mode, SNR typically improves by 0.2 dB at 70 MHz. */
#define REG_DITHER_DIS_CHB (3<<2) /* 11 = Dither is disabled for channel B. In this mode, SNR typically improves by 0.2 dB at 70 MHz. */
#define REG_BITSELECT     0x003
#define REG_BITSELECT_ODD   (0<<0) /* Bits 0, 1, and 2 appear on wire 0; bits 7, 8, and 9 appear on wire 1 */
#define REG_BITSELECT_EVEN  (1<<0) /* Bits 0, 2, and 4 appear on wire 0; bits 1, 3, and 5 appear on wire 1 */
#define REG_OUTPUTMODE    0x005
#define REG_OUTPUTMODE_2W 0 /* Output data are transmitted on two wires (Dx0P, Dx0M and Dx1P, Dx1M) */
#define REG_OUTPUTMODE_1W 1 /* Output data are transmitted on one wire (Dx0P, Dx0M). In this mode, the recommended fS is less than 80 MSPS */
#define REG_RESET         0x006
#define REG_RESET_DORESET   (1<<0) /* perform a reset */
#define REG_RESET_TEST_EN   (1<<1) /* enables test pattern selection for the digital outputs*/
#define REG_OVR           0x007
#define REG_FORMAT    0x009
#define REG_FORMAT_TWOSCOMP   (0<<0) /*  twos complement */
#define REG_FORMAT_OFFSETBIN  (1<<0) /* Offset binary */
#define REG_FORMAT_TESTFREE   (0<<1) /* Test patterns of both channels are free running */
#define REG_FORMAT_TESTALIGN  (1<<1) /* Test patterns of both channels are aligned */
#define REG_TESTPATTERN_CHA  0x00A
#define REG_TESTPATTERN_CHB  0x00B
#define REG_TESTPATTERN_NORMALOP  0
#define REG_TESTPATTERN_ALLZERO   1
#define REG_TESTPATTERN_ALLONE    2
#define REG_TESTPATTERN_TOGGLE    3
#define REG_TESTPATTERN_RAMP      4
#define REG_TESTPATTERN_CUSTOM    5
#define REG_TESTPATTERN_AAA       6 /* Deskew pattern: data are AAAh */
#define REG_TESTPATTERN_RANDOM    8
#define REG_TESTPATTERN_SINEWAVE  9 /* 8-point sine-wave: 0, 599, 2048, 3496, 4095, 3496, 2048, and 599 */
#define REG_CUSTPATTERN_11TO4  0x00E
#define REG_CUSTPATTERN_3TO0   0x00F
#define REG_LOWSPEED    0x013
#define REG_LOWSPEED_MAX125         (0)
#define REG_LOWSPEED_MAX25_1WIRE    (2)
#define REG_LOWSPEED_MAX25_2WIRE    (3)

#define REG_OUTPUTSWING   0x025
#define REG_CLKDIV        0x027
#define REG_CLKDIV_BY1    (0<<6)
#define REG_CLKDIV_BY2    (2<<6)
#define REG_CLKDIV_BY4    (3<<6)

#define REG_SPECIALMODE_A 0x439
#define REG_SPECIALMODE_A_EN (1<<3)
#define REG_SPECIALMODE_B 0x539
#define REG_SPECIALMODE_B_EN (1<<3)


/****************************************************************************
*                              MACROS
*****************************************************************************/
/****************************************************************************
*                              LOCAL VARIABLES
****************************************************************ee>*************/
/****************************************************************************
*                              GLOBAL VARIABLES
*****************************************************************************/
/****************************************************************************
*                              LOCAL FUNCTIONS
*****************************************************************************/


static u8 _readReg(u16 addr)
{
	/***** DEFINITION *******/
  u8 retval;
  u8 txData[3];
  u8 rxData[3];
	/**** PARAMETER CHECK ***/
	/**** INITIALIZATION ****/
  addr &= 0x3FFF; /* protect the upper two bits */
  addr |= 0xC000; /* bit 14 and 15 must be always 1 */
  txData[0] = addr >> 8;
  txData[1] = addr & 0xFF;
  txData[2] = 0;
  rxData[0] = 0;
  rxData[1] = 0;
  rxData[2] = 0;
	/**** PROGRAM CODE ******/
  SPI_SET_ADC_ACTIVE();
  HAL_SPI_TransmitReceive(&hspi1, txData, rxData, sizeof(txData), 1000);
  SPI_SET_ADC_INACTIVE();

  return rxData[2];
}

static u8 _writeReg(u16 addr, u8 data)
{
	/***** DEFINITION *******/
  u8 retval;
  u8 txData[3];
	/**** PARAMETER CHECK ***/
	/**** INITIALIZATION ****/
  addr &= 0x3FFF; /* protect the upper two bits */
  addr |= 0x4000; /* bit 14 must be always 1 */
  txData[0] = addr >> 8;
  txData[1] = addr & 0xFF;
  txData[2] = data;
	/**** PROGRAM CODE ******/
  SPI_SET_ADC_ACTIVE();
  HAL_SPI_Transmit(&hspi1, txData, sizeof(txData), 1000);
  SPI_SET_ADC_INACTIVE();

  /* read back */
  DELAYMS(10);

  return 0;
}


/****************************************************************************
*                             GLOBAL FUNCTIONS
*****************************************************************************/

/****************************************************************************
* FUNC:		ADC3221_init
* PARAM:	void
* RET:		int
* DESC:		returns <0 if failed to init the chip
*****************************************************************************/
int ADC3221_init(void)
{
	/***** DEFINITION *******/
	/**** PARAMETER CHECK ***/
	/**** INITIALIZATION ****/
	/**** PROGRAM CODE ******/
  
  u16 testpat = 0x0AA;

  _writeReg(REG_RESET, REG_RESET_DORESET);
  DELAYMS(50);
  _writeReg(REG_SPECIALMODE_A, REG_SPECIALMODE_A_EN);
  _writeReg(REG_SPECIALMODE_B, REG_SPECIALMODE_B_EN);
  _writeReg(REG_CLKDIV, REG_CLKDIV_BY1);
  _writeReg(REG_BITSELECT, REG_BITSELECT_ODD);
  //_writeReg(REG_DITHER, REG_DITHER_DIS_CHA|REG_DITHER_DIS_CHB); 
  _writeReg(REG_OUTPUTMODE, REG_OUTPUTMODE_2W);
#if 0
  _writeReg(REG_RESET, REG_RESET_TEST_EN); /* 6 <- 0x02 */
  _writeReg(REG_TESTPATTERN_CHB, REG_TESTPATTERN_CUSTOM<<4); /* in channel B the upper 4 bits are for the test pattern */
  _writeReg(REG_TESTPATTERN_CHA, REG_TESTPATTERN_CUSTOM);
  _writeReg(REG_CUSTPATTERN_11TO4, testpat >> 4);
  _writeReg(REG_CUSTPATTERN_3TO0,  (testpat & 0xF) <<4);
  //_writeReg(REG_TESTPATTERN_CHA, REG_TESTPATTERN_ALLZERO);
  _writeReg(REG_TESTPATTERN_CHA, REG_TESTPATTERN_TOGGLE);
  _writeReg(REG_TESTPATTERN_CHB,  REG_TESTPATTERN_RAMP << 4); /* in channel B the upper 4 bits are for the test pattern */
  _writeReg(REG_FORMAT, REG_FORMAT_TESTALIGN); // |REG_FORMAT_OFFSETBIN); /* 9 <- 3  */
#endif
  return 0;
}

/*** EOF ***/
