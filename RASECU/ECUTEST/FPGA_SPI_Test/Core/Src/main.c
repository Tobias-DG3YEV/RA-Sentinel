/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Main program body
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
/* Includes ------------------------------------------------------------------*/
#include "main.h"
#include "dcmi.h"
#include "dma.h"
#include "spi.h"
#include "usart.h"
#include "gpio.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include <stdio.h>
#include <string.h>
#include "platform_types.h"
#include "802_11.h"
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */
#define CR_POWER_THRES                  3
#define CR_POWER_WINDOW                 4
#define CR_SKIP_SAMPLE                  5
#define SR_MIN_PLATEAU                  6

#define DCMI_META_SIZE  256
#define DCMI_FRAMESIZE  (DCMI_META_SIZE + 64)

/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/

/* USER CODE BEGIN PV */
u8 frameBuffer[DCMI_FRAMESIZE] @ "SRAM1";

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
static void MPU_Config(void);
/* USER CODE BEGIN PFP */

static void printMAC(u8 *pMac)
{
  printf("%02X:%02X:%02X:%02X:%02X:%02X", pMac[0], pMac[1], pMac[2], pMac[3], pMac[4], pMac[5] );
}

/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */
/**
 * \brief Outputs a character on the CONSOLE.
 *
 * \param c  Character to output.
 *
 * \return The character that was output.
 */
extern /*WEAK*/ signed int putchar( signed int c )
{
	if(c > 0xc0) {
		c = '.';
	}
  HAL_UART_Transmit(&huart3, (uint8_t*)&c, 1, 1000);
	return c ;
}

volatile u8 frameReadyFlag = 0;

void HAL_DCMI_FrameEventCallback(DCMI_HandleTypeDef *hdcmi)
{
    frameReadyFlag = 1;  // Set flag to indicate a new frame is ready
}

/* USER CODE END 0 */

/**
  * @brief  The application entry point.
  * @retval int
  */
