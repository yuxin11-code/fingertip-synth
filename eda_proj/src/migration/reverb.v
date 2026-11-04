// Port of instrument_v2/rtl/reverb.v: same 8 comb + 4 all-pass geometry.
// Corrected synchronous RAM latency, signed feedback, bounded pointers and
// deterministic synchronous RAM scrub. One complete 12-line pass per sample.
`default_nettype none
module reverb(
 input wire clk,rst_n,start,enable,
 input wire signed [15:0] in_l,in_r,
 input wire [15:0] fb_q,damp_q,
 output wire ready,output reg done,
 output reg signed [15:0] wet_l,wet_r
);
 (* syn_ramstyle="block_ram" *) reg signed [15:0] mem[0:24575];
 reg initializing;reg [14:0] scrub;
 reg [14:0] rdaddr,waddr;reg signed [15:0] rddata,wdata;reg we;
 assign ready=!initializing;
 always @(posedge clk)begin
  rddata<=mem[rdaddr];
  if(initializing)mem[scrub]<=0;else if(we)mem[waddr]<=wdata;
 end
 reg [10:0] wp[0:11];reg signed [15:0] lpm[0:7];
 reg [3:0] state,line;
 reg enabled;
 reg signed [15:0] dry_l,dry_r,tap,ap_l,ap_r;
 reg [16:0] damping,feedback,inverse_damping;
 (* syn_dspstyle="dsp" *) reg signed [33:0] product0,product1;
 reg signed [17:0] filtered;
 (* syn_dspstyle="dsp" *) reg signed [35:0] feedback_product;
 reg signed [19:0] comb_l,comb_r;
 wire signed [15:0] lp_previous=(line<8)?lpm[line[2:0]]:16'sd0;
 wire signed [17:0] inject=(line<4)?($signed(dry_l)>>>1):($signed(dry_r)>>>1);
 wire signed [17:0] ap_input=(line<10)?$signed(ap_l):$signed(ap_r);
 function [10:0] length_for;input [3:0] n;begin case(n)
 0:length_for=1116;1:length_for=1188;2:length_for=1260;3:length_for=1332;
 4:length_for=1139;5:length_for=1211;6:length_for=1283;7:length_for=1355;
 8:length_for=556;9:length_for=997;10:length_for=579;default:length_for=1020;
 endcase end endfunction
 function signed [15:0] saturate;input signed [47:0] x;begin
  saturate=(x>32767)?16'sd32767:(x< -32768)?-16'sd32768:x[15:0];
 end endfunction
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   initializing<=1;scrub<=0;rdaddr<=0;waddr<=0;wdata<=0;we<=0;
   state<=0;line<=0;enabled<=0;done<=0;wet_l<=0;wet_r<=0;
   dry_l<=0;dry_r<=0;tap<=0;ap_l<=0;ap_r<=0;damping<=0;feedback<=0;inverse_damping<=65536;
   product0<=0;product1<=0;filtered<=0;feedback_product<=0;comb_l<=0;comb_r<=0;
   for(i=0;i<12;i=i+1)wp[i]<=0;
   for(i=0;i<8;i=i+1)lpm[i]<=0;
  end else begin
   done<=0;we<=0;
   if(initializing)begin
    if(scrub==24575)initializing<=0;else scrub<=scrub+1'b1;
   end else case(state)
    0:if(start)begin
     enabled<=enable;dry_l<=enable?in_l:16'sd0;dry_r<=enable?in_r:16'sd0;
     damping<={1'b0,damp_q};inverse_damping<=17'd65536-{1'b0,damp_q};
     feedback<=enable?{1'b0,fb_q}:17'd0;comb_l<=0;comb_r<=0;line<=0;state<=1;
    end
    1:begin rdaddr<={line,11'd0}+{4'd0,wp[line]};state<=2;end
    2:state<=3;
    3:begin tap<=rddata;state<=4;end
    4:begin
     product0<=tap*$signed({1'b0,inverse_damping});
     product1<=lp_previous*$signed({1'b0,damping});state<=5;
    end
    5:begin filtered<=(product0+product1)>>>16;state<=6;end
    6:begin
     feedback_product<=(line<8)?filtered*$signed({1'b0,feedback}):tap*18'sd32768;
     state<=7;
    end
    7:begin
     waddr<={line,11'd0}+{4'd0,wp[line]};we<=1;
     wp[line]<=(wp[line]==length_for(line)-1'b1)?11'd0:wp[line]+1'b1;
     if(line<8)begin
      lpm[line[2:0]]<=saturate(filtered);
      wdata<=enabled?saturate(inject+(feedback_product>>>16)):16'sd0;
      if(line<4)comb_l<=comb_l+$signed(tap);else comb_r<=comb_r+$signed(tap);
     end else begin
      wdata<=enabled?saturate(ap_input+(feedback_product>>>16)):16'sd0;
      if(line<10)ap_l<=saturate($signed(tap)-ap_input);
      else ap_r<=saturate($signed(tap)-ap_input);
     end
     state<=8;
    end
    8:begin
     if(line==7)begin ap_l<=saturate(comb_l>>>2);ap_r<=saturate(comb_r>>>2);end
     if(line==11)state<=9;else begin line<=line+1'b1;state<=1;end
    end
    9:begin wet_l<=enabled?ap_l:16'sd0;wet_r<=enabled?ap_r:16'sd0;done<=1;state<=0;end
    default:state<=0;
   endcase
  end
 end
endmodule
`default_nettype wire
