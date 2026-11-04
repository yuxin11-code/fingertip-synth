// Adapted from E:/FPGA/instrument_v2(1)/instrument_v2/rtl/fx_chain.v.
// Parallel dry + stereo chorus + ping-pong delay + Freeverb returns.
// Synchronous BSRAM, signed DSP products, per-frame control snapshot and
// explicit wrap/scrub replace upstream out-of-range/unsigned warm-up logic.
`default_nettype none
module fx_chain #(parameter integer CLK_HZ=52500000)(
 input wire clk,rst_n,frame_tick,
 input wire signed [15:0] dry_l,dry_r,
 input wire rev_en,input wire [1:0] rev_mix,rev_decay,rev_damp,
 input wire dly_en,input wire [1:0] dly_mix,dly_time,dly_fb,
 input wire cho_en,input wire [1:0] cho_mix,cho_rate,cho_depth,
 output reg signed [15:0] wet_l,wet_r,
 output wire fx_active,ready,output reg busy,sample_valid
);
 (* syn_ramstyle="block_ram" *) reg signed [15:0] dmem[0:4095];
 (* syn_ramstyle="block_ram" *) reg signed [15:0] cmem[0:2047];
 reg initializing;reg [11:0] scrub;
 reg [10:0] dwr,cwr;
 reg [11:0] daddr,dwaddr;reg [10:0] caddr,cwaddr;
 reg signed [15:0] ddata,cdata,dwdata,cwdata;reg dwe,cwe;
 always @(posedge clk)begin
  ddata<=dmem[daddr];cdata<=cmem[caddr];
  if(initializing)begin dmem[scrub]<=0;if(!scrub[11])cmem[scrub[10:0]]<=0;end
  else begin if(dwe)dmem[dwaddr]<=dwdata;if(cwe)cmem[cwaddr]<=cwdata;end
 end
 reg [31:0] lfo_phase;reg signed [15:0] sine_q;
 (* rom_style="block" *) reg signed [15:0] sine[0:255];
 initial $readmemh("src/migration/fx_sine.hex",sine);
 always @(posedge clk)sine_q<=sine[lfo_phase[31:24]];
 function [31:0] rate_step;input [1:0] rate;begin case(rate)
 0:rate_step=112420;1:rate_step=190250;default:rate_step=285375;
 endcase end endfunction
 function [16:0] level;input [1:0] x;begin level={1'b0,x,14'd0};end endfunction
 function [10:0] delay_length;input [1:0] x;begin case(x)
 0:delay_length=410;1:delay_length=853;2:delay_length=1295;default:delay_length=1738;
 endcase end endfunction
 function signed [15:0] sat;input signed [47:0] x;begin
  sat=(x>32767)?16'sd32767:(x< -32768)?-16'sd32768:x[15:0];
 end endfunction
 reg [7:0] t;
 reg signed [15:0] input_l,input_r,dl,dr,cl0,cl1,cr0,cr1;
 reg [10:0] delay_n,off_l,off_r;
 reg [7:0] frac_l,frac_r;
 reg [16:0] rev_level,dly_level,cho_level,feedback;
 reg re,de,ce;
 reg [1:0] rev_decay_q,rev_damp_q;
 reg [4:0] depth;
 (* syn_dspstyle="dsp" *) reg signed [21:0] modulation;
 wire signed [24:0] offset_l_q8=25'sd384000+($signed(modulation)>>>7);
 wire signed [24:0] offset_r_q8=25'sd384000-($signed(modulation)>>>7);
 (* syn_dspstyle="dsp" *) reg signed [33:0] fb_l,fb_r;
 (* syn_dspstyle="dsp" *) reg signed [25:0] cp0,cp1,cp2,cp3;
 reg signed [17:0] chorus_l,chorus_r;
 (* syn_dspstyle="dsp" *) reg signed [35:0] chorus_product_l,chorus_product_r;
 (* syn_dspstyle="dsp" *) reg signed [33:0] delay_product_l,delay_product_r,rev_product_l,rev_product_r;
 reg rev_start;wire rev_ready,rev_done;wire signed [15:0] rev_l,rev_r;
 reg rev_complete;
 wire [15:0] rev_feedback=(rev_decay_q==0)?16'd45875:(rev_decay_q==1)?16'd49152:(rev_decay_q==2)?16'd52429:16'd56360;
 wire [15:0] rev_damping={rev_damp_q,14'd0};
 reverb u_reverb(.clk(clk),.rst_n(rst_n),.start(rev_start),.enable(re),
  .in_l(input_l),.in_r(input_r),.fb_q(rev_feedback),.damp_q(rev_damping),
  .ready(rev_ready),.done(rev_done),.wet_l(rev_l),.wet_r(rev_r));
 assign ready=!initializing && rev_ready;
 assign fx_active=rev_en|dly_en|cho_en;
 wire [10:0] delay_read=dwr-delay_n;
 wire signed [16:0] mono_input=$signed(input_l)+$signed(input_r);
 wire signed [39:0] sum_l=$signed(input_l)+(chorus_product_l>>>16)+(delay_product_l>>>16)+(rev_product_l>>>16);
 wire signed [39:0] sum_r=$signed(input_r)+(chorus_product_r>>>16)+(delay_product_r>>>16)+(rev_product_r>>>16);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   initializing<=1;scrub<=0;dwr<=0;cwr<=0;daddr<=0;caddr<=0;dwaddr<=0;cwaddr<=0;dwdata<=0;cwdata<=0;dwe<=0;cwe<=0;
   lfo_phase<=0;t<=0;busy<=0;sample_valid<=0;wet_l<=0;wet_r<=0;
   input_l<=0;input_r<=0;dl<=0;dr<=0;cl0<=0;cl1<=0;cr0<=0;cr1<=0;
   delay_n<=410;off_l<=1500;off_r<=1500;frac_l<=0;frac_r<=0;
   rev_level<=0;dly_level<=0;cho_level<=0;feedback<=0;re<=0;de<=0;ce<=0;
   rev_decay_q<=0;rev_damp_q<=0;depth<=0;modulation<=0;
   fb_l<=0;fb_r<=0;cp0<=0;cp1<=0;cp2<=0;cp3<=0;chorus_l<=0;chorus_r<=0;
   chorus_product_l<=0;chorus_product_r<=0;delay_product_l<=0;delay_product_r<=0;rev_product_l<=0;rev_product_r<=0;
   rev_start<=0;rev_complete<=0;
  end else begin
   sample_valid<=0;dwe<=0;cwe<=0;rev_start<=0;
   if(initializing)begin if(scrub==4095)initializing<=0;else scrub<=scrub+1'b1;end
   if(rev_done)rev_complete<=1;
   if(frame_tick && ready && !busy)begin
    busy<=1;t<=0;input_l<=dry_l;input_r<=dry_r;re<=rev_en;de<=dly_en;ce<=cho_en;
    rev_level<=rev_en?level(rev_mix):17'd0;dly_level<=dly_en?level(dly_mix):17'd0;
    cho_level<=cho_en?level(cho_mix):17'd0;feedback<=dly_en?level(dly_fb):17'd0;
    rev_decay_q<=rev_decay;rev_damp_q<=rev_damp;delay_n<=delay_length(dly_time);
    depth<=(cho_depth==0)?5'd0:(cho_depth==1)?5'd4:(cho_depth==2)?5'd8:5'd16;
    lfo_phase<=lfo_phase+rate_step(cho_rate);rev_complete<=0;
   end else if(busy)begin
    if(t!=120)t<=t+1'b1;
    case(t)
     0:begin modulation<=sine_q*$signed({1'b0,depth});rev_start<=1;end
     1:begin off_l<=offset_l_q8[18:8];frac_l<=offset_l_q8[7:0];off_r<=offset_r_q8[18:8];frac_r<=offset_r_q8[7:0];end
     2:begin daddr<={1'b0,delay_read};caddr<=cwr-off_l;end
     4:begin dl<=ddata;cl0<=cdata;daddr<={1'b1,delay_read};caddr<=cwr-off_l-1'b1;end
     6:begin dr<=ddata;cl1<=cdata;caddr<=cwr-off_r;end
     8:begin cr0<=cdata;caddr<=cwr-off_r-1'b1;end
     10:cr1<=cdata;
     11:begin
      fb_l<=dl*$signed({1'b0,feedback});fb_r<=dr*$signed({1'b0,feedback});
      cp0<=cl0*$signed(10'd256-{2'd0,frac_l});cp1<=cl1*$signed({2'd0,frac_l});
      cp2<=cr0*$signed(10'd256-{2'd0,frac_r});cp3<=cr1*$signed({2'd0,frac_r});
     end
     12:begin chorus_l<=(cp0+cp1)>>>8;chorus_r<=(cp2+cp3)>>>8;end
     13:begin dwe<=1;dwaddr<={1'b0,dwr};dwdata<=de?sat($signed(input_l)+(fb_r>>>16)):16'sd0;end
     15:begin dwe<=1;dwaddr<={1'b1,dwr};dwdata<=de?sat($signed(input_r)+(fb_l>>>16)):16'sd0;end
     17:begin cwe<=1;cwaddr<=cwr;cwdata<=ce?(mono_input>>>1):16'sd0;dwr<=dwr+1'b1;cwr<=cwr+1'b1;end
     18:begin
      chorus_product_l<=chorus_l*$signed({1'b0,cho_level});chorus_product_r<=chorus_r*$signed({1'b0,cho_level});
      delay_product_l<=dl*$signed({1'b0,dly_level});delay_product_r<=dr*$signed({1'b0,dly_level});
     end
     120:if(rev_complete)begin
      rev_product_l<=rev_l*$signed({1'b0,rev_level});rev_product_r<=rev_r*$signed({1'b0,rev_level});t<=121;
     end
     121:begin wet_l<=sat(sum_l);wet_r<=sat(sum_r);sample_valid<=1;busy<=0;t<=0;end
     default:;
    endcase
   end
  end
 end
endmodule
`default_nettype wire
