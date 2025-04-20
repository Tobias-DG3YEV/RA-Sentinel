-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2024.2 (win64) Build 5239630 Fri Nov 08 22:35:27 MST 2024
-- Date        : Sun Apr 20 19:47:13 2025
-- Host        : PC1008 running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode funcsim
--               D:/Data/RASentinel/RASBB/AP-FPGA/AP_TEST/AP_TEST.runs/Video_clk_synth_1/Video_clk_sim_netlist.vhdl
-- Design      : Video_clk
-- Purpose     : This VHDL netlist is a functional simulation representation of the design and should not be modified or
--               synthesized. This netlist cannot be used for SDF annotated simulation.
-- Device      : xc7a100tcsg324-2
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;
entity Video_clk_clk_wiz is
  port (
    o_clk_65M : out STD_LOGIC;
    o_clk_325M : out STD_LOGIC;
    o_clk_195M : out STD_LOGIC;
    o_clk_120M : out STD_LOGIC;
    reset : in STD_LOGIC;
    locked : out STD_LOGIC;
    i_clk_50M : in STD_LOGIC
  );
end Video_clk_clk_wiz;

architecture STRUCTURE of Video_clk_clk_wiz is
  signal clkfbout_Video_clk : STD_LOGIC;
  signal clkfbout_buf_Video_clk : STD_LOGIC;
  signal i_clk_50M_Video_clk : STD_LOGIC;
  signal \^locked\ : STD_LOGIC;
  signal o_clk_120M_Video_clk : STD_LOGIC;
  signal o_clk_120M_Video_clk_en_clk : STD_LOGIC;
  signal o_clk_195M_Video_clk : STD_LOGIC;
  signal o_clk_195M_Video_clk_en_clk : STD_LOGIC;
  signal o_clk_325M_Video_clk : STD_LOGIC;
  signal o_clk_325M_Video_clk_en_clk : STD_LOGIC;
  signal o_clk_65M_Video_clk : STD_LOGIC;
  signal o_clk_65M_Video_clk_en_clk : STD_LOGIC;
  signal seq_reg1 : STD_LOGIC_VECTOR ( 7 downto 0 );
  attribute RTL_KEEP : string;
  attribute RTL_KEEP of seq_reg1 : signal is "true";
  attribute async_reg : string;
  attribute async_reg of seq_reg1 : signal is "true";
  signal seq_reg2 : STD_LOGIC_VECTOR ( 7 downto 0 );
  attribute RTL_KEEP of seq_reg2 : signal is "true";
  attribute async_reg of seq_reg2 : signal is "true";
  signal seq_reg3 : STD_LOGIC_VECTOR ( 7 downto 0 );
  attribute RTL_KEEP of seq_reg3 : signal is "true";
  attribute async_reg of seq_reg3 : signal is "true";
  signal seq_reg4 : STD_LOGIC_VECTOR ( 7 downto 0 );
  attribute RTL_KEEP of seq_reg4 : signal is "true";
  attribute async_reg of seq_reg4 : signal is "true";
  signal NLW_mmcm_adv_inst_CLKFBOUTB_UNCONNECTED : STD_LOGIC;
  signal NLW_mmcm_adv_inst_CLKFBSTOPPED_UNCONNECTED : STD_LOGIC;
  signal NLW_mmcm_adv_inst_CLKINSTOPPED_UNCONNECTED : STD_LOGIC;
  signal NLW_mmcm_adv_inst_CLKOUT0B_UNCONNECTED : STD_LOGIC;
  signal NLW_mmcm_adv_inst_CLKOUT1B_UNCONNECTED : STD_LOGIC;
  signal NLW_mmcm_adv_inst_CLKOUT2B_UNCONNECTED : STD_LOGIC;
  signal NLW_mmcm_adv_inst_CLKOUT3B_UNCONNECTED : STD_LOGIC;
  signal NLW_mmcm_adv_inst_CLKOUT4_UNCONNECTED : STD_LOGIC;
  signal NLW_mmcm_adv_inst_CLKOUT5_UNCONNECTED : STD_LOGIC;
  signal NLW_mmcm_adv_inst_CLKOUT6_UNCONNECTED : STD_LOGIC;
  signal NLW_mmcm_adv_inst_DRDY_UNCONNECTED : STD_LOGIC;
  signal NLW_mmcm_adv_inst_PSDONE_UNCONNECTED : STD_LOGIC;
  signal NLW_mmcm_adv_inst_DO_UNCONNECTED : STD_LOGIC_VECTOR ( 15 downto 0 );
  attribute BOX_TYPE : string;
  attribute BOX_TYPE of clkf_buf : label is "PRIMITIVE";
  attribute BOX_TYPE of clkin1_ibufg : label is "PRIMITIVE";
  attribute CAPACITANCE : string;
  attribute CAPACITANCE of clkin1_ibufg : label is "DONT_CARE";
  attribute IBUF_DELAY_VALUE : string;
  attribute IBUF_DELAY_VALUE of clkin1_ibufg : label is "0";
  attribute IFD_DELAY_VALUE : string;
  attribute IFD_DELAY_VALUE of clkin1_ibufg : label is "AUTO";
  attribute BOX_TYPE of clkout1_buf : label is "PRIMITIVE";
  attribute XILINX_LEGACY_PRIM : string;
  attribute XILINX_LEGACY_PRIM of clkout1_buf : label is "BUFGCE";
  attribute XILINX_TRANSFORM_PINMAP : string;
  attribute XILINX_TRANSFORM_PINMAP of clkout1_buf : label is "CE:CE0 I:I0 GND:S1,IGNORE0,CE1 VCC:S0,IGNORE1,I1";
  attribute BOX_TYPE of clkout1_buf_en : label is "PRIMITIVE";
  attribute BOX_TYPE of clkout2_buf : label is "PRIMITIVE";
  attribute XILINX_LEGACY_PRIM of clkout2_buf : label is "BUFGCE";
  attribute XILINX_TRANSFORM_PINMAP of clkout2_buf : label is "CE:CE0 I:I0 GND:S1,IGNORE0,CE1 VCC:S0,IGNORE1,I1";
  attribute BOX_TYPE of clkout2_buf_en : label is "PRIMITIVE";
  attribute BOX_TYPE of clkout3_buf : label is "PRIMITIVE";
  attribute XILINX_LEGACY_PRIM of clkout3_buf : label is "BUFGCE";
  attribute XILINX_TRANSFORM_PINMAP of clkout3_buf : label is "CE:CE0 I:I0 GND:S1,IGNORE0,CE1 VCC:S0,IGNORE1,I1";
  attribute BOX_TYPE of clkout3_buf_en : label is "PRIMITIVE";
  attribute BOX_TYPE of clkout4_buf : label is "PRIMITIVE";
  attribute XILINX_LEGACY_PRIM of clkout4_buf : label is "BUFGCE";
  attribute XILINX_TRANSFORM_PINMAP of clkout4_buf : label is "CE:CE0 I:I0 GND:S1,IGNORE0,CE1 VCC:S0,IGNORE1,I1";
  attribute BOX_TYPE of clkout4_buf_en : label is "PRIMITIVE";
  attribute BOX_TYPE of mmcm_adv_inst : label is "PRIMITIVE";
  attribute ASYNC_REG_boolean : boolean;
  attribute ASYNC_REG_boolean of \seq_reg1_reg[0]\ : label is std.standard.true;
  attribute KEEP : string;
  attribute KEEP of \seq_reg1_reg[0]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg1_reg[1]\ : label is std.standard.true;
  attribute KEEP of \seq_reg1_reg[1]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg1_reg[2]\ : label is std.standard.true;
  attribute KEEP of \seq_reg1_reg[2]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg1_reg[3]\ : label is std.standard.true;
  attribute KEEP of \seq_reg1_reg[3]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg1_reg[4]\ : label is std.standard.true;
  attribute KEEP of \seq_reg1_reg[4]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg1_reg[5]\ : label is std.standard.true;
  attribute KEEP of \seq_reg1_reg[5]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg1_reg[6]\ : label is std.standard.true;
  attribute KEEP of \seq_reg1_reg[6]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg1_reg[7]\ : label is std.standard.true;
  attribute KEEP of \seq_reg1_reg[7]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg2_reg[0]\ : label is std.standard.true;
  attribute KEEP of \seq_reg2_reg[0]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg2_reg[1]\ : label is std.standard.true;
  attribute KEEP of \seq_reg2_reg[1]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg2_reg[2]\ : label is std.standard.true;
  attribute KEEP of \seq_reg2_reg[2]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg2_reg[3]\ : label is std.standard.true;
  attribute KEEP of \seq_reg2_reg[3]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg2_reg[4]\ : label is std.standard.true;
  attribute KEEP of \seq_reg2_reg[4]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg2_reg[5]\ : label is std.standard.true;
  attribute KEEP of \seq_reg2_reg[5]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg2_reg[6]\ : label is std.standard.true;
  attribute KEEP of \seq_reg2_reg[6]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg2_reg[7]\ : label is std.standard.true;
  attribute KEEP of \seq_reg2_reg[7]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg3_reg[0]\ : label is std.standard.true;
  attribute KEEP of \seq_reg3_reg[0]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg3_reg[1]\ : label is std.standard.true;
  attribute KEEP of \seq_reg3_reg[1]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg3_reg[2]\ : label is std.standard.true;
  attribute KEEP of \seq_reg3_reg[2]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg3_reg[3]\ : label is std.standard.true;
  attribute KEEP of \seq_reg3_reg[3]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg3_reg[4]\ : label is std.standard.true;
  attribute KEEP of \seq_reg3_reg[4]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg3_reg[5]\ : label is std.standard.true;
  attribute KEEP of \seq_reg3_reg[5]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg3_reg[6]\ : label is std.standard.true;
  attribute KEEP of \seq_reg3_reg[6]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg3_reg[7]\ : label is std.standard.true;
  attribute KEEP of \seq_reg3_reg[7]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg4_reg[0]\ : label is std.standard.true;
  attribute KEEP of \seq_reg4_reg[0]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg4_reg[1]\ : label is std.standard.true;
  attribute KEEP of \seq_reg4_reg[1]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg4_reg[2]\ : label is std.standard.true;
  attribute KEEP of \seq_reg4_reg[2]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg4_reg[3]\ : label is std.standard.true;
  attribute KEEP of \seq_reg4_reg[3]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg4_reg[4]\ : label is std.standard.true;
  attribute KEEP of \seq_reg4_reg[4]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg4_reg[5]\ : label is std.standard.true;
  attribute KEEP of \seq_reg4_reg[5]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg4_reg[6]\ : label is std.standard.true;
  attribute KEEP of \seq_reg4_reg[6]\ : label is "yes";
  attribute ASYNC_REG_boolean of \seq_reg4_reg[7]\ : label is std.standard.true;
  attribute KEEP of \seq_reg4_reg[7]\ : label is "yes";
