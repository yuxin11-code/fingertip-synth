`timescale 1ns/1ps
module tb_curve_capture;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,tick=0,arm=0,mode_a=1,consumed=0,rd=0;
 reg signed[15:0] a=0,b=0,l=0,r=0;
 reg[7:0] address=0;
 wire ready,bank,rv;wire[15:0] x,y;
 reg[63:0] inputs[0:519];reg[31:0] expected[0:511];
 integer scene,n,i;reg previous_bank;
 viz_capture #(.LEGACY_PACKED(0),.LISS_POINTS(128)) dut(
  .clk(clk),.rst_n(rst_n),.frame_tick(tick),.sample_valid(1'b1),
  .wave_sample(l),.dry_sample(l),.wet_sample(r),.voice_a_sample(a),.voice_b_sample(b),
  .wave_decim(2'd0),.wave_arm(1'b0),.wave_consumed(1'b0),
  .liss_arm(arm),.liss_mode_a(mode_a),.liss_voice_count(2'd2),.liss_consumed(consumed),.liss_ready(ready),
  .adsr_arm(1'b0),.adsr_consumed(1'b0),.adsr_a(4'd0),.adsr_d(4'd0),.adsr_s(4'd0),.adsr_r(4'd0),
  .env_value(17'd0),.env_stage(3'd0),.wave_mem_rd_en(1'b0),.wave_mem_rd_addr(8'd0),
  .liss_mem_rd_en(rd),.liss_mem_rd_addr(address),.liss_mem_rd_x(x),.liss_mem_rd_y(y),
  .liss_mem_rd_valid(rv),.liss_mem_bank(bank),.adsr_mem_rd_en(1'b0),.adsr_mem_rd_addr(8'd0));
 initial begin
  $readmemh("capture_inputs.hex",inputs);$readmemh("capture_expected.hex",expected);
  repeat(5)@(negedge clk);rst_n=1;
  for(scene=0;scene<4;scene=scene+1)begin
   arm=0;tick=0;repeat(3)@(negedge clk);mode_a=(scene!=1);arm=1;
   for(n=0;n<130;n=n+1)begin
    {a,b,l,r}=inputs[scene*130+n];tick=1;@(negedge clk);tick=0;
    repeat(9)@(negedge clk);
   end
   wait(ready);@(negedge clk);
   if(scene>0 && bank==previous_bank)$fatal(1,"capture bank did not alternate");
   previous_bank=bank;
   for(i=0;i<128;i=i+1)begin
    address={bank,i[6:0]};rd=1;@(negedge clk);rd=0;
    if(!rv || {x,y}!==expected[scene*128+i])$fatal(1,"capture/FIR/gain/mapping scene=%0d point=%0d expected=%h got=%h",scene,i,expected[scene*128+i],{x,y});
    @(negedge clk);
   end
   repeat(10)@(negedge clk);
   if(!ready)$fatal(1,"capture not frozen for consumer");
   consumed=1;@(negedge clk);consumed=0;@(negedge clk);
   $display("PASS XY capture scene=%0d all128 coordinates/FIR/common gain/bank freeze",scene);
  end
  $display("PASS AB and LR mode sources/silence/signed extremes/128-point synchronous BSRAM capture");$finish;
 end
 initial begin repeat(20000)@(negedge clk);$fatal(1,"capture watchdog");end
endmodule
