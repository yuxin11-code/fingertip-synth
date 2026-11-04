`timescale 1ns/1ps
module tb_hmi_scaling;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;reg [15:0] slider=0,value=0;
 wire [16:0] q,a,s,p;
 wire [31:0] ra,rs;
 hmi_scale_exact #(.KIND(0)) qmap(slider,q);
 hmi_scale_exact #(.KIND(1)) amap(slider,a);
 hmi_scale_exact #(.KIND(2)) smap(slider,s);
 hmi_scale_exact #(.KIND(3)) pmap(slider,p);
 hmi_readback_scale #(.DIVISOR(4095)) adiv(clk,rst_n,value,ra);
 hmi_readback_scale #(.DIVISOR(32767)) sdiv(clk,rst_n,value,rs);
 integer i;
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  for(i=0;i<=1000;i=i+1)begin
   slider=i;#1;
   if(q!=(i*65536+500)/1000 || a!=1+(i*4095+500)/1000 ||
      s!=(i*32767+500)/1000 || p!=(i*15+500)/1000)$fatal(1,"mapping changed at %0d",i);
  end
  slider=65535;#1;if(q!=65536 || a!=4096 || s!=32767 || p!=15)$fatal(1,"clamp");
  for(i=0;i<=32767;i=i+1)begin
   @(negedge clk);value=i;repeat(70)@(negedge clk);
   if(rs!=(i*1000+16383)/32767)$fatal(1,"S readback %0d",i);
   if(i<=4095 && ra!=(i*1000+2047)/4095)$fatal(1,"A readback %0d",i);
  end
  $display("PASS exact 1001 slider mappings x4; all A/S readback values");$finish;
 end
endmodule
