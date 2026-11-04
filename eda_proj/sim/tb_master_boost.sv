`timescale 1ns/1ps
module tb_master_boost;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,test_atten=0;
 reg signed [39:0] panel_a=0,panel_b=0;
 reg [16:0] master=0,blend=32768,balance=32768;
 wire signed [15:0] pcm_left,pcm_right,old_left,old_right;
 mig_stereo_mixer #(.EQUAL_POWER(1),.BOOST_MASTER(1)) dut(.*);
 mig_stereo_mixer #(.EQUAL_POWER(1)) baseline(.clk(clk),.rst_n(rst_n),
  .panel_a(panel_a),.panel_b(panel_b),.master(master),.blend(blend),
  .balance(balance),.test_atten(test_atten),.pcm_left(old_left),.pcm_right(old_right));
 function automatic signed [15:0] expected(input integer channel,input integer boosted);
  longint signed ga,gb,gain,mixed,x,pan;
  begin
   ga=(blend==0)?65536:(blend==32768)?46341:0;
   gb=(blend==0)?0:(blend==32768)?46341:65536;
   mixed=(($signed(panel_a)*ga)>>>16)+(($signed(panel_b)*gb)>>>16);
   gain=test_atten?(master>>3):master;
   if(boosted)gain=gain+(gain>>1);
   x=((mixed>>>2)*gain)>>>16;
   pan=channel?((balance<32768)?balance*2:65536):((balance>32768)?(65536-balance)*2:65536);
   x=(x*pan)>>>16;
   expected=(x>32767)?32767:(x< -32768)?-32768:x;
  end
 endfunction
 integer checks=0,i,j,k,m;
 task verify;
  begin
   repeat(12)@(negedge clk);
   if(pcm_left!==expected(0,1) || pcm_right!==expected(1,1))
    $fatal(1,"boost mismatch A=%0d B=%0d master=%0d got=%0d/%0d expected=%0d/%0d",
     panel_a,panel_b,master,pcm_left,pcm_right,expected(0,1),expected(1,1));
   if(old_left!==expected(0,0) || old_right!==expected(1,0))$fatal(1,"legacy gain changed");
   checks=checks+1;
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  for(i=0;i<3;i=i+1)for(j=0;j<3;j=j+1)for(k=0;k<2;k=k+1)begin
   blend=i*32768;balance=j*32768;test_atten=k;
   for(m=0;m<=32;m=m+1)begin
    master=m*2048;panel_a=(m&1)?-4000:4000;panel_b=(m&2)?-8000:8000;verify;
   end
  end
  // Every 16-partial amplitude sum <=0.9 in the current additive ROM.
  // Each voice's sample magnitude <=3702, including 16 signed-floor terms.
  // Both 16-voice panels at that bound must fit the 16-bit output at 1.5x.
  blend=32768;balance=32768;master=65536;test_atten=0;
  panel_a=59232;panel_b=59232;verify;
  if(pcm_left>=32767 || pcm_right>=32767)$fatal(1,"32-voice bound clips");
  panel_a=-59232;panel_b=-59232;verify;
  if(pcm_left<=-32768)$fatal(1,"negative 32-voice bound clips");
  // Effects may reach full scale; preserve the final safety limiter.
  panel_a=131068;panel_b=131068;verify;
  if(pcm_left!=32767)$fatal(1,"positive limiter");
  panel_a=-131072;panel_b=-131072;verify;
  if(pcm_left!=-32768)$fatal(1,"negative limiter");
  master=0;verify;if(pcm_left!==0 || pcm_right!==0)$fatal(1,"not exact mute");
  panel_a=4000;panel_b=8000;master=65535;verify;
  $display("PASS master boost: %0d cases, 1.5x Q16, knob endpoints, odd inputs, old gain preserved, 32-voice bounds and limiter",checks);
  $finish;
 end
 initial begin #1000000;$fatal(1,"watchdog");end
endmodule
