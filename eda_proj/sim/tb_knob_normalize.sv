`timescale 1ns/1ps
module tb_knob_normalize;
 wire [95:0] calibration_low,calibration_high;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,snapshot_valid=0;reg [127:0] raw_values=0;
 wire [5:0] write_mask;wire [101:0] write_values;
 wire [5:0] reverse_mask;wire [101:0] reverse_values;
 mig_knob_normalize dut(.*);
 mig_knob_normalize #(.REVERSE_MASK(6'b101010)) reversed(
  .clk(clk),.rst_n(rst_n),.snapshot_valid(snapshot_valid),.raw_values(raw_values),
  .write_mask(reverse_mask),.write_values(reverse_values));
 integer lo[0:5],hi[0:5],sample[0:5];
 integer i,j,expected;
 reg [5:0] observed;
 task send;
  begin
   @(negedge clk);snapshot_valid=1;
   @(negedge clk);snapshot_valid=0;observed=0;
   repeat(250)begin @(negedge clk);if(write_mask!=0)observed=write_mask;end
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  for(i=0;i<6;i=i+1)begin
   lo[i]=(i==5)?0:1000+13*i;hi[i]=(i==5)?65535:lo[i]+500+97*i;
   raw_values[i*16+:16]=lo[i];
  end
  send;if(observed!=0)$fatal(1,"uncalibrated takeover");
  for(i=0;i<6;i=i+1)raw_values[i*16+:16]=lo[i]+31;
  send;if(observed!=0)$fatal(1,"minimum span noise rejection");
  for(i=0;i<6;i=i+1)raw_values[i*16+:16]=hi[i];
  send;if(observed!=63)$fatal(1,"all channels calibrated");
  for(j=0;j<20;j=j+1)begin
   for(i=0;i<6;i=i+1)begin
    sample[i]=lo[i]+((j*137+i*53)%(hi[i]-lo[i]+1));
    raw_values[i*16+:16]=sample[i];
   end
   send;
   for(i=0;i<6;i=i+1)begin
    // Use a 64-bit reference for the full 16-bit input span.
    expected=(64'(sample[i]-lo[i])*65536)/(hi[i]-lo[i]);
    if(write_values[i*17+:17]!=expected)$fatal(1,"normalization ch=%d got=%d expected=%d",i,write_values[i*17+:17],expected);
    if(reverse_values[i*17+:17]!=(i%2?65536-expected:expected))$fatal(1,"direction mask channel %d",i);
   end
  end
  $display("PASS normalization: independent unknown spans, noise threshold, 120 interior points, full 16-bit span, direction masks");$finish;
 end
endmodule
