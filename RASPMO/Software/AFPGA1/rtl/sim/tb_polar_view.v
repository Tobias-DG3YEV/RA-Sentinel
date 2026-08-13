`timescale 1ns / 1ps

/* Geometry check for polar_view: renders two frames into a small pane and
   prints every lit pixel, so a reference model can confirm that
//   frame 0 - a uniform angle table draws a disc of the right radius
//   frame 1 - a table populated only near 90deg draws a ray pointing UP
   which together pin down the radius scaling and the angle convention. */
module tb_polar_view;

localparam PW = 128, PH = 128, RMAX = 48;
localparam H_ACTIVE = 128, H_TOTAL = 160;
localparam V_ACTIVE = 128, V_TOTAL = 140;

reg clk = 1'b0;
always #5 clk = ~clk;

reg [11:0] h = 0, v = 0;
reg [2:0]  frame = 0;
reg        rst = 1'b1;
initial begin
    repeat (8) @(posedge clk);
    rst <= 1'b0;
end

wire de = (h < H_ACTIVE) && (v < V_ACTIVE);
wire vs = (v >= 132) && (v < 134);          // positive polarity, as 1080p
wire hs = (h >= 132) && (h < 140);

always @(posedge clk) begin
    if (h == H_TOTAL-1) begin
        h <= 0;
        if (v == V_TOTAL-1) begin
            v <= 0;
            frame <= frame + 3'd1;
        end
        else v <= v + 1;
    end
    else h <= h + 1;
end

/* Behavioural angle table, registered read to match the module's contract. */
reg [7:0] tblA [0:511];
reg [7:0] tblB [0:511];
wire [8:0] angAddr;
reg  [7:0] angLen;
always @(posedge clk)
    angLen <= (frame == 3'd2) ? tblA[angAddr] :
              (frame == 3'd3) ? tblB[angAddr] : 8'd0;

/* Frequency code, one fixed value per frame - the two ENDS of the ramp, so the
   check is on rendered pixels and covers the whole path: table -> the register
   that has to stay in step with the length -> freqmap -> the output mux. Both
   ends matter: the low one is the code an empty/cleared table entry carries, so
   a plumbing bug that zeroes the code still produces a plausible blue ray, and
   only the violet frame would catch it. */
reg [7:0] angFrq;
always @(posedge clk)
    angFrq <= (frame == 3'd2) ? 8'd0 :      // blue,   (0,0,255)
              (frame == 3'd3) ? 8'd255 :    // violet, (255,0,255)
                                8'd128;     // unused; those frames draw no ray

wire        act, shd;
wire [7:0]  pr, pg, pb;

polar_view #(
    .REG_X0(0), .REG_Y0(0), .REG_W(PW), .REG_H(PH),
    .R_MAX(RMAX), .STAGES(12), .CGUARD(10)
) dut (
    .i_pixClk(clk), .i_rst(rst),
    .i_video_hs(hs), .i_video_vs(vs), .i_video_de(de),
    .o_angAddr(angAddr), .i_angLen(angLen), .i_angFrq(angFrq),
    .o_active(act), .o_shade(shd), .o_r(pr), .o_g(pg), .o_b(pb)
);

integer i;
initial begin
    for (i = 0; i < 512; i = i + 1) begin
        tblA[i] = 8'd24;                       // uniform -> disc
        tblB[i] = ((i >= 126) && (i <= 130)) ? 8'd40 : 8'd0;  // ~90deg -> ray up
    end
end

/* Report every CLAIMED pixel, deliberately NOT filtered on a non-black colour.
   o_active is an alpha mask: top.v blends the indicator over channel 4's
   spectrum wherever it is high, so a pixel claimed but drawn black would punch
   a black hole in that spectrum. Printing the black ones lets check_polar.py
   fail on them instead of them being invisible to the regression - which is
   what happened while o_active still meant "in the pane".

   The renderer's own active_x/active_y are the authority on which pixel a
   colour belongs to, so sample them from the DUT rather than re-deriving from
   h/v and risking agreeing with a bug. */
always @(posedge clk) begin
    if (act)
        $display("PX %0d %0d %0d %0d %0d %0d",
                 frame, dut.active_x, dut.active_y, pr, pg, pb);

    /* The shade mask - the disc top.v darkens the spectra under - reported for
       one frame only, since it is R_MAX^2*pi pixels every frame and its shape
       does not depend on the angle table. A drawn pixel must always be a shaded
       one, so this stream has to cover the PX stream above. */
    if (shd && frame == 3'd2)
        $display("SH %0d %0d", dut.active_x, dut.active_y);
end

initial begin
    // let frame 0 and frame 1 both render fully
    repeat (H_TOTAL * V_TOTAL * 5 + 64) @(posedge clk);
    $display("TB_DONE");
    $finish;
end

endmodule
