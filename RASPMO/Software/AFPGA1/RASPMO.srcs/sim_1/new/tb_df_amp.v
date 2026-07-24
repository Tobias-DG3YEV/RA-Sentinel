`timescale 1ns / 1ps

/* Feeds df_amp a single populated FFT bin whose four channel amplitudes
   correspond to a source at a known bearing, then dumps the resulting angle
   table so a reference model can confirm the recovered bearing. */
module tb_df_amp;

localparam NTEST   = 25;
localparam FFTLEN  = 10;
localparam ANGBITS = 9;
localparam SIGBIN  = 10'd100;   // -> frequency code SIGBIN>>2 = 25

reg clk = 1'b0;
always #5 clk = ~clk;

reg rst = 1'b1;

reg        wr_en   = 1'b0;
reg [1:0]  wr_chan = 2'd0;
reg [9:0]  wr_addr = 10'd0;
reg [7:0]  wr_data = 8'd0;
reg        round_done = 1'b0;
reg        frame_tick = 1'b0;

reg  [ANGBITS-1:0] rd_addr = 0;
wire [7:0]         rd_len;
wire [7:0]         rd_frq;

df_amp #(
    .FFTLEN(FFTLEN), .ANGBITS(ANGBITS),
    .CH_E(0), .CH_N(1), .CH_W(2), .CH_S(3),
    .AMP_FLOOR(8'd128), .AMP_SHIFT(1), .DIR_MIN(11'd24), .STAGES(12), .CGUARD(10)
) dut (
    .i_clk(clk), .i_rst(rst),
    .i_wr_en(wr_en), .i_wr_chan(wr_chan), .i_wr_addr(wr_addr), .i_wr_data(wr_data),
    .i_round_done(round_done), .i_frame_tick(frame_tick),
    .i_rdClk(clk), .i_rdAddr(rd_addr), .o_rdLen(rd_len), .o_rdFrq(rd_frq)
);

reg [31:0] stim [0:NTEST-1];

task write_ch(input [1:0] ch, input [7:0] val);
begin
    @(posedge clk);
    wr_chan <= ch; wr_addr <= SIGBIN; wr_data <= val; wr_en <= 1'b1;
    @(posedge clk);
    wr_en <= 1'b0;
end
endtask

integer t, i;
integer nonzero;
initial begin
    $readmemh("stim.hex", stim);
    repeat (8) @(posedge clk);
    rst <= 1'b0;
    repeat (8) @(posedge clk);

    for (t = 0; t < NTEST; t = t + 1) begin
        // load this test's four channel amplitudes into the signal bin
        write_ch(2'd0, stim[t][31:24]);
        write_ch(2'd1, stim[t][23:16]);
        write_ch(2'd2, stim[t][15:8]);
        write_ch(2'd3, stim[t][7:0]);

        // one sweep
        @(posedge clk); round_done <= 1'b1;
        @(posedge clk); round_done <= 1'b0;
        repeat (4400) @(posedge clk);      // 1024 bins x 4 clocks + drain

        // swap so the filled half becomes the displayed half
        @(posedge clk); frame_tick <= 1'b1;
        @(posedge clk); frame_tick <= 1'b0;
        repeat (700) @(posedge clk);       // clear pass on the new fill half

        // dump the displayed half
        nonzero = 0;
        for (i = 0; i < (1<<ANGBITS); i = i + 1) begin
            rd_addr <= i[ANGBITS-1:0];
            @(posedge clk);
            @(posedge clk);
            if (rd_len != 8'd0) begin
                $display("TBL %0d %0d %0d %0d", t, i, rd_len, rd_frq);
                nonzero = nonzero + 1;
            end
        end
        $display("TESTDONE %0d %0d", t, nonzero);
    end
    $display("TB_DONE");
    $finish;
end

/* probe: every accepted bearing, plus the raw pipeline at the signal bin */
always @(posedge clk) if (dut.draw_ok)
    $display("DRAW t=%0d idx=%0d len=%0d mag=%0d ang=%0d", t, dut.ang_idx, dut.len_sat, dut.cd_mag, dut.cd_ang);
always @(posedge clk) if (dut.s5_vld && (dut.s5_amp > 8'd128))
    $display("S2 t=%0d amp=%0d x=%0d y=%0d", t, dut.s5_amp, $signed(dut.s5_x), $signed(dut.s5_y));
always @(posedge clk) if (dut.i_round_done)
    $display("ROUND t=%0d state=%0d fill=%0d", t, dut.state, dut.fill_sel);

endmodule
