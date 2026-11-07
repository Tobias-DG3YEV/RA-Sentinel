/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Main program body
  ******************************************************************************
  * @attention
  *
  * Copyright (c) 2025 STMicroelectronics.
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
#include "cmsis_os.h"
#include "lwip.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include <stdio.h>
#include <string.h>
#include "rasbb_fpga.h"
#include "logw_seq.h"
#include "iqcap_cfg.h"
#include "httpserver_netconn.h"
#include "DPFPGA.h"
#include "rasrf.h"
#include "console.h"
#include "menu.h"
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */

/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/
ADC_HandleTypeDef hadc1;

DAC_HandleTypeDef hdac1;

DCMI_HandleTypeDef hdcmi;
DMA_HandleTypeDef hdma_dcmi;

I2C_HandleTypeDef hi2c1;
I2C_HandleTypeDef hi2c3;

SPI_HandleTypeDef hspi2;
SPI_HandleTypeDef hspi3;
SPI_HandleTypeDef hspi4;

UART_HandleTypeDef huart3;

/* Definitions for defaultTask */
osThreadId_t defaultTaskHandle;
const osThreadAttr_t defaultTask_attributes = {
  .name = "defaultTask",
  .stack_size = 256 * 4,
  .priority = (osPriority_t) osPriorityNormal,
};
/* USER CODE BEGIN PV */
/* OWIFI_RX phase-2 bring-up telemetry. Deliberately a plain global with a
   magic word at the front: it can be located in the .map and read straight
   out over SWD, so the read-out path can be proven without any UART wiring. */
typedef struct {
    uint32_t magic;          /* 0x4F574946 = "OWIF" */
    uint32_t polls;
    uint32_t frames;
    uint32_t read_errors;
    uint32_t spi_errors;
    uint32_t last_status;
    uint32_t last_seq;
    uint16_t last_len;
    uint16_t last_flags;
    uint32_t last_timestamp;
    uint8_t  first16[16];
    /* appended at the END so the offsets above stay stable across builds */
    uint32_t frames_bad;     /* queued despite a failed FCS (KEEP_BAD) */
    uint32_t last_bad_len;
    uint8_t  bad_first16[16];
} owifi_telemetry_t;

volatile owifi_telemetry_t g_owifi_tel = { 0x4F574946u, 0,0,0,0,0,0,0,0,0,{0},0,0,{0} };

/* The frame staging buffer is a static global, NOT a task local: at ~2KB it
   would dwarf any sane task stack. */
static rasbb_frame_t g_owifi_frame;

/* Non-zero once osThreadNew has accepted the read-out task. If this stays 0
   the FreeRTOS heap ran out; if it is 1 but g_owifi_tel.polls never moves,
   the task was created but is not being scheduled. */
volatile uint32_t g_owifi_task_created = 0;

/* Bring-up instrumentation: the read-out task stopped after ~250 polls with
   interrupts masked in thread mode, which is the signature of either
   Error_Handler() or a configASSERT - both are __disable_irq(); for(;;).
   These markers say which, and how far StartDefaultTask got. */
volatile uint32_t g_owifi_phase = 0;          /* 1 = entering MX_LWIP_Init, 2 = returned */
volatile uint32_t g_error_handler_hit = 0;
volatile uint32_t g_free_heap = 0;

/* ---- power-threshold sweep -----------------------------------------------
   Write g_cmd_thresh over SWD; the task notices the change, pushes it into
   the FPGA's CR_POWER_THRES, reads it back for confirmation, and restarts the
   measurement window.

   The window is counted in POLLS, not milliseconds: the task polls at a fixed
   500/s, and every SWD connect halts the core, so wall-clock timing would be
   corrupted by the act of reading it. frames/(polls/500) is immune to that. */
volatile uint32_t g_cmd_thresh      = 0;   /* 0 = leave the FPGA default alone */
volatile uint32_t g_applied_thresh  = 0;
volatile uint32_t g_readback_thresh = 0xFFFFFFFFu;
volatile uint32_t g_meas_polls      = 0;
volatile uint32_t g_meas_frames     = 0;
volatile uint32_t g_meas_bad        = 0;

/* Same pattern for the other two detection knobs.
   window_size  (CR_POWER_WINDOW, default 80): consecutive below-threshold
                samples power_trigger waits for before releasing the trigger.
   min_plateau  (CR_MIN_PLATEAU, default 100): required short-preamble plateau
                length; sync_short uses it as (i_min_plateau >> 2). */
volatile uint32_t g_cmd_window       = 0;
volatile uint32_t g_applied_window   = 0;
volatile uint32_t g_readback_window  = 0xFFFFFFFFu;
volatile uint32_t g_cmd_plateau      = 0;
volatile uint32_t g_applied_plateau  = 0;
volatile uint32_t g_readback_plateau = 0xFFFFFFFFu;

/* The link sequencer (logw_seq.c, ported from LOTAG/LOGW/Firmware/ECU):
   brings front end, FPGA and LVDS training up in the right order and
   re-trains after a bitstream reload. Shares I2C1/SPI4 with the console and
   the read-out task through logw_bus_lock(). */
static osThreadId_t logwSeqTaskHandle;
const osThreadAttr_t logwSeqTask_attributes = {
  .name = "logwSeq",
  .stack_size = 512 * 4,
  .priority = (osPriority_t) osPriorityNormal,
};

static osThreadId_t owifiRxTaskHandle;
const osThreadAttr_t owifiRxTask_attributes = {
  .name = "owifiRx",
  .stack_size = 512 * 4,
  .priority = (osPriority_t) osPriorityNormal,
};
void StartOwifiRxTask(void *argument);

/* The frontend console (console.c). Its own task rather than a call from
   StartDefaultTask, for the same two reasons owifiRx got one: the attributes
   live in USER CODE, so a CubeMX regeneration cannot resize the stack out from
   under it, and 2KB is what printf plus an I2C transaction wants - defaultTask
   is given 1KB by the generated code and cannot be widened here. */
