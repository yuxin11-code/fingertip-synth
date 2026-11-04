`timescale 1ns/1ps
// Exact stereo PCM -> all 32 independent band values, not a single-peak test.
module tb_spectrum_pcm_oracle #(parameter integer SAMPLES=4096);
 reg clk=0,rst_n=0,tick=0;
 always #5 clk=~clk;
 reg signed [15:0] left=0,right=0;
 wire [5:0] addr;wire [11:0] mag,peak;wire valid,busy;
 wire [31:0] overruns;wire [10:0] cycles;
 spectrum #(.STEREO(1)) dut(.clk(clk),.rst_n(rst_n),.tick(tick),
  .sample(left),.sample_right(right),.fast(1'b0),.clk_aud(clk),
  .rst_n_aud(rst_n),.frame_strobe(tick),.addr(addr),.mag(mag),
  .peak(peak),.valid(valid),.busy(busy),.overrun_count(overruns),.cycles_last(cycles));
 integer input_fd,expect_fd,ok,l,r,i,seen=0,ea,em,ep,pub=0,nonzero=0,max_active=0;
 always @(negedge clk)if(valid)begin
  ok=$fscanf(expect_fd,"%d %d %d\n",ea,em,ep);
  if(ok!=3 || addr!==ea || mag!==em || peak!==ep)
   $fatal(1,"PCM oracle mismatch row=%0d band=%0d/%0d mag=%0d/%0d peak=%0d/%0d",seen,addr,ea,mag,em,peak,ep);
  if(mag>=5)nonzero=nonzero+1;
  seen=seen+1;
  if(addr==31)begin
   pub=pub+1;if(nonzero>max_active)max_active=nonzero;nonzero=0;
  end
 end
 initial begin
  input_fd=$fopen("pcm.txt","r");expect_fd=$fopen("oracle.txt","r");
  if(!input_fd || !expect_fd)$fatal(1,"missing PCM/oracle fixtures");
  repeat(5)@(negedge clk);rst_n=1;repeat(70)@(negedge clk);
  for(i=0;i<SAMPLES;i=i+1)begin
   ok=$fscanf(input_fd,"%d %d\n",l,r);if(ok!=2)$fatal(1,"short PCM fixture");
   @(negedge clk);left=l;right=r;tick=1;
   @(negedge clk);tick=0;
   repeat(1055)@(negedge clk);
   if(overruns!=0 || cycles>=1057)$fatal(1,"PCM overrun or deadline: %0d/%0d",overruns,cycles);
  end
  if(seen!=(SAMPLES/256)*32 || max_active<5)$fatal(1,"missing multi-column activity rows=%0d max_active=%0d",seen,max_active);
  $display("PASS bit-exact %0d stereo PCM samples; %0d band values; max simultaneous active=%0d; cycles=%0d; overruns=%0d",SAMPLES,seen,max_active,cycles,overruns);
  $fclose(input_fd);$fclose(expect_fd);$finish;
 end
endmodule