begin
  locked <= \^locked\;
clkf_buf: unisim.vcomponents.BUFG
     port map (
      I => clkfbout_Video_clk,
      O => clkfbout_buf_Video_clk
    );
clkin1_ibufg: unisim.vcomponents.IBUF
    generic map(
      IOSTANDARD => "DEFAULT"
    )
        port map (
      I => i_clk_50M,
      O => i_clk_50M_Video_clk
    );
clkout1_buf: unisim.vcomponents.BUFGCTRL
    generic map(
      INIT_OUT => 0,
      PRESELECT_I0 => true,
      PRESELECT_I1 => false,
      SIM_DEVICE => "7SERIES"
    )
        port map (
      CE0 => seq_reg1(7),
      CE1 => '0',
      I0 => o_clk_65M_Video_clk,
      I1 => '1',
      IGNORE0 => '0',
      IGNORE1 => '1',
      O => o_clk_65M,
      S0 => '1',
      S1 => '0'
    );
clkout1_buf_en: unisim.vcomponents.BUFH
     port map (
      I => o_clk_65M_Video_clk,
      O => o_clk_65M_Video_clk_en_clk
    );
clkout2_buf: unisim.vcomponents.BUFGCTRL
    generic map(
      INIT_OUT => 0,
      PRESELECT_I0 => true,
      PRESELECT_I1 => false,
      SIM_DEVICE => "7SERIES"
    )
        port map (
      CE0 => seq_reg2(7),
      CE1 => '0',
      I0 => o_clk_325M_Video_clk,
      I1 => '1',
      IGNORE0 => '0',
      IGNORE1 => '1',
      O => o_clk_325M,
      S0 => '1',
      S1 => '0'
    );
