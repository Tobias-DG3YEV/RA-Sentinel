//////////////////////////////////////////////////////////////////////////////////
// hdmi_clk.v
//
// Pixel/serial clock generation for 1080p60 HDMI out of the 50MHz SYS_clk.
//
// 1920x1080@60 wants 148.500MHz pixel / 742.500MHz TMDS bit clock. Neither is
// reachable exactly from 50MHz in one MMCM (M would have to be 14.85, but
// CLKFBOUT_MULT_F only has 0.125 granularity), so the nearest legal setting is
// used: M = 14.875 -> VCO = 743.75MHz (inside the -2 part's 600..1440MHz VCO
// window), CLKOUT0 = VCO/1 = 743.75MHz serial, CLKOUT1 = VCO/5 = 148.75MHz
// pixel. That is +0.17% off nominal -> 60.10Hz refresh; HDMI sinks lock to the
// TMDS clock, and a fraction of a percent is far inside what monitors accept
// (the previous 1024x768/65.0MHz mode was similarly "nominal-ish", not exact).
//
// The serial clock goes onto a BUFG feeding the OSERDES in OutputSERDES.vhd.
// 743.75MHz is ~5% above the -2 BUFG datasheet Fmax - the standard, widely
// shipped way 1080p DVI is done on Artix-7 (Digilent's own rgb2dvi demos do
// exactly this); if a particular die ever proves marginal the fallback is
// dropping to 1280x720 (371.25MHz serial, fully in spec).
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module hdmi_clk (
    input  wire i_clk_50M,
    output wire o_clk_pix,     // 148.75MHz pixel clock (BUFG)
    output wire o_clk_serial,  // 743.75MHz TMDS serial clock (BUFG)
    output wire o_locked
);

wire clkfb;
wire clk_serial_unbuf;
wire clk_pix_unbuf;

MMCME2_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKIN1_PERIOD(20.000),      // 50MHz
    .CLKFBOUT_MULT_F(14.875),    // VCO = 743.75MHz
    .DIVCLK_DIVIDE(1),
    .CLKOUT0_DIVIDE_F(1.000),    // 743.75MHz serial
    .CLKOUT1_DIVIDE(5),          // 148.75MHz pixel (exactly serial/5, same VCO)
    .CLKOUT0_PHASE(0.0),
    .CLKOUT1_PHASE(0.0),
    .STARTUP_WAIT("FALSE")
) mmcm_hdmi (
    .CLKIN1(i_clk_50M),
    .CLKFBIN(clkfb),
    .CLKFBOUT(clkfb),
    .CLKOUT0(clk_serial_unbuf),
    .CLKOUT1(clk_pix_unbuf),
    .CLKOUT2(), .CLKOUT3(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
    .CLKFBOUTB(), .CLKOUT0B(), .CLKOUT1B(), .CLKOUT2B(), .CLKOUT3B(),
    .LOCKED(o_locked),
    .PWRDWN(1'b0),
    .RST(1'b0)
);

BUFG bufg_serial (.I(clk_serial_unbuf), .O(o_clk_serial));
BUFG bufg_pix    (.I(clk_pix_unbuf),    .O(o_clk_pix));

endmodule
