`timescale 1ns/1ps
module tb_spectrum32_transport #(parameter integer CLK_HZ=1843200);
 localparam PERIOD=CLK_HZ/194;
 `define HMI_DEFINE_TX_TABLE
 `include "hmi_defs.vh"
 `undef HMI_DEFINE_TX_TABLE
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg cmd_valid=0;reg[7:0] cmd=0;reg[15:0] value=0;
 reg repeat_liss=0;
 wire[3:0] page;wire tx,av,al,ar,afe;wire[7:0] ad;
 reg[HMI_TX_FIELD_COUNT*32-1:0] fields=0;
 reg sv=0;reg[5:0] sa=0;reg[11:0] sm=0;wire[11:0] sp=sm+10;
 reg lr=0,lv=0;reg[15:0] lx=0,ly=0;
 wire lrd,lc;wire[7:0] la;
 integer reads=0;
 hmi_tx #(.CLK_HZ(CLK_HZ),.FIELD_COUNT(HMI_TX_FIELD_COUNT),.LINK_DIAGNOSTICS(1)) txer(
  .clk(clk),.rst_n(rst_n),.cmd_valid(cmd_valid),.cmd(cmd),.value(value),.fields(fields),
  .page_valid(1'b0),.screen_reset(1'b0),.page_id(16'd0),.tx(tx),.current_page(page),
  .byte_count(),.aux_valid(av),.aux_last(al),
`ifndef OLD_DESIGN
  .aux_frame_end(afe),
`endif
  .aux_data(ad),.aux_ready(ar));
 hmi_viz_tx #(.CLK_HZ(CLK_HZ)) dut(.clk(clk),.rst_n(rst_n),.page(page),
  .wave_ready(1'b0),.wave_bank(1'b0),.adsr_ready(1'b0),.adsr_bank(1'b0),
  .liss_ready(lr),.liss_bank(1'b0),.wave_data(8'd0),.adsr_data(8'd0),
  .wave_valid(1'b0),.adsr_valid(1'b0),.liss_x(lx),.liss_y(ly),.liss_valid(lv),
  .wave_rd(),.adsr_rd(),.liss_rd(lrd),.curve_addr(),.liss_addr(la),
  .wave_consumed(),.adsr_consumed(),.liss_consumed(lc),
  .spec_valid(sv),.spec_addr(sa),.spec_mag(sm),.spec_peak(sp),.dot_valid(1'b0),.env_observe(20'd0),
  .valid(av),.last(al),
`ifndef OLD_DESIGN
  .frame_end(afe),
`endif
  .data(ad),.ready(ar));
 always @(posedge clk)begin
  lv<=lrd;
  if(lrd)begin lx<=24+la*3;ly<=64+(la*7)%155;reads=reads+1;end
  // Same one-clock ready clearing latency as the real capture producer.
  if(lc)lr<=0;else if(repeat_liss && !lr)lr<=1;
 end
 wire[7:0] bd;wire bv,fe;
 hmi_uart_rx #(.CLK_HZ(CLK_HZ)) monitor(.clk(clk),.rst_n(rst_n),.rx(tx),.data(bd),.valid(bv),.frame_error(fe));
 integer peak_id=201;
 integer cycle=0,off,gen,fd,n=0,frames=0,sweeps=0,points=0,bar=101,g=-1,cid,pid,v,tuple;
 integer start_liss=0,last_liss=0,first_bar=0,max_spec_age=0,begin_liss=0,wire_liss=0,xy_point=0,xy_chunk=0;
 real spec_ms,liss_ms,control_ms,entry_ms;integer bank_stamp[0:2];integer max_age=0,age=0;
 initial begin bank_stamp[0]=0;bank_stamp[1]=0;bank_stamp[2]=0;end
 always @(posedge clk)if(rst_n && dut.spec_capture && sa==31)bank_stamp[dut.spec_write_bank]=cycle;
 integer spec_wire=0,control_start=0,control_end=0;

 reg[7:0] packet[0:255];reg[31:0] tail=0;
 initial fd=$fopen("uart.bin","wb");
 always @(negedge clk)begin
  cycle=cycle+1;sv=0;
  if(page!=3)begin first_bar=0;bar=101;peak_id=201;g=-1;end
  if(dut.spec_sending && dut.spec_capture && dut.spec_write_bank==dut.spec_read_bank)
   $fatal(1,"writer overwrites active UART bank");
  if(rst_n)begin
   off=cycle%PERIOD;gen=cycle/PERIOD;
   if(off<704 && off%22==0)begin sv=1;sa=off/22;sm=5+(gen%4)*4+sa*2;end
  end
  if(av && ar && dut.pos==0 && dut.op==8'h10 && page==3 && dut.index==0 && !dut.spec_sending)begin
   spec_wire=cycle;
`ifdef OLD_DESIGN
   age=cycle-bank_stamp[dut.spec_read_bank];
`else
   age=cycle-bank_stamp[dut.spec_latest_bank];
   if(age>PERIOD+64)$fatal(1,"stale spectrum snapshot at UART header age=%0d",age);
`endif
   if(age>max_age)max_age=age;
  end
  if(av && ar && dut.pos==0 && dut.op==8'h50 && page==4 && points==0)wire_liss=cycle;
  if(fe)$fatal(1,"UART framing error");
  if(bv)begin
   $fwrite(fd,"%c",bd);packet[n]=bd;n=n+1;tail={tail[23:0],bd};
   if(tail==32'hcc33c33c)begin
    frames=frames+1;
    if(packet[0]!=8'haa || (packet[1]!=8'hb1 && packet[1]!=8'h50 && packet[1]!=8'h6a && packet[1]!=8'h66))$fatal(1,"bad packet header");
    pid={packet[3],packet[4]};cid={packet[5],packet[6]};

    if(packet[1]==8'hb1 && packet[2]==8'h10 && pid==3 && page==3 && cid>=101 && cid<=132)begin
     `ifdef OLD_DESIGN
     if(n!=15)$fatal(1,"legacy spectrum bytes=%0d",n);
`else
     if(n!=15)$fatal(1,"manufacturer single-control spectrum packet bytes=%0d",n);
`endif
     for(tuple=3;tuple<n-4;tuple=tuple+8)begin
      cid={packet[tuple+2],packet[tuple+3]};
      if({packet[tuple],packet[tuple+1]}!=3 || cid!=bar)$fatal(1,"spectrum ID order");
      v=packet[tuple+7]-(cid-101)*2;
      if(cid==101)begin g=v;if(first_bar!=0)$display("METRIC spectrum_group_interval_ms=%0.3f",1000.0*(cycle-first_bar)/CLK_HZ);first_bar=cycle;end
      if(v!=g)$fatal(1,"mixed/stale band data cid=%0d got=%0d generation=%0d",cid,v,g);
      if(cid==132)begin sweeps=sweeps+1;bar=101;$display("METRIC spectrum_sweep=%0d wire_ms=%0.3f",sweeps,1000.0*(cycle-spec_wire)/CLK_HZ);end else bar=bar+1;
     end
    end
    if(packet[1]==8'hb1 && packet[2]==8'h28 && pid==3)$fatal(1,"removed peak traffic");
    if(packet[1]==8'h50)begin xy_point=0;xy_chunk=0;if(points==0)start_liss=cycle;end
    if(packet[1]==8'h66)begin
     if(n!=((xy_chunk<2)?246:46))$fatal(1,"native XY packet bytes=%0d",n);
     for(tuple=2;tuple<n-4;tuple=tuple+4)begin
      if({packet[tuple],packet[tuple+1]}!=24+xy_point*3 ||
         {packet[tuple+2],packet[tuple+3]}!=64+(xy_point*7)%155)$fatal(1,"XY RAM/read pipeline");
      xy_point=xy_point+1;
     end
     xy_chunk=xy_chunk+1;
     if(xy_point==128)begin points=points+128;last_liss=cycle;end
     else xy_point=xy_point-1;
    end
    if(packet[2]==8'h10 && pid==4 && cid==65 && packet[7]==1 && control_start!=0 && control_end==0)control_end=cycle;
    n=0;tail=0;
   end else if(n>250)$fatal(1,"packet runaway");
  end
 end
 task change(input[15:0] p);begin
  @(negedge clk);cmd=8'h1f;value=p;cmd_valid=1;@(negedge clk);cmd_valid=0;
 end endtask
 initial begin
  repeat(10)@(negedge clk);rst_n=1;change(3);
  wait(sweeps==2);wait(n==0);change(4);begin_liss=cycle;lr=1;
  wait(lc);wait(points==128);wait(n==0);
  entry_ms=1000.0*(last_liss-begin_liss)/CLK_HZ;
  liss_ms=entry_ms;
  $display("METRIC liss_publish_to_last_ms=%0.3f liss_first_to_last_ms=%0.3f",liss_ms,1000.0*(last_liss-wire_liss)/CLK_HZ);
  liss_ms=1000.0*(last_liss-wire_liss)/CLK_HZ;
  if(reads!=130)$fatal(1,"128 points plus two shared endpoints expected: reads=%0d",reads);
`ifndef TRANSPORT_ONLY
  repeat_liss=1;
  repeat(CLK_HZ/5)@(negedge clk);
  control_start=cycle;fields[98*32+:32]=1;
  while(control_end==0 && cycle-control_start<CLK_HZ*3/10)@(negedge clk);
  control_ms=(control_end==0)?300.0:1000.0*(control_end-control_start)/CLK_HZ;
  $display("METRIC control_change_to_UART_ms=%0.3f observed=%0d",control_ms,control_end!=0);
  repeat_liss=0;
`endif
  change(3);wait(sweeps==4);wait(n==0);
  $fclose(fd);
  $display("METRIC maximum_spectrum_snapshot_age_ms=%0.3f",1000.0*max_age/CLK_HZ);
  if(entry_ms>80.0)$fatal(1,"PAGE_ENTRY picture exceeds 80 ms: %0.3f",entry_ms);
  if(control_ms>150.0)$fatal(1,"CONTROL_STARVATION exceeds 150 ms: %0.3f ms",control_ms);
  if(liss_ms>65.0)$fatal(1,"LATENCY liss frame exceeds 65 ms target: %0.3f ms",liss_ms);
  $display("PASS 32 independent solid bars UART transport sweeps=%0d XY_points=%0d UART_frames=%0d illegal=0",sweeps,points,frames);
  $finish;
 end
 initial begin repeat(CLK_HZ)@(negedge clk);$fatal(1,"watchdog points=%0d sweeps=%0d state=%0d",points,sweeps,dut.state);end
endmodule
