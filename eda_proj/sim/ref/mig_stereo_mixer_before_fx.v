// Center retains the original gain of BOTH sources/channels; extremes mute one.
module mig_stereo_mixer_before_fx #(parameter integer EQUAL_POWER=0)(
 input wire clk,rst_n,
 input wire signed [39:0] panel_a,panel_b,
 input wire [16:0] master,blend,balance,
 input wire test_atten,
 output reg signed [15:0] pcm_left,pcm_right
);
 function [16:0] sin_gain;
 input [4:0] idx;
 begin case(idx)
   5'd0:sin_gain=17'd0;
   5'd1:sin_gain=17'd6424;
   5'd2:sin_gain=17'd12785;
   5'd3:sin_gain=17'd19024;
   5'd4:sin_gain=17'd25080;
   5'd5:sin_gain=17'd30893;
   5'd6:sin_gain=17'd36410;
   5'd7:sin_gain=17'd41576;
   5'd8:sin_gain=17'd46341;
   5'd9:sin_gain=17'd50660;
   5'd10:sin_gain=17'd54491;
   5'd11:sin_gain=17'd57798;
   5'd12:sin_gain=17'd60547;
   5'd13:sin_gain=17'd62714;
   5'd14:sin_gain=17'd64277;
   5'd15:sin_gain=17'd65220;
   5'd16:sin_gain=17'd65536;
  default:sin_gain=17'd65536;
 endcase end
 endfunction
 function [16:0] equal_gain;
 input [16:0] position;
 reg [16:0] a,b;
 reg [28:0] interpolation;
 begin
  a=sin_gain({1'b0,position[15:12]});
  b=sin_gain({1'b0,position[15:12]}+5'd1);
  interpolation=(b-a)*position[11:0];
  equal_gain=position[16]?17'd65536:(a+(interpolation>>12));
 end endfunction
 // Separate interpolation from the wide panel multiply. This adds one
 // system-clock of control latency and removes their combined critical path.
 reg [16:0] equal_a,equal_b;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin equal_a<=17'd46341;equal_b<=17'd46341;end
  else begin equal_a<=equal_gain(17'd65536-blend);equal_b<=equal_gain(blend);end
 end
 wire [16:0] a_gain=EQUAL_POWER?equal_a:
  ((blend<=32768)?17'd65536:((17'd65536-blend)<<1));
 wire [16:0] b_gain=EQUAL_POWER?equal_b:
  ((blend>=32768)?17'd65536:(blend<<1));
 wire [16:0] l_gain=(balance<=32768)?17'd65536:((17'd65536-balance)<<1);
 wire [16:0] r_gain=(balance>=32768)?17'd65536:(balance<<1);
 wire [16:0] volume=test_atten?(master>>3):master;
 wire signed [57:0] a_product=panel_a*$signed({1'b0,a_gain});
 wire signed [57:0] b_product=panel_b*$signed({1'b0,b_gain});
 reg signed [42:0] mixed;
 reg signed [60:0] master_product;
 reg signed [44:0] mono;
 reg signed [62:0] left_product,right_product;
 function signed [15:0] clip;
 input signed [62:0] sample;
 begin
  if(sample>32767) clip=16'sd32767;
  else if(sample< -32768) clip=-16'sd32768;
  else clip=sample[15:0];
 end endfunction
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin mixed<=0;master_product<=0;mono<=0;
   left_product<=0;right_product<=0;pcm_left<=0;pcm_right<=0; end
  else begin
   mixed<=($signed(a_product)>>>16)+($signed(b_product)>>>16);
   master_product<=(mixed>>>2)*$signed({1'b0,volume});
   mono<=master_product>>>16;
   left_product<=mono*$signed({1'b0,l_gain});
   right_product<=mono*$signed({1'b0,r_gain});
   pcm_left<=clip(left_product>>>16); pcm_right<=clip(right_product>>>16);
  end
 end
endmodule
