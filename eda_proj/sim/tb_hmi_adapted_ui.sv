`timescale 1ns/1ps
module tb_hmi_adapted_ui;
 parameter integer SYNTH_MODE=1;
 `include "hmi_defs.vh"
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,cmd_valid=0,page_valid=0;reg [7:0] cmd=0;
 reg [15:0] value=0,page_id=0;
 reg [HMI_TX_FIELD_COUNT*32-1:0] fields=0;
 wire tx;
 hmi_tx #(.CLK_HZ(1843200),.FIELD_COUNT(HMI_TX_FIELD_COUNT),.SYNTH_MODE(SYNTH_MODE)) sender(
  .clk(clk),.rst_n(rst_n),.cmd_valid(cmd_valid),.cmd(cmd),.value(value),.fields(fields),
  .page_valid(page_valid),.page_id(page_id),.screen_reset(1'b0),
  .aux_valid(1'b0),.aux_last(1'b0),.aux_data(8'd0),.tx(tx));
 wire [7:0] data;wire valid,frame_error;
 hmi_uart_rx #(.CLK_HZ(1843200)) monitor(.clk(clk),.rst_n(rst_n),.rx(tx),.data(data),.valid(valid),.frame_error(frame_error));
 reg [7:0] packet[0:31];reg [31:0] tail=0;
 reg [2:0] visibility=0,seen=0;integer n=0,latest=-1,idx,j;
 integer stream;
 initial begin
  stream=$fopen($sformatf("../results/hmi_fixes_20261102/hmi_adapted_ui_%0d_raw.bin",SYNTH_MODE),"wb");
  if(stream==0)$fatal(1,"cannot open adapted UI stream");
 end
 always @(negedge clk)if(rst_n)begin
  if(frame_error)$fatal(1,"UI UART framing");
  if(valid)begin
   $fwrite(stream,"%c",data);
   packet[n]=data;n=n+1;tail={tail[23:0],data};
   if(tail==32'hcc33c33c)begin
    if(n!=7 && {packet[3],packet[4]}==5)begin
     if(packet[2]==8'h03)begin
      idx={packet[5],packet[6]}-120;
      if(n!=22 || idx<0 || idx>2)$fatal(1,"visibility tuple length/target");
      if({packet[8],packet[9]}!=5 || {packet[10],packet[11]}!=62+idx ||
         {packet[13],packet[14]}!=5 || {packet[15],packet[16]}!=100+idx ||
         packet[7]>1 || packet[12]!=(packet[7]==0) || packet[17]!=(packet[7]==0))
       $fatal(1,"visibility tuple mapping");
      visibility[idx]=packet[7];seen[idx]=1;
     end else if(packet[2]==8'h10 && {packet[5],packet[6]}==102)begin
      if(SYNTH_MODE==1)begin
       if(n==14 && {packet[7],packet[8],packet[9]}=="50%")latest=500;
       else if(n==14 && {packet[7],packet[8],packet[9]}=="75%")latest=750;
       else if(n==15 && {packet[7],packet[8],packet[9],packet[10]}=="100%")latest=1000;
       else $fatal(1,"Sustain is not 50%%/75%%/100%%");
      end else begin
       if(n!=15)$fatal(1,"legacy sustain width changed");
       latest=0;for(j=7;j<11;j=j+1)latest=latest*10+packet[j]-48;
      end
     end
    end
    n=0;tail=0;
   end else if(n>=32)$fatal(1,"oversize UI packet");
  end
 end
 task cycles(input integer count);repeat(count)@(negedge clk);endtask
 task set_s(input integer v);integer wait_cycles;begin
  fields[HMI_FIELD_P5_C102_ADSR_VALUE_2*32+:32]=v;wait_cycles=0;
  while(latest!=v && wait_cycles<250000)begin cycles(1);wait_cycles=wait_cycles+1;end
  if(latest!=v)$fatal(1,"sustain update missing mode=%0d",SYNTH_MODE);
 end endtask
 initial begin
  fields[HMI_FIELD_P5_C102_ADSR_VALUE_2*32+:32]=500;
  fields[HMI_FIELD_P5_C120_ADSR_DISABLED_0*32+:32]=(SYNTH_MODE==1);
  fields[HMI_FIELD_P5_C122_ADSR_DISABLED_2*32+:32]=(SYNTH_MODE==1);
  cycles(4);rst_n=1;cmd_valid=1;cmd=8'h1f;value=5;page_valid=1;page_id=5;
  cycles(1);cmd_valid=0;page_valid=0;
  set_s(500);wait(seen==7);
  if(visibility!==(SYNTH_MODE==1?3'b101:3'b000))$fatal(1,"plucked/legacy disabled state");
  set_s(750);set_s(1000);
  if(SYNTH_MODE==1)begin
   seen=0;
   fields[HMI_FIELD_P5_C120_ADSR_DISABLED_0*32+:32]=0;
   fields[HMI_FIELD_P5_C121_ADSR_DISABLED_1*32+:32]=1;
   fields[HMI_FIELD_P5_C122_ADSR_DISABLED_2*32+:32]=0;
   wait(seen==7);if(visibility!==3'b010)$fatal(1,"violin disabled state");
  end
  wait(sender.state==0 && !sender.busy);cycles(1);$fclose(stream);
  $display("PASS adapted UI mode=%0d: sustain formatting and atomic overlay/slider/value visibility",SYNTH_MODE);$finish;
 end
 initial begin cycles(1500000);$fatal(1,"adapted UI watchdog");end
endmodule