int main(void)
{

  /* USER CODE BEGIN 1 */

  /* USER CODE END 1 */

  /* MPU Configuration--------------------------------------------------------*/
  MPU_Config();

  /* MCU Configuration--------------------------------------------------------*/

  /* Reset of all peripherals, Initializes the Flash interface and the Systick. */
  HAL_Init();

  /* USER CODE BEGIN Init */

  /* USER CODE END Init */

  /* Configure the system clock */
  SystemClock_Config();

  /* USER CODE BEGIN SysInit */

  /* USER CODE END SysInit */

  /* Initialize all configured peripherals */
  MX_GPIO_Init();
  MX_DMA_Init();
  MX_DCMI_Init();
  MX_SPI1_Init();
  MX_USART3_UART_Init();
  /* USER CODE BEGIN 2 */
  u8 inData[5];
  u8 outData[5];
  u8 minPlateau = 100;
  u8 powerThres = 30;
  u8 powerWnd = 100;

  printf("Initialising OWIFI_RX chip.\n");

  outData[0] = CR_POWER_THRES << 1;
  outData[1] = 0;
  outData[2] = 0;
  outData[3] = 0;
  outData[4] = powerThres;
  HAL_SPI_TransmitReceive(&hspi1, outData, inData, 5, 1000);

  HAL_Delay(20);

  outData[0] = CR_POWER_WINDOW << 1;
  outData[1] = 0x00;
  outData[2] = 0x00;
  outData[3] = 0x00;
  outData[4] = powerWnd;
  HAL_SPI_TransmitReceive(&hspi1, outData, inData, 5, 1000);

  HAL_Delay(20);


  outData[0] = SR_MIN_PLATEAU << 1;
  outData[1] = 0x00;
  outData[2] = 0x00;
  outData[3] = 0x00;
  outData[4] = minPlateau;
  HAL_SPI_TransmitReceive(&hspi1, outData, inData, 5, 1000);

  HAL_Delay(20);


  outData[0] = CR_POWER_THRES <<1 | 1;
  outData[1] = 0;
  outData[2] = 0;
  outData[3] = 0;
  outData[4] = 0;
  HAL_SPI_TransmitReceive(&hspi1, outData, inData, 5, 1000);
  printf("Reg 3: %X %X %X %X\n", inData[1], inData[2], inData[3], inData[4] );

  HAL_Delay(20);

  outData[0] = CR_POWER_WINDOW <<1 | 1;
  outData[1] = 0;
  outData[2] = 0;
  outData[3] = 0;
  outData[4] = 0;
  HAL_SPI_TransmitReceive(&hspi1, outData, inData, 5, 1000);
  printf("Reg 4: %X %X %X %X\n", inData[1], inData[2], inData[3], inData[4] );

  HAL_DCMI_StateTypeDef dcmi_lastState, dcmi_state;

  memset(frameBuffer, 0xDD, sizeof(frameBuffer));

  __enable_irq();

  if(HAL_DCMI_Start_DMA(&hdcmi, DCMI_MODE_SNAPSHOT, (uint32_t)frameBuffer, DCMI_FRAMESIZE/4) != HAL_OK) {
      printf("ERROR DCMI DMA START!\n");
  }
  u8 *pHdr;

  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  while (1)
  {
    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */

    if (frameReadyFlag == 1) {

      pHdr = &frameBuffer[259];

      DOT11_FHDR_FCTL1_T *pHdr1 = (DOT11_FHDR_FCTL1_T*) pHdr;
      pHdr += sizeof(DOT11_FHDR_FCTL1_T);
      DOT11_FHDR_FCTL0_T *pHdr0 = (DOT11_FHDR_FCTL0_T*) pHdr;
      pHdr += sizeof(DOT11_FHDR_FCTL1_T);

      printf("=============================================\n");
      printf("Timestamp: %ul\n", HAL_GetTick());
      printf("Protocol Version: %i\n", pHdr0->protoVersion);
      printf("Frame Type: %i\n", pHdr0->type);
      printf("Subtype: %i\n", pHdr0->subType);
      printf("To DS: %i\n", pHdr1->toDS);
      printf("From DS: %i\n", pHdr1->fromDS);
      printf("More Frag.: %i\n", pHdr1->moreFrag);
      printf("Retry: %i\n", pHdr1->retry);
      printf("Power Mgmt: %i\n", pHdr1->powerMng);
      printf("WEP: %i\n", pHdr1->WEP);
      printf("Order: %i\n", pHdr1->order);
      printf("Duration ID: %i\n", pHdr[0] + (pHdr[1]<<8));
      pHdr += 2;
      if(pHdr1->toDS) {
        printf("Destination MAC: ");
        printMAC(pHdr);
        printf("\n");
        pHdr += 6;
      }
      if(pHdr1->fromDS) {
        printf("Source MAC: ");
        printMAC(pHdr);
        printf("\n");
        pHdr += 6;
      }
      printf("---------------------------------------------\n");
      for(int i = 0; i < DCMI_META_SIZE; i++) {
        printf("%i,", (s8)frameBuffer[i]);
      }
      printf("\n\n");
      HAL_Delay(200);
      frameReadyFlag = 0;

    }
    // Error starting DCMI capture
    dcmi_state = HAL_DCMI_GetState(&hdcmi);
    if(dcmi_state != dcmi_lastState) {
      //printf("DCMI state: %i\n", dcmi_state);
      dcmi_lastState = dcmi_state;
    }
    if(dcmi_state == HAL_DCMI_STATE_ERROR || dcmi_state == HAL_DCMI_STATE_READY) {
      HAL_DCMI_Stop(&hdcmi);
      HAL_DCMI_Start_DMA(&hdcmi, DCMI_MODE_SNAPSHOT, (uint32_t)frameBuffer, DCMI_FRAMESIZE/4);
    }
  }
  /* USER CODE END 3 */
}

/**
  * @brief System Clock Configuration
  * @retval None
  */