clkout2_buf_en: unisim.vcomponents.BUFH
     port map (
      I => o_clk_325M_Video_clk,
      O => o_clk_325M_Video_clk_en_clk
    );
clkout3_buf: unisim.vcomponents.BUFGCTRL
    generic map(
      INIT_OUT => 0,
      PRESELECT_I0 => true,
      PRESELECT_I1 => false,
      SIM_DEVICE => "7SERIES"
    )
        port map (
      CE0 => seq_reg3(7),
      CE1 => '0',
      I0 => o_clk_195M_Video_clk,
      I1 => '1',
      IGNORE0 => '0',
      IGNORE1 => '1',
      O => o_clk_195M,
      S0 => '1',
      S1 => '0'
    );
clkout3_buf_en: unisim.vcomponents.BUFH
     port map (
      I => o_clk_195M_Video_clk,
      O => o_clk_195M_Video_clk_en_clk
    );
clkout4_buf: unisim.vcomponents.BUFGCTRL
    generic map(
      INIT_OUT => 0,
      PRESELECT_I0 => true,
      PRESELECT_I1 => false,
      SIM_DEVICE => "7SERIES"
    )
        port map (
      CE0 => seq_reg4(7),
      CE1 => '0',
      I0 => o_clk_120M_Video_clk,
      I1 => '1',
      IGNORE0 => '0',
      IGNORE1 => '1',
      O => o_clk_120M,
      S0 => '1',
      S1 => '0'
    );
