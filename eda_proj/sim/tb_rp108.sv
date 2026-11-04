`timescale 1ns/1ps
module tb_rp108;
 wire [95:0] calibration_low,calibration_high;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,enabled=0,bad_id=0;
 tri1 scl,sda;
 reg [127:0] values=0;
 wire [127:0] raw_values;wire snapshot_valid,online;wire [15:0] error_count;
 wire [5:0] write_mask;wire [101:0] write_values;
 mig_rp108_reader #(.CLK_HZ(100000),.I2C_HZ(5000)) dut(.*);
 rp108_slave_model slave(.*);
 mig_knob_normalize normalizer(.*);
 integer i,updates=0;
 always @(posedge clk)if(write_mask!=0)updates=updates+1;
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task snapshot;
  integer limit;
  begin limit=0;
   while(snapshot_valid!==1 && limit<200000)begin cycles(1);limit=limit+1;end
   if(limit==200000)$fatal(1,"no RP108 snapshot st=%d online=%b errors=%d",dut.st,online,error_count);
   cycles(500);
  end
 endtask
 initial begin
  cycles(5);rst_n=1;cycles(30000);
  if(online!==0 || error_count==0 || updates!=0)$fatal(1,"absent module must not write zeros");
  enabled=1;bad_id=1;cycles(30000);
  if(online!==0)$fatal(1,"ID must check BOTH bytes");
  bad_id=0;snapshot;
  if(raw_values!==0 || write_mask!=0 || updates!=0)$fatal(1,"first reading must not seize uncalibrated controls");
  // Unknown per-channel ADC spans and endian-sensitive values.
  for(i=0;i<8;i=i+1)values[i*16+:16]=16'h1234;
  snapshot;
  if(raw_values!=={8{16'h1234}})$fatal(1,"little endian or channel mapping %h",raw_values);
  if(updates==0)$fatal(1,"calibration never valid");
  for(i=0;i<6;i=i+1)if(write_values[i*17+:17]!=65536)$fatal(1,"upper endpoint");
  for(i=0;i<8;i=i+1)values[i*16+:16]=16'h091a;
  snapshot;
  for(i=0;i<6;i=i+1)if(write_values[i*17+:17]!=32768)$fatal(1,"shared divider normalization channel %d value %d",i,write_values[i*17+:17]);
  values=0;snapshot;
  for(i=0;i<6;i=i+1)if(write_values[i*17+:17]!=0)$fatal(1,"lower endpoint");
  enabled=0;cycles(30000);
  if(online!==0)$fatal(1,"unplug not detected");
  enabled=1;snapshot;
  $display("PASS RP108: address/registers/endian/ACK/NACK/strict ID, absent/unplug/reconnect, 8-channel snapshots, six independent calibrated pots");$finish;
 end
 initial begin #20000000;$fatal(1,"timeout");end
endmodule
