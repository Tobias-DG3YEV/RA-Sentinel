/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.h
  * @brief          : Header for main.c file.
  *                   This file contains the common defines of the application.
  ******************************************************************************
  * @attention
  *
  * Copyright (c) 2024 STMicroelectronics.
  * All rights reserved.
  *
  * This software is licensed under terms that can be found in the LICENSE file
  * in the root directory of this software component.
  * If no LICENSE file comes with this software, it is provided AS-IS.
  *
  ******************************************************************************
  */
/* USER CODE END Header */

/* Define to prevent recursive inclusion -------------------------------------*/
#ifndef __MAIN_H
#define __MAIN_H

#ifdef __cplusplus
extern "C" {
#endif

/* Includes ------------------------------------------------------------------*/
#include "stm32h7xx_hal.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */

/* USER CODE END Includes */

/* Exported types ------------------------------------------------------------*/
/* USER CODE BEGIN ET */

/* USER CODE END ET */

/* Exported constants --------------------------------------------------------*/
/* USER CODE BEGIN EC */

/* USER CODE END EC */

/* Exported macro ------------------------------------------------------------*/
/* USER CODE BEGIN EM */

/* USER CODE END EM */

/* Exported functions prototypes ---------------------------------------------*/
void Error_Handler(void);

/* USER CODE BEGIN EFP */

/* USER CODE END EFP */

/* Private defines -----------------------------------------------------------*/
#define LORA_DIO1_Pin GPIO_PIN_2
#define LORA_DIO1_GPIO_Port GPIOE
#define LORA_DIO2_Pin GPIO_PIN_3
#define LORA_DIO2_GPIO_Port GPIOE
#define LORA_NRST_Pin GPIO_PIN_13
#define LORA_NRST_GPIO_Port GPIOC
#define LORA_BUSY_Pin GPIO_PIN_14
#define LORA_BUSY_GPIO_Port GPIOC
#define LORA_DIO3_Pin GPIO_PIN_15
#define LORA_DIO3_GPIO_Port GPIOC
#define uC_CONFIG_Pin GPIO_PIN_0
#define uC_CONFIG_GPIO_Port GPIOC
#define ETH_NRST_Pin GPIO_PIN_3
#define ETH_NRST_GPIO_Port GPIOA
#define CS_MUX2_Pin GPIO_PIN_0
#define CS_MUX2_GPIO_Port GPIOB
#define SPI3_NSS_Pin GPIO_PIN_7
#define SPI3_NSS_GPIO_Port GPIOE
#define LED_9_Pin GPIO_PIN_8
#define LED_9_GPIO_Port GPIOE
#define LED_8_Pin GPIO_PIN_9
#define LED_8_GPIO_Port GPIOE
#define LED_7_Pin GPIO_PIN_10
#define LED_7_GPIO_Port GPIOE
#define SPI4_NSS_Pin GPIO_PIN_11
#define SPI4_NSS_GPIO_Port GPIOE
#define uC_PE15_Pin GPIO_PIN_15
#define uC_PE15_GPIO_Port GPIOE
#define CS_MUX1_Pin GPIO_PIN_15
#define CS_MUX1_GPIO_Port GPIOB
#define PD10_DEBUG_Pin GPIO_PIN_10
#define PD10_DEBUG_GPIO_Port GPIOD
#define ALARM_Pin GPIO_PIN_11
#define ALARM_GPIO_Port GPIOD
#define PD12_DEBUG_Pin GPIO_PIN_12
#define PD12_DEBUG_GPIO_Port GPIOD
#define PD13_DEBUG_Pin GPIO_PIN_13
#define PD13_DEBUG_GPIO_Port GPIOD
#define PD14_DEBUG_Pin GPIO_PIN_14
#define PD14_DEBUG_GPIO_Port GPIOD
#define PD15_DEBUG_Pin GPIO_PIN_15
#define PD15_DEBUG_GPIO_Port GPIOD
#define EN_MUX2_Pin GPIO_PIN_9
#define EN_MUX2_GPIO_Port GPIOA
#define EN_MUX1_Pin GPIO_PIN_10
#define EN_MUX1_GPIO_Port GPIOA
#define SPI2_NSS_Pin GPIO_PIN_11
#define SPI2_NSS_GPIO_Port GPIOA
#define SPI4_NCS2_Pin GPIO_PIN_12
#define SPI4_NCS2_GPIO_Port GPIOC
#define PD0_DEBUG_Pin GPIO_PIN_0
#define PD0_DEBUG_GPIO_Port GPIOD
#define PD1_DEBUG_Pin GPIO_PIN_1
#define PD1_DEBUG_GPIO_Port GPIOD
#define PD2_DEBUG_Pin GPIO_PIN_2
#define PD2_DEBUG_GPIO_Port GPIOD
#define PD4_DEBUG_Pin GPIO_PIN_4
#define PD4_DEBUG_GPIO_Port GPIOD
#define PD7_DEBUG_Pin GPIO_PIN_7
#define PD7_DEBUG_GPIO_Port GPIOD
#define FPGA01_PROG_Pin GPIO_PIN_4
#define FPGA01_PROG_GPIO_Port GPIOB
#define FPGA02_PROG_Pin GPIO_PIN_5
#define FPGA02_PROG_GPIO_Port GPIOB

/* USER CODE BEGIN Private defines */

/* USER CODE END Private defines */

#ifdef __cplusplus
}
#endif

#endif /* __MAIN_H */