static osThreadId_t consoleTaskHandle;
const osThreadAttr_t consoleTask_attributes = {
  .name = "console",
  .stack_size = 512 * 4,
  .priority = (osPriority_t) osPriorityNormal,
};
void StartConsoleTask(void *argument);
/* USER CODE END PV */

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
static void MPU_Config(void);
static void MX_GPIO_Init(void);
static void MX_DMA_Init(void);
static void MX_ADC1_Init(void);
static void MX_DAC1_Init(void);
static void MX_DCMI_Init(void);
static void MX_I2C1_Init(void);
static void MX_I2C3_Init(void);
static void MX_SPI2_Init(void);
static void MX_SPI3_Init(void);
static void MX_SPI4_Init(void);
static void MX_USART3_UART_Init(void);
void StartDefaultTask(void *argument);

/* USER CODE BEGIN PFP */

/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */
int __io_putchar(int ch)
{
    HAL_UART_Transmit(&huart3, (uint8_t*)&ch, 1, HAL_MAX_DELAY);
    return ch;
}
int _write(int file, char *ptr, int len)
{
    HAL_UART_Transmit(&huart3, (uint8_t*)ptr, len, HAL_MAX_DELAY);
    return len;
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

  /* Enable D-Cache---------------------------------------------------------*/
  SCB_EnableDCache();

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
  MX_ADC1_Init();
  MX_DAC1_Init();
  MX_DCMI_Init();
  MX_I2C1_Init();
  MX_I2C3_Init();
  MX_SPI2_Init();
  MX_SPI3_Init();
  MX_SPI4_Init();
  MX_USART3_UART_Init();
  /* USER CODE BEGIN 2 */
  /* First, because it makes stdout unbuffered and setvbuf has to precede any
     stdio traffic on the stream - including the line below. It also arms UART
     reception, which is harmless this early: characters simply queue up. */
  console_init();
  menu_init();      /* J8 buttons for the on-screen menu (after MX_GPIO_Init) */

  printf("Firmware starts\n");
  fflush(stdout);

  /* The FPGA read-out now runs as its own FreeRTOS task (StartOwifiRxTask),
     created below in RTOS_THREADS. GPIO/SPI setup stays here, before the
     scheduler, so the chip select and the mux are in their safe state from
     the first instant rather than whenever the task happens to be scheduled. */
  rasbb_fpga_init();
  /* IQ snapshot transport settings (JOB-06): load from flash bank 2 or take
     the SPEC defaults; applied to each FPGA when it is seen alive (see the
     read-out task). */
  {
    static const iqcap_port_t port = {
      rasbb_fpga_read_reg, rasbb_fpga_write_reg,
      rasbb_fpga2_read_reg, rasbb_fpga2_write_reg,
      iqcap_nv_h7_load, iqcap_nv_h7_save
    };
    iqcap_cfg_init(&port);
  }
  /* USER CODE END 2 */

  /* Init scheduler */
  osKernelInitialize();

  /* USER CODE BEGIN RTOS_MUTEX */
  logw_seq_init();   /* the I2C1/SPI4 bus guard shared by sequencer, console, read-out */
  /* add mutexes, ... */
  /* USER CODE END RTOS_MUTEX */

  /* USER CODE BEGIN RTOS_SEMAPHORES */
  /* add semaphores, ... */
  /* USER CODE END RTOS_SEMAPHORES */

  /* USER CODE BEGIN RTOS_TIMERS */
  /* start timers, add new ones, ... */
  /* USER CODE END RTOS_TIMERS */

  /* USER CODE BEGIN RTOS_QUEUES */
  /* add queues, ... */
  /* USER CODE END RTOS_QUEUES */

  /* Create the thread(s) */
  /* creation of defaultTask */
  defaultTaskHandle = osThreadNew(StartDefaultTask, NULL, &defaultTask_attributes);

  /* USER CODE BEGIN RTOS_THREADS */
  logwSeqTaskHandle = osThreadNew(StartLogwSeqTask, NULL, &logwSeqTask_attributes);
  owifiRxTaskHandle = osThreadNew(StartOwifiRxTask, NULL, &owifiRxTask_attributes);
  g_owifi_task_created = (owifiRxTaskHandle != NULL) ? 1u : 0u;
  consoleTaskHandle = osThreadNew(StartConsoleTask, NULL, &consoleTask_attributes);
  /* add threads, ... */
  /* USER CODE END RTOS_THREADS */

  /* USER CODE BEGIN RTOS_EVENTS */
  /* add events, ... */
  /* USER CODE END RTOS_EVENTS */

  /* Start scheduler */
  osKernelStart();

  /* We should never get here as control is now taken by the scheduler */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  while (1)
  {
    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */
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
  RCC_OscInitStruct.PLL.PLLR = 8;
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

/**
  * @brief ADC1 Initialization Function
  * @param None
  * @retval None
  */
static void MX_ADC1_Init(void)
{

  /* USER CODE BEGIN ADC1_Init 0 */

  /* USER CODE END ADC1_Init 0 */

  ADC_MultiModeTypeDef multimode = {0};
  ADC_ChannelConfTypeDef sConfig = {0};

  /* USER CODE BEGIN ADC1_Init 1 */

  /* USER CODE END ADC1_Init 1 */

  /** Common config
  */
  hadc1.Instance = ADC1;
  hadc1.Init.ClockPrescaler = ADC_CLOCK_ASYNC_DIV1;
  hadc1.Init.Resolution = ADC_RESOLUTION_16B;
  hadc1.Init.ScanConvMode = ADC_SCAN_DISABLE;
  hadc1.Init.EOCSelection = ADC_EOC_SINGLE_CONV;
  hadc1.Init.LowPowerAutoWait = DISABLE;
  hadc1.Init.ContinuousConvMode = DISABLE;
  hadc1.Init.NbrOfConversion = 1;
  hadc1.Init.DiscontinuousConvMode = DISABLE;
  hadc1.Init.ExternalTrigConv = ADC_SOFTWARE_START;
  hadc1.Init.ExternalTrigConvEdge = ADC_EXTERNALTRIGCONVEDGE_NONE;
  hadc1.Init.ConversionDataManagement = ADC_CONVERSIONDATA_DR;
  hadc1.Init.Overrun = ADC_OVR_DATA_PRESERVED;
  hadc1.Init.LeftBitShift = ADC_LEFTBITSHIFT_NONE;
  hadc1.Init.OversamplingMode = DISABLE;
  hadc1.Init.Oversampling.Ratio = 1;
  if (HAL_ADC_Init(&hadc1) != HAL_OK)
  {
    Error_Handler();
  }

  /** Configure the ADC multi-mode
  */
  multimode.Mode = ADC_MODE_INDEPENDENT;
  if (HAL_ADCEx_MultiModeConfigChannel(&hadc1, &multimode) != HAL_OK)
  {
    Error_Handler();
  }

  /** Configure Regular Channel
  */
  sConfig.Channel = ADC_CHANNEL_5;
  sConfig.Rank = ADC_REGULAR_RANK_1;
  sConfig.SamplingTime = ADC_SAMPLETIME_1CYCLE_5;
  sConfig.SingleDiff = ADC_SINGLE_ENDED;
  sConfig.OffsetNumber = ADC_OFFSET_NONE;
  sConfig.Offset = 0;
  sConfig.OffsetSignedSaturation = DISABLE;
  if (HAL_ADC_ConfigChannel(&hadc1, &sConfig) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN ADC1_Init 2 */

  /* USER CODE END ADC1_Init 2 */

}

/**
  * @brief DAC1 Initialization Function
  * @param None
  * @retval None
  */
static void MX_DAC1_Init(void)
{

  /* USER CODE BEGIN DAC1_Init 0 */

  /* USER CODE END DAC1_Init 0 */

  DAC_ChannelConfTypeDef sConfig = {0};

  /* USER CODE BEGIN DAC1_Init 1 */

  /* USER CODE END DAC1_Init 1 */

  /** DAC Initialization
  */
  hdac1.Instance = DAC1;
  if (HAL_DAC_Init(&hdac1) != HAL_OK)
  {
    Error_Handler();
  }

  /** DAC channel OUT2 config
  */
  sConfig.DAC_SampleAndHold = DAC_SAMPLEANDHOLD_DISABLE;
  sConfig.DAC_Trigger = DAC_TRIGGER_NONE;
  sConfig.DAC_OutputBuffer = DAC_OUTPUTBUFFER_ENABLE;
  sConfig.DAC_ConnectOnChipPeripheral = DAC_CHIPCONNECT_DISABLE;
  sConfig.DAC_UserTrimming = DAC_TRIMMING_FACTORY;
  if (HAL_DAC_ConfigChannel(&hdac1, &sConfig, DAC_CHANNEL_2) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN DAC1_Init 2 */

  /* USER CODE END DAC1_Init 2 */

}

/**
  * @brief DCMI Initialization Function
  * @param None
  * @retval None
  */
static void MX_DCMI_Init(void)
{

  /* USER CODE BEGIN DCMI_Init 0 */

  /* USER CODE END DCMI_Init 0 */

  /* USER CODE BEGIN DCMI_Init 1 */

  /* USER CODE END DCMI_Init 1 */
  hdcmi.Instance = DCMI;
  hdcmi.Init.SynchroMode = DCMI_SYNCHRO_HARDWARE;
  hdcmi.Init.PCKPolarity = DCMI_PCKPOLARITY_FALLING;
  hdcmi.Init.VSPolarity = DCMI_VSPOLARITY_HIGH;
  hdcmi.Init.HSPolarity = DCMI_HSPOLARITY_HIGH;
  hdcmi.Init.CaptureRate = DCMI_CR_ALL_FRAME;
  hdcmi.Init.ExtendedDataMode = DCMI_EXTEND_DATA_8B;
  hdcmi.Init.JPEGMode = DCMI_JPEG_DISABLE;
  hdcmi.Init.ByteSelectMode = DCMI_BSM_ALL;
  hdcmi.Init.ByteSelectStart = DCMI_OEBS_ODD;
  hdcmi.Init.LineSelectMode = DCMI_LSM_ALL;
  hdcmi.Init.LineSelectStart = DCMI_OELS_ODD;
  if (HAL_DCMI_Init(&hdcmi) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN DCMI_Init 2 */

  /* USER CODE END DCMI_Init 2 */

}

/**
  * @brief I2C1 Initialization Function
  * @param None
  * @retval None
  */
static void MX_I2C1_Init(void)
{

  /* USER CODE BEGIN I2C1_Init 0 */

  /* USER CODE END I2C1_Init 0 */

  /* USER CODE BEGIN I2C1_Init 1 */

  /* USER CODE END I2C1_Init 1 */
  hi2c1.Instance = I2C1;
  hi2c1.Init.Timing = 0x10C0ECFF;
  hi2c1.Init.OwnAddress1 = 0;
  hi2c1.Init.AddressingMode = I2C_ADDRESSINGMODE_7BIT;
  hi2c1.Init.DualAddressMode = I2C_DUALADDRESS_DISABLE;
  hi2c1.Init.OwnAddress2 = 0;
  hi2c1.Init.OwnAddress2Masks = I2C_OA2_NOMASK;
  hi2c1.Init.GeneralCallMode = I2C_GENERALCALL_DISABLE;
  hi2c1.Init.NoStretchMode = I2C_NOSTRETCH_DISABLE;
  if (HAL_I2C_Init(&hi2c1) != HAL_OK)
  {
    Error_Handler();
  }

  /** Configure Analogue filter
  */
  if (HAL_I2CEx_ConfigAnalogFilter(&hi2c1, I2C_ANALOGFILTER_ENABLE) != HAL_OK)
  {
    Error_Handler();
  }

  /** Configure Digital filter
  */
  if (HAL_I2CEx_ConfigDigitalFilter(&hi2c1, 0) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN I2C1_Init 2 */

  /* USER CODE END I2C1_Init 2 */

}

/**
  * @brief I2C3 Initialization Function
  * @param None
  * @retval None
  */
static void MX_I2C3_Init(void)
{

  /* USER CODE BEGIN I2C3_Init 0 */

  /* USER CODE END I2C3_Init 0 */

  /* USER CODE BEGIN I2C3_Init 1 */

  /* USER CODE END I2C3_Init 1 */
  hi2c3.Instance = I2C3;
  hi2c3.Init.Timing = 0x10C0ECFF;
  hi2c3.Init.OwnAddress1 = 0;
  hi2c3.Init.AddressingMode = I2C_ADDRESSINGMODE_7BIT;
  hi2c3.Init.DualAddressMode = I2C_DUALADDRESS_DISABLE;
  hi2c3.Init.OwnAddress2 = 0;
  hi2c3.Init.OwnAddress2Masks = I2C_OA2_NOMASK;
  hi2c3.Init.GeneralCallMode = I2C_GENERALCALL_DISABLE;
  hi2c3.Init.NoStretchMode = I2C_NOSTRETCH_DISABLE;
  if (HAL_I2C_Init(&hi2c3) != HAL_OK)
  {
    Error_Handler();
  }

  /** Configure Analogue filter
  */
  if (HAL_I2CEx_ConfigAnalogFilter(&hi2c3, I2C_ANALOGFILTER_ENABLE) != HAL_OK)
  {
    Error_Handler();
  }

  /** Configure Digital filter
  */
  if (HAL_I2CEx_ConfigDigitalFilter(&hi2c3, 0) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN I2C3_Init 2 */

  /* USER CODE END I2C3_Init 2 */

}

/**
  * @brief SPI2 Initialization Function
  * @param None
  * @retval None
  */
static void MX_SPI2_Init(void)
{

  /* USER CODE BEGIN SPI2_Init 0 */

  /* USER CODE END SPI2_Init 0 */

  /* USER CODE BEGIN SPI2_Init 1 */

  /* USER CODE END SPI2_Init 1 */
  /* SPI2 parameter configuration*/
  hspi2.Instance = SPI2;
  hspi2.Init.Mode = SPI_MODE_MASTER;
  hspi2.Init.Direction = SPI_DIRECTION_2LINES;
  hspi2.Init.DataSize = SPI_DATASIZE_4BIT;
  hspi2.Init.CLKPolarity = SPI_POLARITY_LOW;
  hspi2.Init.CLKPhase = SPI_PHASE_1EDGE;
  hspi2.Init.NSS = SPI_NSS_SOFT;
  hspi2.Init.BaudRatePrescaler = SPI_BAUDRATEPRESCALER_2;
  hspi2.Init.FirstBit = SPI_FIRSTBIT_MSB;
  hspi2.Init.TIMode = SPI_TIMODE_DISABLE;
  hspi2.Init.CRCCalculation = SPI_CRCCALCULATION_DISABLE;
  hspi2.Init.CRCPolynomial = 0x0;
  hspi2.Init.NSSPMode = SPI_NSS_PULSE_ENABLE;
  hspi2.Init.NSSPolarity = SPI_NSS_POLARITY_LOW;
  hspi2.Init.FifoThreshold = SPI_FIFO_THRESHOLD_01DATA;
  hspi2.Init.TxCRCInitializationPattern = SPI_CRC_INITIALIZATION_ALL_ZERO_PATTERN;
  hspi2.Init.RxCRCInitializationPattern = SPI_CRC_INITIALIZATION_ALL_ZERO_PATTERN;
  hspi2.Init.MasterSSIdleness = SPI_MASTER_SS_IDLENESS_00CYCLE;
  hspi2.Init.MasterInterDataIdleness = SPI_MASTER_INTERDATA_IDLENESS_00CYCLE;
  hspi2.Init.MasterReceiverAutoSusp = SPI_MASTER_RX_AUTOSUSP_DISABLE;
  hspi2.Init.MasterKeepIOState = SPI_MASTER_KEEP_IO_STATE_DISABLE;
  hspi2.Init.IOSwap = SPI_IO_SWAP_DISABLE;
  if (HAL_SPI_Init(&hspi2) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN SPI2_Init 2 */

  /* USER CODE END SPI2_Init 2 */

}

/**
  * @brief SPI3 Initialization Function
  * @param None
  * @retval None
  */
static void MX_SPI3_Init(void)
{

  /* USER CODE BEGIN SPI3_Init 0 */

  /* USER CODE END SPI3_Init 0 */

  /* USER CODE BEGIN SPI3_Init 1 */

  /* USER CODE END SPI3_Init 1 */
  /* SPI3 parameter configuration*/
  hspi3.Instance = SPI3;
  hspi3.Init.Mode = SPI_MODE_MASTER;
  hspi3.Init.Direction = SPI_DIRECTION_2LINES;
  hspi3.Init.DataSize = SPI_DATASIZE_4BIT;
  hspi3.Init.CLKPolarity = SPI_POLARITY_LOW;
  hspi3.Init.CLKPhase = SPI_PHASE_1EDGE;
  hspi3.Init.NSS = SPI_NSS_SOFT;
  hspi3.Init.BaudRatePrescaler = SPI_BAUDRATEPRESCALER_2;
  hspi3.Init.FirstBit = SPI_FIRSTBIT_MSB;
  hspi3.Init.TIMode = SPI_TIMODE_DISABLE;
  hspi3.Init.CRCCalculation = SPI_CRCCALCULATION_DISABLE;
  hspi3.Init.CRCPolynomial = 0x0;
  hspi3.Init.NSSPMode = SPI_NSS_PULSE_ENABLE;
  hspi3.Init.NSSPolarity = SPI_NSS_POLARITY_LOW;
  hspi3.Init.FifoThreshold = SPI_FIFO_THRESHOLD_01DATA;
  hspi3.Init.TxCRCInitializationPattern = SPI_CRC_INITIALIZATION_ALL_ZERO_PATTERN;
  hspi3.Init.RxCRCInitializationPattern = SPI_CRC_INITIALIZATION_ALL_ZERO_PATTERN;
  hspi3.Init.MasterSSIdleness = SPI_MASTER_SS_IDLENESS_00CYCLE;
  hspi3.Init.MasterInterDataIdleness = SPI_MASTER_INTERDATA_IDLENESS_00CYCLE;
  hspi3.Init.MasterReceiverAutoSusp = SPI_MASTER_RX_AUTOSUSP_DISABLE;
  hspi3.Init.MasterKeepIOState = SPI_MASTER_KEEP_IO_STATE_DISABLE;
  hspi3.Init.IOSwap = SPI_IO_SWAP_DISABLE;
  if (HAL_SPI_Init(&hspi3) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN SPI3_Init 2 */

  /* USER CODE END SPI3_Init 2 */

}

/**
  * @brief SPI4 Initialization Function
  * @param None
  * @retval None
  */
static void MX_SPI4_Init(void)
{

  /* USER CODE BEGIN SPI4_Init 0 */

  /* USER CODE END SPI4_Init 0 */

  /* USER CODE BEGIN SPI4_Init 1 */

  /* USER CODE END SPI4_Init 1 */
  /* SPI4 parameter configuration*/
  hspi4.Instance = SPI4;
  hspi4.Init.Mode = SPI_MODE_MASTER;
  hspi4.Init.Direction = SPI_DIRECTION_2LINES;
  /* HAND EDIT (OWIFI_RX phase 2): 8-bit frames. CubeMX defaults H7 SPI
     DataSize to 4BIT when the field is not set in the .ioc, which silently
     clocks half of every byte - the FPGA saw nibbles and returned a
     half-formed status. Add DataSize to SPI4.IPParameters in the .ioc so a
     regeneration keeps this. */
  hspi4.Init.DataSize = SPI_DATASIZE_8BIT;
  hspi4.Init.CLKPolarity = SPI_POLARITY_LOW;
  hspi4.Init.CLKPhase = SPI_PHASE_1EDGE;
  hspi4.Init.NSS = SPI_NSS_SOFT;
  hspi4.Init.BaudRatePrescaler = SPI_BAUDRATEPRESCALER_2;
  hspi4.Init.FirstBit = SPI_FIRSTBIT_MSB;
  hspi4.Init.TIMode = SPI_TIMODE_DISABLE;
  hspi4.Init.CRCCalculation = SPI_CRCCALCULATION_DISABLE;
  hspi4.Init.CRCPolynomial = 0x0;
  hspi4.Init.NSSPMode = SPI_NSS_PULSE_ENABLE;
  hspi4.Init.NSSPolarity = SPI_NSS_POLARITY_LOW;
  hspi4.Init.FifoThreshold = SPI_FIFO_THRESHOLD_01DATA;
  hspi4.Init.TxCRCInitializationPattern = SPI_CRC_INITIALIZATION_ALL_ZERO_PATTERN;
  hspi4.Init.RxCRCInitializationPattern = SPI_CRC_INITIALIZATION_ALL_ZERO_PATTERN;
  hspi4.Init.MasterSSIdleness = SPI_MASTER_SS_IDLENESS_00CYCLE;
  hspi4.Init.MasterInterDataIdleness = SPI_MASTER_INTERDATA_IDLENESS_00CYCLE;
  hspi4.Init.MasterReceiverAutoSusp = SPI_MASTER_RX_AUTOSUSP_DISABLE;
  hspi4.Init.MasterKeepIOState = SPI_MASTER_KEEP_IO_STATE_DISABLE;
  hspi4.Init.IOSwap = SPI_IO_SWAP_DISABLE;
  if (HAL_SPI_Init(&hspi4) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN SPI4_Init 2 */

  /* USER CODE END SPI4_Init 2 */

}

/**
  * @brief USART3 Initialization Function
  * @param None
  * @retval None
  */
static void MX_USART3_UART_Init(void)
{

  /* USER CODE BEGIN USART3_Init 0 */

  /* USER CODE END USART3_Init 0 */

  /* USER CODE BEGIN USART3_Init 1 */

  /* USER CODE END USART3_Init 1 */
  huart3.Instance = USART3;
  huart3.Init.BaudRate = 115200;
  huart3.Init.WordLength = UART_WORDLENGTH_8B;
  huart3.Init.StopBits = UART_STOPBITS_1;
  huart3.Init.Parity = UART_PARITY_NONE;
  huart3.Init.Mode = UART_MODE_TX_RX;
  huart3.Init.HwFlowCtl = UART_HWCONTROL_NONE;
  huart3.Init.OverSampling = UART_OVERSAMPLING_16;
  huart3.Init.OneBitSampling = UART_ONE_BIT_SAMPLE_DISABLE;
  huart3.Init.ClockPrescaler = UART_PRESCALER_DIV1;
  huart3.AdvancedInit.AdvFeatureInit = UART_ADVFEATURE_NO_INIT;
  if (HAL_UART_Init(&huart3) != HAL_OK)
  {
    Error_Handler();
  }
  if (HAL_UARTEx_SetTxFifoThreshold(&huart3, UART_TXFIFO_THRESHOLD_1_8) != HAL_OK)
  {
    Error_Handler();
  }
  if (HAL_UARTEx_SetRxFifoThreshold(&huart3, UART_RXFIFO_THRESHOLD_1_8) != HAL_OK)
  {
    Error_Handler();
  }
  if (HAL_UARTEx_DisableFifoMode(&huart3) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN USART3_Init 2 */
  /* Mode is TX_RX, not the MODE_TX the .ioc used to ask for: PD9 was already
     configured as USART3_RX by the generated MSP and the USART3 interrupt was
     already enabled and routed, but with the receiver disabled in CR1 none of
     that could ever deliver a character. The .ioc has been changed to match, so
     a CubeMX regeneration keeps the receiver on. */
  /* USER CODE END USART3_Init 2 */

}

/**
  * Enable DMA controller clock
  */
static void MX_DMA_Init(void)
{

  /* DMA controller clock enable */
  __HAL_RCC_DMA1_CLK_ENABLE();

  /* DMA interrupt init */
  /* DMA1_Stream0_IRQn interrupt configuration */
  HAL_NVIC_SetPriority(DMA1_Stream0_IRQn, 5, 0);
  HAL_NVIC_EnableIRQ(DMA1_Stream0_IRQn);

}

/**
  * @brief GPIO Initialization Function
  * @param None
  * @retval None
  */
static void MX_GPIO_Init(void)
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};
  /* USER CODE BEGIN MX_GPIO_Init_1 */

  /* USER CODE END MX_GPIO_Init_1 */

  /* GPIO Ports Clock Enable */
  __HAL_RCC_GPIOE_CLK_ENABLE();
  __HAL_RCC_GPIOC_CLK_ENABLE();
  __HAL_RCC_GPIOH_CLK_ENABLE();
  __HAL_RCC_GPIOA_CLK_ENABLE();
  __HAL_RCC_GPIOB_CLK_ENABLE();
  __HAL_RCC_GPIOD_CLK_ENABLE();

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(LORA_NRST_GPIO_Port, LORA_NRST_Pin, GPIO_PIN_SET);

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(ETH_NRST_GPIO_Port, ETH_NRST_Pin, GPIO_PIN_SET);

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(GPIOB, CS_MUX2_Pin|CS_MUX1_Pin, GPIO_PIN_RESET);

  /* HAND EDIT (OWIFI_RX phase 2): FPGA0x_PROG must come up HIGH.
     PROGRAM_B is ACTIVE LOW - CubeMX's default RESET level holds both FPGAs
     in configuration reset, which wipes a running bitstream and stops the
     board booting from flash. The pins are open-drain, so SET = released.
     These WritePin calls run BEFORE HAL_GPIO_Init configures the pins as
     outputs, so the correct ODR value is in place the instant they start
     driving - no glitch. Mirror this in the .ioc (GPIO_PinState) if the
     project is ever regenerated from CubeMX. */
  HAL_GPIO_WritePin(GPIOB, FPGA01_PROG_Pin|FPGA02_PROG_Pin, GPIO_PIN_SET);

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(GPIOE, SPI3_NSS_Pin|LED_9_Pin|LED_8_Pin
                          |uC_PE15_Pin, GPIO_PIN_RESET);

  /* HAND EDIT (OWIFI_RX phase 2): SPI4 chip select idles HIGH. At RESET the
     FPGA slave would see itself permanently selected. */
  HAL_GPIO_WritePin(SPI4_NSS_GPIO_Port, SPI4_NSS_Pin, GPIO_PIN_SET);

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(LED_7_GPIO_Port, LED_7_Pin, GPIO_PIN_SET);

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(GPIOD, PD10_DEBUG_Pin|ALARM_Pin|PD12_DEBUG_Pin|PD13_DEBUG_Pin
                          |PD14_DEBUG_Pin|PD15_DEBUG_Pin|PD0_DEBUG_Pin|PD1_DEBUG_Pin
                          |PD2_DEBUG_Pin|PD4_DEBUG_Pin|PD7_DEBUG_Pin, GPIO_PIN_RESET);

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(GPIOA, EN_MUX2_Pin|EN_MUX1_Pin|SPI2_NSS_Pin, GPIO_PIN_RESET);

  /*Configure GPIO pin Output Level */
  /* HAND EDIT (JOB-05): CS2 = FPGA2's register slave select, active LOW.
     CubeMX generates RESET here = FPGA2 permanently selected and its MISO
     driven onto the shared flash bus. Must come up SET; not in the .ioc. */
  HAL_GPIO_WritePin(SPI4_NCS2_GPIO_Port, SPI4_NCS2_Pin, GPIO_PIN_SET);

  /*Configure GPIO pins : LORA_DIO1_Pin LORA_DIO2_Pin */
  GPIO_InitStruct.Pin = LORA_DIO1_Pin|LORA_DIO2_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  HAL_GPIO_Init(GPIOE, &GPIO_InitStruct);

  /*Configure GPIO pin : LORA_NRST_Pin */
  GPIO_InitStruct.Pin = LORA_NRST_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_OD;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(LORA_NRST_GPIO_Port, &GPIO_InitStruct);

  /*Configure GPIO pins : LORA_BUSY_Pin LORA_DIO3_Pin */
  GPIO_InitStruct.Pin = LORA_BUSY_Pin|LORA_DIO3_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  HAL_GPIO_Init(GPIOC, &GPIO_InitStruct);

  /*Configure GPIO pin : uC_CONFIG_Pin */
  GPIO_InitStruct.Pin = uC_CONFIG_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
  GPIO_InitStruct.Pull = GPIO_PULLUP;
  HAL_GPIO_Init(uC_CONFIG_GPIO_Port, &GPIO_InitStruct);

  /*Configure GPIO pin : ETH_NRST_Pin */
  GPIO_InitStruct.Pin = ETH_NRST_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_OD;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(ETH_NRST_GPIO_Port, &GPIO_InitStruct);

  /*Configure GPIO pins : CS_MUX2_Pin CS_MUX1_Pin */
  GPIO_InitStruct.Pin = CS_MUX2_Pin|CS_MUX1_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOB, &GPIO_InitStruct);

  /*Configure GPIO pins : SPI3_NSS_Pin LED_9_Pin LED_8_Pin LED_7_Pin
                           SPI4_NSS_Pin uC_PE15_Pin */
  GPIO_InitStruct.Pin = SPI3_NSS_Pin|LED_9_Pin|LED_8_Pin|LED_7_Pin
                          |SPI4_NSS_Pin|uC_PE15_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOE, &GPIO_InitStruct);

  /*Configure GPIO pins : PD10_DEBUG_Pin ALARM_Pin PD12_DEBUG_Pin PD13_DEBUG_Pin
                           PD14_DEBUG_Pin PD15_DEBUG_Pin PD0_DEBUG_Pin PD1_DEBUG_Pin
                           PD2_DEBUG_Pin PD4_DEBUG_Pin PD7_DEBUG_Pin */
  GPIO_InitStruct.Pin = PD10_DEBUG_Pin|ALARM_Pin|PD12_DEBUG_Pin|PD13_DEBUG_Pin
                          |PD14_DEBUG_Pin|PD15_DEBUG_Pin|PD0_DEBUG_Pin|PD1_DEBUG_Pin
                          |PD2_DEBUG_Pin|PD4_DEBUG_Pin|PD7_DEBUG_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOD, &GPIO_InitStruct);

  /*Configure GPIO pins : EN_MUX2_Pin EN_MUX1_Pin SPI2_NSS_Pin */
  GPIO_InitStruct.Pin = EN_MUX2_Pin|EN_MUX1_Pin|SPI2_NSS_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);

  /*Configure GPIO pin : SPI4_NCS2_Pin */
  GPIO_InitStruct.Pin = SPI4_NCS2_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(SPI4_NCS2_GPIO_Port, &GPIO_InitStruct);

  /*Configure GPIO pins : FPGA01_PROG_Pin FPGA02_PROG_Pin */
  GPIO_InitStruct.Pin = FPGA01_PROG_Pin|FPGA02_PROG_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_OD;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOB, &GPIO_InitStruct);

  /* USER CODE BEGIN MX_GPIO_Init_2 */

  /* USER CODE END MX_GPIO_Init_2 */
}

/* USER CODE BEGIN 4 */

/**
  * @brief  OWIFI_RX frame read-out task.
  *
  * Polls the FPGA's status byte and drains any queued 802.11 frames into
  * g_owifi_frame / g_owifi_tel.
  *
  * Runs as its own task so it is independent of StartDefaultTask, which
  * calls MX_LWIP_Init() - that can stall on a PHY with no link, and the
  * receiver must not be hostage to the network stack coming up.
  *
  * 2ms period against a ~500ms frame interval is ~250x oversampled, which
  * costs almost nothing: a poll is a 2-byte SPI transaction (~1.3us at
  * 12.5MHz) because the FPGA returns its status full-duplex in byte 1.
  *
  * SPI4 is touched by nothing else, so no mutex is needed. If another task
  * ever shares the bus, guard the whole CS-low window - not the individual
  * transfers - or a burst read will be torn in half.
  */
void StartOwifiRxTask(void *argument)
{
  UNUSED(argument);

  /* Queue frames whose FCS failed as well, so the gap between the generator's
     rate and what we were capturing becomes visible instead of being silently
     dropped in the FPGA. Also clear the stale sticky-overflow flag left from
     the period before the host was draining the queue, so the flag from here
     on means something. */
  logw_bus_lock();
  rasbb_fpga_control(RASBB_CTRL_KEEP_BAD | RASBB_CTRL_CLR_STICKY);
  logw_bus_unlock();

  for (;;)
  {
    uint8_t st;

    /* SPI4 is shared with the link sequencer (logw_seq.c): hold the bus
       guard for one whole iteration - a poll plus at most one frame read,
       ~1.5 ms worst case - and release it around the osDelay. */
    logw_bus_lock();

    /* apply any changed detection knob and restart the measurement window */
    {
      uint32_t rb;
      uint8_t changed = 0u;

      if (g_cmd_thresh != 0u && g_cmd_thresh != g_applied_thresh)
      {
        rb = 0xFFFFFFFFu;
        rasbb_fpga_write_reg(RASBB_REG_POWER_THRES, g_cmd_thresh);
        if (rasbb_fpga_read_reg(RASBB_REG_POWER_THRES, &rb))
          g_readback_thresh = rb;
        g_applied_thresh = g_cmd_thresh;
        changed = 1u;
      }
      if (g_cmd_window != 0u && g_cmd_window != g_applied_window)
      {
        rb = 0xFFFFFFFFu;
        rasbb_fpga_write_reg(RASBB_REG_POWER_WINDOW, g_cmd_window);
        if (rasbb_fpga_read_reg(RASBB_REG_POWER_WINDOW, &rb))
          g_readback_window = rb;
        g_applied_window = g_cmd_window;
        changed = 1u;
      }
      if (g_cmd_plateau != 0u && g_cmd_plateau != g_applied_plateau)
      {
        rb = 0xFFFFFFFFu;
        rasbb_fpga_write_reg(RASBB_REG_MIN_PLATEAU, g_cmd_plateau);
        if (rasbb_fpga_read_reg(RASBB_REG_MIN_PLATEAU, &rb))
          g_readback_plateau = rb;
        g_applied_plateau = g_cmd_plateau;
        changed = 1u;
      }

      if (changed)
      {
        g_meas_polls  = 0;
        g_meas_frames = 0;
        g_meas_bad    = 0;
      }
    }

    st = rasbb_fpga_status();
    /* Apply the persisted IQ capture / network settings once per FPGA
       (re)appearance: FPGA1 = it answers with a sane NSAMP register, FPGA2 =
       its PHY_ID reads as the RTL8211E. Checked once a second. */
    {
      static uint32_t t_chk = 0u;
      static uint8_t applied1 = 0u, applied2 = 0u;
      if ((HAL_GetTick() - t_chk) >= 1000u)
      {
        t_chk = HAL_GetTick();
        /* FPGA1 "present" = it answers on SPI and its capture register file
           reads back a sane NSAMP (LINK_OK would mean the ADC LVDS link,
           which is absent without a front end). */
        {
          uint32_t ns = 0u;
          if (st != 0xFFu && rasbb_fpga_read_reg(0x11u, &ns) && ns >= 1u && ns <= 1024u)
          {
            if (!applied1) applied1 = iqcap_cfg_apply_fpga1() ? 1u : 0u;
          }
          else applied1 = 0u;
        }
        if (iqcap_fpga2_present())
        {
          if (!applied2) applied2 = iqcap_cfg_apply_fpga2() ? 1u : 0u;
        }
        else applied2 = 0u;
      }
    }

    g_owifi_tel.polls++;
    g_meas_polls++;
    g_owifi_tel.last_status = st;

    if (st == 0xFFu)
    {
      g_owifi_tel.spi_errors++;
    }
    else if (st & RASBB_ST_FRAME_READY)
    {
      if (rasbb_fpga_read_frame(&g_owifi_frame))
      {
        uint16_t n = (g_owifi_frame.desc.len < 16u) ? g_owifi_frame.desc.len : 16u;

        if (g_owifi_frame.desc.flags & RASBB_DESC_FCS_OK)
        {
          g_owifi_tel.frames++;
          g_meas_frames++;
          memcpy((void *)g_owifi_tel.first16, g_owifi_frame.payload, n);
        }
        else
        {
          g_owifi_tel.frames_bad++;
          g_meas_bad++;
          g_owifi_tel.last_bad_len = g_owifi_frame.desc.len;
          memcpy((void *)g_owifi_tel.bad_first16, g_owifi_frame.payload, n);
        }

        g_owifi_tel.last_len       = g_owifi_frame.desc.len;
        g_owifi_tel.last_flags     = g_owifi_frame.desc.flags;
        g_owifi_tel.last_seq       = g_owifi_frame.desc.seq;
        g_owifi_tel.last_timestamp = g_owifi_frame.desc.timestamp_us;

        /* Retire it only now that it is safely copied out - the FPGA holds
           the frame until POP, so a failed read can simply be retried. */
        rasbb_fpga_pop();

        /* TODO (production): hand the frame on here - Ethernet/pcap or the
           LoRa link - instead of only recording it in g_owifi_tel. */
      }
      else
      {
        g_owifi_tel.read_errors++;
      }
    }

    logw_bus_unlock();
    osDelay(2);
  }
}

/**
  * @brief  Frontend console task.
  *
  * Drains USART3 and runs whatever command arrived. See console.c; the
  * commands themselves talk to the RF frontend over I2C1 (rasrf.c).
  *
  * 5ms is well inside what a person can type and leaves the 64-byte receive
  * ring three times more room than the longest command line, so even a pasted
  * command cannot outrun it. The banner is printed from in here rather than
  * from main() because it probes the frontend, and an I2C transaction should
  * happen where it can yield.
  *
  * The only task that prints, apart from the one "Firmware starts" before the
  * scheduler - so there is no lock around stdout. Give it one before adding
  * printf to another task, or the two will interleave mid-line.
  */
void StartConsoleTask(void *argument)
{
  UNUSED(argument);

  console_banner();

  for (;;)
  {
    console_poll();
    menu_poll();      /* J8 buttons, auto-repeat, menu timeout (5 ms tick) */
    osDelay(5);
  }
}

/* USER CODE END 4 */

/* USER CODE BEGIN Header_StartDefaultTask */
/**
  * @brief  Function implementing the defaultTask thread.
  * @param  argument: Not used
  * @retval None
  */
/* USER CODE END Header_StartDefaultTask */
void StartDefaultTask(void *argument)
{
  /* init code for LWIP */
  g_owifi_phase = 1;                      /* HAND EDIT: bring-up marker */
  g_free_heap = (uint32_t)xPortGetFreeHeapSize();

  /* HAND EDIT (2026-09-19, Ethernet bring-up): MX_LWIP_Init() is back. The
     2026-07-31 hang was the missing non-cacheable MPU region over RAM_D2
     (see MPU_Config) plus LWIP_TCP=0 in lwipopts.h; both fixed by hand,
     NOT in the .ioc. The web server (RASBB_ECU's httpserver_netconn.c +
     webpage*.c) runs in its own thread; the suspect list it shows still
     comes from the DPFPGA.c simulator until a real source exists. */
  MX_LWIP_Init();
  DPFPGA_init();
  http_server_netconn_init();
  g_owifi_phase = 2;
  /* USER CODE BEGIN 5 */
  /* Infinite loop */
  for(;;)
  {
    osDelay(1);
  }
  /* USER CODE END 5 */
}

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
  /* HAND EDIT (Ethernet bring-up 2026-09-19, not in the .ioc): RAM_D2
     0x30000000..0x3000FFFF as Normal, NON-cacheable, shareable. It holds the
     ETH DMA descriptors (.RxDecripSection/.TxDecripSection), the zero-copy
     RX pool (.Rx_PoolSection) and the lwIP heap (LWIP_RAM_HEAP_POINTER
     0x30008000). With the D-cache on and no such region the CPU read stale
     descriptors and MX_LWIP_Init() hung ~500 ms after the scheduler started
     (the "lwIP is broken on this board" finding of 2026-07-31). */
  MPU_InitStruct.Enable = MPU_REGION_ENABLE;
  MPU_InitStruct.Number = MPU_REGION_NUMBER1;
  MPU_InitStruct.BaseAddress = 0x30000000;
  MPU_InitStruct.Size = MPU_REGION_SIZE_64KB;
  MPU_InitStruct.SubRegionDisable = 0x0;
  MPU_InitStruct.TypeExtField = MPU_TEX_LEVEL1;
  MPU_InitStruct.AccessPermission = MPU_REGION_FULL_ACCESS;
  MPU_InitStruct.DisableExec = MPU_INSTRUCTION_ACCESS_ENABLE;
  MPU_InitStruct.IsShareable = MPU_ACCESS_SHAREABLE;
  MPU_InitStruct.IsCacheable = MPU_ACCESS_NOT_CACHEABLE;
  MPU_InitStruct.IsBufferable = MPU_ACCESS_NOT_BUFFERABLE;
  HAL_MPU_ConfigRegion(&MPU_InitStruct);
  /* Enables the MPU */
  HAL_MPU_Enable(MPU_PRIVILEGED_DEFAULT);

}

/**
  * @brief  Period elapsed callback in non blocking mode
  * @note   This function is called  when TIM4 interrupt took place, inside
  * HAL_TIM_IRQHandler(). It makes a direct call to HAL_IncTick() to increment
  * a global variable "uwTick" used as application time base.
  * @param  htim : TIM handle
  * @retval None
  */
void HAL_TIM_PeriodElapsedCallback(TIM_HandleTypeDef *htim)
{
  /* USER CODE BEGIN Callback 0 */

  /* USER CODE END Callback 0 */
  if (htim->Instance == TIM4)
  {
    HAL_IncTick();
  }
  /* USER CODE BEGIN Callback 1 */

  /* USER CODE END Callback 1 */
}

/**
  * @brief  This function is executed in case of error occurrence.
  * @retval None
  */
void Error_Handler(void)
{
  /* USER CODE BEGIN Error_Handler_Debug */
  /* User can add his own implementation to report the HAL error return state */
  g_error_handler_hit++;   /* leave a trace BEFORE masking interrupts */
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
