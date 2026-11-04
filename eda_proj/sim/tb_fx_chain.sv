`timescale 1ns/1ps
module tb_fx_chain;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,frame_tick=0;
 reg signed [15:0] dry_l=0,dry_r=0;
 reg rev_en=0,dly_en=0,cho_en=0;
 reg [1:0] rev_mix=2,rev_decay=2,rev_damp=1;
 reg [1:0] dly_mix=2,dly_time=0,dly_fb=2;
 reg [1:0] cho_mix=2,cho_rate=3,cho_depth=3;
 wire signed [15:0] wet_l,wet_r;
 wire fx_active,ready,busy,sample_valid;
 fx_chain dut(.*);
 integer mode,count,n,fd,nonzero=0,difference=0;
 string filename;
 real angle;
 reg signed [15:0] expected_l,expected_r;
 initial begin
  if(!$value$plusargs("MODE=%d",mode))mode=0;
  filename=$sformatf("../results/ui512_fx/fx_%0d.txt",mode);
  fd=$fopen(filename,"w");if(fd==0)$fatal(1,"cannot open FX output");
  case(mode)
   0:count=512;
   1:begin count=30000;rev_en=1;end
   2:begin count=15000;dly_en=1;end
   3:begin count=30000;cho_en=1;end
   default:$fatal(1,"unknown mode");
  endcase
  repeat(4)@(negedge clk);rst_n=1;
  wait(ready);
  for(n=0;n<count;n=n+1)begin
   @(negedge clk);
   if(mode==3)begin
    angle=6.283185307179586*440.0*n/49667.3583984375;
    expected_l=$rtoi(7000.0*$sin(angle));expected_r=expected_l;
   end else begin expected_l=(n==0)?16'sd12000:16'sd0;expected_r=expected_l;end
   dry_l=expected_l;dry_r=expected_r;frame_tick=1;
   @(negedge clk);frame_tick=0;
   wait(sample_valid);
   if(mode==0 && (wet_l!==expected_l || wet_r!==expected_r))
    $fatal(1,"bypass mismatch sample=%0d got=%0d/%0d expected=%0d/%0d",n,wet_l,wet_r,expected_l,expected_r);
   if(n>1 && (wet_l!=0 || wet_r!=0))nonzero=nonzero+1;
   if(wet_l!=expected_l || wet_r!=expected_r)difference=difference+1;
   $fwrite(fd,"%0d %0d\n",wet_l,wet_r);
  end
  $fclose(fd);
  if(mode!=0 && (nonzero==0 || difference==0))$fatal(1,"FX has no output mode=%0d",mode);
  $display("PASS fx_chain mode=%0d samples=%0d nonzero=%0d difference=%0d",mode,count,nonzero,difference);
  $finish;
 end
endmodule