void SystemClock_Config(void)
{
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

  /** Supply configuration update enable
  */
  HAL_PWREx_ConfigSupply(PWR_LDO_SUPPLY);

  /** Configure the main internal regulator output voltage
  */
  __HAL_PWR_VOLTAGESCALING_CONFIG(PWR_REGULATOR_VOLTAGE_SCALE1);

  while(!__HAL_PWR_GET_FLAG(PWR_FLAG_VOSRDY)) {}

  /** Initializes the RCC Oscillators according to the specified parameters
  * in the RCC_OscInitTypeDef structure.
  */
  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSE;
  RCC_OscInitStruct.HSEState = RCC_HSE_ON;
  RCC_OscInitStruct.PLL.PLLState = RCC_PLL_ON;
  RCC_OscInitStruct.PLL.PLLSource = RCC_PLLSOURCE_HSE;
  RCC_OscInitStruct.PLL.PLLM = 2;
  RCC_OscInitStruct.PLL.PLLN = 64;
  RCC_OscInitStruct.PLL.PLLP = 2;
  RCC_OscInitStruct.PLL.PLLQ = 8;
  RCC_OscInitStruct.PLL.PLLR = 4;
  RCC_OscInitStruct.PLL.PLLRGE = RCC_PLL1VCIRANGE_3;
  RCC_OscInitStruct.PLL.PLLVCOSEL = RCC_PLL1VCOWIDE;
  RCC_OscInitStruct.PLL.PLLFRACN = 0;
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK)
  {
    Error_Handler();
  }

  /** Initializes the CPU, AHB and APB buses clocks
  */
  RCC_ClkInitStruct.ClockType = RCC_CLOCKTYPE_HCLK|RCC_CLOCKTYPE_SYSCLK
                              |RCC_CLOCKTYPE_PCLK1|RCC_CLOCKTYPE_PCLK2
                              |RCC_CLOCKTYPE_D3PCLK1|RCC_CLOCKTYPE_D1PCLK1;
  RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_PLLCLK;
  RCC_ClkInitStruct.SYSCLKDivider = RCC_SYSCLK_DIV1;
  RCC_ClkInitStruct.AHBCLKDivider = RCC_HCLK_DIV2;
  RCC_ClkInitStruct.APB3CLKDivider = RCC_APB3_DIV2;
  RCC_ClkInitStruct.APB1CLKDivider = RCC_APB1_DIV2;
  RCC_ClkInitStruct.APB2CLKDivider = RCC_APB2_DIV2;
  RCC_ClkInitStruct.APB4CLKDivider = RCC_APB4_DIV2;

  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_2) != HAL_OK)
  {
    Error_Handler();
  }
}

/* USER CODE BEGIN 4 */

/* USER CODE END 4 */

 /* MPU Configuration */

void MPU_Config(void)
{
  MPU_Region_InitTypeDef MPU_InitStruct = {0};

  /* Disables the MPU */
  HAL_MPU_Disable();

  /** Initializes and configures the Region and the memory to be protected
  */
  MPU_InitStruct.Enable = MPU_REGION_ENABLE;
  MPU_InitStruct.Number = MPU_REGION_NUMBER0;
  MPU_InitStruct.BaseAddress = 0x0;
  MPU_InitStruct.Size = MPU_REGION_SIZE_4GB;
  MPU_InitStruct.SubRegionDisable = 0x87;
  MPU_InitStruct.TypeExtField = MPU_TEX_LEVEL0;
  MPU_InitStruct.AccessPermission = MPU_REGION_NO_ACCESS;
  MPU_InitStruct.DisableExec = MPU_INSTRUCTION_ACCESS_DISABLE;
  MPU_InitStruct.IsShareable = MPU_ACCESS_SHAREABLE;
  MPU_InitStruct.IsCacheable = MPU_ACCESS_NOT_CACHEABLE;
  MPU_InitStruct.IsBufferable = MPU_ACCESS_NOT_BUFFERABLE;

  HAL_MPU_ConfigRegion(&MPU_InitStruct);
  /* Enables the MPU */
  HAL_MPU_Enable(MPU_PRIVILEGED_DEFAULT);

}

/**
  * @brief  This function is executed in case of error occurrence.
  * @retval None
  */
void Error_Handler(void)
{
  /* USER CODE BEGIN Error_Handler_Debug */
  /* User can add his own implementation to report the HAL error return state */
  __disable_irq();
  while (1)
  {
  }
  /* USER CODE END Error_Handler_Debug */
}

#ifdef  USE_FULL_ASSERT
/**
  * @brief  Reports the name of the source file and the source line number
  *         where the assert_param error has occurred.
  * @param  file: pointer to the source file name
  * @param  line: assert_param error line source number
  * @retval None
  */
void assert_failed(uint8_t *file, uint32_t line)
{
  /* USER CODE BEGIN 6 */
  /* User can add his own implementation to report the file name and line number,
     ex: printf("Wrong parameters value: file %s on line %d\r\n", file, line) */
  /* USER CODE END 6 */
}
#endif /* USE_FULL_ASSERT */