clkout4_buf_en: unisim.vcomponents.BUFH
     port map (
      I => o_clk_120M_Video_clk,
      O => o_clk_120M_Video_clk_en_clk
    );
mmcm_adv_inst: unisim.vcomponents.MMCME2_ADV
    generic map(
      BANDWIDTH => "OPTIMIZED",
      CLKFBOUT_MULT_F => 19.500000,
      CLKFBOUT_PHASE => 0.000000,
      CLKFBOUT_USE_FINE_PS => false,
      CLKIN1_PERIOD => 20.000000,
      CLKIN2_PERIOD => 0.000000,
      CLKOUT0_DIVIDE_F => 15.000000,
      CLKOUT0_DUTY_CYCLE => 0.500000,
      CLKOUT0_PHASE => 0.000000,
      CLKOUT0_USE_FINE_PS => false,
      CLKOUT1_DIVIDE => 3,
      CLKOUT1_DUTY_CYCLE => 0.500000,
      CLKOUT1_PHASE => 0.000000,
      CLKOUT1_USE_FINE_PS => false,
      CLKOUT2_DIVIDE => 5,
      CLKOUT2_DUTY_CYCLE => 0.500000,
      CLKOUT2_PHASE => 0.000000,
      CLKOUT2_USE_FINE_PS => false,
      CLKOUT3_DIVIDE => 8,
      CLKOUT3_DUTY_CYCLE => 0.500000,
      CLKOUT3_PHASE => 0.000000,
      CLKOUT3_USE_FINE_PS => false,
      CLKOUT4_CASCADE => false,
      CLKOUT4_DIVIDE => 1,
      CLKOUT4_DUTY_CYCLE => 0.500000,
      CLKOUT4_PHASE => 0.000000,
      CLKOUT4_USE_FINE_PS => false,
      CLKOUT5_DIVIDE => 1,
      CLKOUT5_DUTY_CYCLE => 0.500000,
      CLKOUT5_PHASE => 0.000000,
      CLKOUT5_USE_FINE_PS => false,
      CLKOUT6_DIVIDE => 1,
      CLKOUT6_DUTY_CYCLE => 0.500000,
      CLKOUT6_PHASE => 0.000000,
      CLKOUT6_USE_FINE_PS => false,
      COMPENSATION => "ZHOLD",
      DIVCLK_DIVIDE => 1,
      IS_CLKINSEL_INVERTED => '0',
      IS_PSEN_INVERTED => '0',
      IS_PSINCDEC_INVERTED => '0',
      IS_PWRDWN_INVERTED => '0',
      IS_RST_INVERTED => '0',
      REF_JITTER1 => 0.010000,
      REF_JITTER2 => 0.010000,
      SS_EN => "FALSE",
      SS_MODE => "CENTER_HIGH",
      SS_MOD_PERIOD => 10000,
      STARTUP_WAIT => false
    )
        port map (
      CLKFBIN => clkfbout_buf_Video_clk,
      CLKFBOUT => clkfbout_Video_clk,
      CLKFBOUTB => NLW_mmcm_adv_inst_CLKFBOUTB_UNCONNECTED,
      CLKFBSTOPPED => NLW_mmcm_adv_inst_CLKFBSTOPPED_UNCONNECTED,
      CLKIN1 => i_clk_50M_Video_clk,
      CLKIN2 => '0',
      CLKINSEL => '1',
      CLKINSTOPPED => NLW_mmcm_adv_inst_CLKINSTOPPED_UNCONNECTED,
      CLKOUT0 => o_clk_65M_Video_clk,
      CLKOUT0B => NLW_mmcm_adv_inst_CLKOUT0B_UNCONNECTED,
      CLKOUT1 => o_clk_325M_Video_clk,
      CLKOUT1B => NLW_mmcm_adv_inst_CLKOUT1B_UNCONNECTED,
      CLKOUT2 => o_clk_195M_Video_clk,
      CLKOUT2B => NLW_mmcm_adv_inst_CLKOUT2B_UNCONNECTED,
      CLKOUT3 => o_clk_120M_Video_clk,
      CLKOUT3B => NLW_mmcm_adv_inst_CLKOUT3B_UNCONNECTED,
      CLKOUT4 => NLW_mmcm_adv_inst_CLKOUT4_UNCONNECTED,
      CLKOUT5 => NLW_mmcm_adv_inst_CLKOUT5_UNCONNECTED,
      CLKOUT6 => NLW_mmcm_adv_inst_CLKOUT6_UNCONNECTED,
      DADDR(6 downto 0) => B"0000000",
      DCLK => '0',
      DEN => '0',
      DI(15 downto 0) => B"0000000000000000",
      DO(15 downto 0) => NLW_mmcm_adv_inst_DO_UNCONNECTED(15 downto 0),
      DRDY => NLW_mmcm_adv_inst_DRDY_UNCONNECTED,
      DWE => '0',
      LOCKED => \^locked\,
      PSCLK => '0',
      PSDONE => NLW_mmcm_adv_inst_PSDONE_UNCONNECTED,
      PSEN => '0',
      PSINCDEC => '0',
      PWRDWN => '0',
      RST => reset
    );
