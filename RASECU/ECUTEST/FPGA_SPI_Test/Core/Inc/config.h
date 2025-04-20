/*HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
 *
 *  Elektronik-idee Weber GmbH (c);
 *
 *  File: config.h
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
 HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH*/
#ifndef _config_H_
#define _config_H_
/****************************************************************************
*                              INCLUDES
*****************************************************************************/
#include "platform_types.h"
#include "stm32c0xx_hal.h"
/****************************************************************************
*                              GLOBAL DEFINES
*****************************************************************************/

/****************************************************************************
*                              MACROS
*****************************************************************************/
#define SET_PIN_ON(x) HAL_GPIO_WritePin(x##_GPIO_Port, x##_Pin, GPIO_PIN_SET)
#define SET_PIN_OFF(x) HAL_GPIO_WritePin(x##_GPIO_Port, x##_Pin, GPIO_PIN_RESET)

#define SPI_SET_ADC_ACTIVE() SET_PIN_OFF(ADC_NCS)
#define SPI_SET_ADC_INACTIVE() SET_PIN_ON(ADC_NCS)

#define LVLSH_ENA()   SET_PIN_OFF(LVL_SH_EN)
#define LVLSH_DIS()   SET_PIN_ON(LVL_SH_EN)

#define DELAYMS(x) HAL_Delay(x)

#define LED_ON()   SET_PIN_OFF(LED_PIN)
#define LED_OFF()   SET_PIN_ON(LED_PIN)

/****************************************************************************
*                              GLOBAL VARIABLES
*****************************************************************************/

#endif //_config_H_
/*** EOF ***/
