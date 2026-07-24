`timescale 1ns / 1ps

module tb_cordic_vec;

localparam NVEC   = 792;
localparam XYW    = 16;
localparam STAGES = 12;
localparam LAT    = STAGES + 1;   // registers from i_x/i_y to o_mag/o_ang

reg clk = 1'b0;
always #5 clk = ~clk;

reg  [31:0] vecmem [0:NVEC-1];

reg                   valid = 1'b0;
reg  signed [XYW-1:0] x = 0, y = 0;
wire [XYW+1:0]        mag;
wire [15:0]           ang;
wire                  vld;

cordic_vec #(.XYW(XYW), .STAGES(STAGES), .GUARD(10)) dut (
    .i_clk(clk), .i_ce(1'b1), .i_valid(valid),
    .i_x(x), .i_y(y),
    .o_mag(mag), .o_ang(ang), .o_valid(vld)
);

/* Shadow delay line so each output is paired with the input that produced it.
   shadow[j] is j+1 registers deep, so the input matching a LAT-deep output is
   shadow[LAT-1]. If this is misaligned the angles come out visibly wrong, so
   it doubles as a latency check. */
reg [31:0] shadow [0:LAT-1];
integer k;
always @(posedge clk) begin
    shadow[0] <= {x, y};
    for (k = 0; k < LAT-1; k = k + 1)
        shadow[k+1] <= shadow[k];
end

integer i;
initial begin
    $readmemh("vectors.hex", vecmem);

    @(posedge clk);
    for (i = 0; i < NVEC; i = i + 1) begin
        x     <= vecmem[i][31:16];
        y     <= vecmem[i][15:0];
        valid <= 1'b1;
        @(posedge clk);
    end
    valid <= 1'b0;
    x <= 0; y <= 0;
    repeat (LAT + 4) @(posedge clk);
    $display("TB_DONE");
    $finish;
end

always @(posedge clk) begin
    if (vld)
        $display("RES %0d %0d %0d %0d",
                 $signed(shadow[LAT-1][31:16]), $signed(shadow[LAT-1][15:0]),
                 mag, ang);
end

endmodule