\seq_reg1_reg[0]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_65M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => \^locked\,
      Q => seq_reg1(0)
    );
\seq_reg1_reg[1]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_65M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg1(0),
      Q => seq_reg1(1)
    );
\seq_reg1_reg[2]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_65M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg1(1),
      Q => seq_reg1(2)
    );
\seq_reg1_reg[3]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_65M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg1(2),
      Q => seq_reg1(3)
    );
\seq_reg1_reg[4]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_65M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg1(3),
      Q => seq_reg1(4)
    );
\seq_reg1_reg[5]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_65M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg1(4),
      Q => seq_reg1(5)
    );
\seq_reg1_reg[6]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_65M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg1(5),
      Q => seq_reg1(6)
    );
\seq_reg1_reg[7]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_65M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg1(6),
      Q => seq_reg1(7)
    );
\seq_reg2_reg[0]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_325M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => \^locked\,
      Q => seq_reg2(0)
    );
\seq_reg2_reg[1]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_325M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg2(0),
      Q => seq_reg2(1)
    );
\seq_reg2_reg[2]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_325M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg2(1),
      Q => seq_reg2(2)
    );
\seq_reg2_reg[3]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_325M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg2(2),
      Q => seq_reg2(3)
    );
\seq_reg2_reg[4]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_325M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg2(3),
      Q => seq_reg2(4)
    );
