`timescale 1ns/1ps
module tb_spectrum_2khz #(parameter integer START_BAND=0,END_BAND=31,RELEASE_TEST=1);
 reg clk=0,rst_n=0,tick=0;always #5 clk=~clk;
 reg signed[15:0] left=0,right=0;
 wire[5:0] addr;wire[11:0] mag,peak;wire valid,busy;
 wire[31:0] overrun;wire[10:0] cycles;
 spectrum #(.BINS(32),.N(256),.STEREO(1)) dut(.clk(clk),.rst_n(rst_n),.tick(tick),
  .sample(left),.sample_right(right),.fast(1'b0),.clk_aud(clk),.rst_n_aud(rst_n),.frame_strobe(tick),
  .addr(addr),.mag(mag),.peak(peak),.valid(valid),.busy(busy),.overrun_count(overrun),.cycles_last(cycles));
 integer levels[0:31];integer expected_addr=0,publishes=0,band,j,n,i,maxband,maxlevel,fd,ok;
 real f,phase;integer a0,a1;
 always @(negedge clk)if(valid)begin
  if(addr!=expected_addr || mag>100 || peak>100 || ^mag===1'bx)$fatal(1,"invalid band/publish");
  levels[addr]=mag;expected_addr=(addr==31)?0:addr+1;
  if(addr==31)publishes=publishes+1;
 end
 task reset_bank;begin
  rst_n=0;tick=0;repeat(5)@(negedge clk);rst_n=1;
  expected_addr=0;publishes=0;for(j=0;j<32;j=j+1)levels[j]=0;
  repeat(70)@(negedge clk);
 end endtask
 task sample_pair(input integer l,input integer r);begin
  @(negedge clk);left=l;right=r;tick=1;
  @(negedge clk);tick=0;
  repeat(1055)@(negedge clk);
  if(overrun || cycles>1057)$fatal(1,"analyzer misses audio frame");
 end endtask
 initial begin
  fd=$fopen("centers.txt","r");if(!fd)$fatal(1,"missing generated centers");
  for(band=0;band<32;band=band+1)begin
   ok=$fscanf(fd,"%f\n",f);if(ok!=1)$fatal(1,"center input");
   if(band>=START_BAND && band<=END_BAND)begin
   reset_bank();
   n=$rtoi(12.0*49667.3583984375/f);if(n<3072)n=3072;
   for(i=0;i<n;i=i+1)begin
    phase=6.283185307179586*f*i/49667.3583984375;
    sample_pair($rtoi(7000*$sin(phase)),-$rtoi(7000*$sin(phase)));
   end
   maxlevel=-1;maxband=-1;
   for(j=0;j<32;j=j+1)if(levels[j]>maxlevel)begin maxlevel=levels[j];maxband=j;end
   if(maxband!=band || maxlevel<20)$fatal(1,"real center response f=%f target=%0d got=%0d level=%0d",f,band,maxband,maxlevel);
   $display("PASS real PCM band=%0d center=%0.6fHz level=%0d opposite_phase_stereo cycles=%0d",band,f,maxlevel,cycles);
   end
  end
  $fclose(fd);
  // The envelope must release to zero; the IIR may not retain a spurious peak.
  if(RELEASE_TEST)begin
   for(i=0;i<32000;i=i+1)sample_pair(0,0);
   for(j=0;j<32;j=j+1)if(levels[j]!=0)$fatal(1,"silence did not release band=%0d level=%0d",j,levels[j]);
   $display("PASS silence release for all32 states");
  end
  $display("PASS real PCM centers %0d..%0d/stereo anti-cancellation/0 overrun/100%% real PCM",START_BAND,END_BAND);$finish;
 end
endmodule