\seq_reg2_reg[5]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_325M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg2(4),
      Q => seq_reg2(5)
    );
\seq_reg2_reg[6]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_325M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg2(5),
      Q => seq_reg2(6)
    );
\seq_reg2_reg[7]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_325M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg2(6),
      Q => seq_reg2(7)
    );
\seq_reg3_reg[0]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_195M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => \^locked\,
      Q => seq_reg3(0)
    );
\seq_reg3_reg[1]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_195M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg3(0),
      Q => seq_reg3(1)
    );
\seq_reg3_reg[2]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_195M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg3(1),
      Q => seq_reg3(2)
    );
\seq_reg3_reg[3]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_195M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg3(2),
      Q => seq_reg3(3)
    );
\seq_reg3_reg[4]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_195M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg3(3),
      Q => seq_reg3(4)
    );
\seq_reg3_reg[5]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_195M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg3(4),
      Q => seq_reg3(5)
    );
\seq_reg3_reg[6]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_195M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg3(5),
      Q => seq_reg3(6)
    );
\seq_reg3_reg[7]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_195M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg3(6),
      Q => seq_reg3(7)
    );
\seq_reg4_reg[0]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_120M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => \^locked\,
      Q => seq_reg4(0)
    );
\seq_reg4_reg[1]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_120M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg4(0),
      Q => seq_reg4(1)
    );
\seq_reg4_reg[2]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_120M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg4(1),
      Q => seq_reg4(2)
    );
\seq_reg4_reg[3]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_120M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg4(2),
      Q => seq_reg4(3)
    );
\seq_reg4_reg[4]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_120M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg4(3),
      Q => seq_reg4(4)
    );
\seq_reg4_reg[5]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_120M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg4(4),
      Q => seq_reg4(5)
    );
\seq_reg4_reg[6]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_120M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg4(5),
      Q => seq_reg4(6)
    );
\seq_reg4_reg[7]\: unisim.vcomponents.FDCE
    generic map(
      INIT => '0'
    )
        port map (
      C => o_clk_120M_Video_clk_en_clk,
      CE => '1',
      CLR => reset,
      D => seq_reg4(6),
      Q => seq_reg4(7)
    );
end STRUCTURE;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;
entity Video_clk is
  port (
    o_clk_65M : out STD_LOGIC;
    o_clk_325M : out STD_LOGIC;
    o_clk_195M : out STD_LOGIC;
    o_clk_120M : out STD_LOGIC;
    reset : in STD_LOGIC;
    locked : out STD_LOGIC;
    i_clk_50M : in STD_LOGIC
  );
  attribute NotValidForBitStream : boolean;
  attribute NotValidForBitStream of Video_clk : entity is true;
end Video_clk;

architecture STRUCTURE of Video_clk is
begin
inst: entity work.Video_clk_clk_wiz
     port map (
      i_clk_50M => i_clk_50M,
      locked => locked,
      o_clk_120M => o_clk_120M,
      o_clk_195M => o_clk_195M,
      o_clk_325M => o_clk_325M,
      o_clk_65M => o_clk_65M,
      reset => reset
    );
end STRUCTURE;
