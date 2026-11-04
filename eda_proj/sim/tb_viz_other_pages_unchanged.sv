`timescale 1ns/1ps
// Compare the pre-repair and repaired graphics producers cycle-for-cycle.
// Baseline module is extracted from before_full.zip, never reconstructed.
module tb_viz_other_pages_unchanged;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg [3:0] page=0;
 reg wr=0,ar=0,lr=0,dot=0;
 wire [1:0] valid,last,frame_end,wrd,ard,lrd,wc,ac,lc;
 wire [7:0] data[0:1],ca[0:1],la[0:1];
 reg [7:0] wave=0,adsr=0;reg wv=0,av=0,lv=0;
 reg [15:0] lx=0,ly=0;reg [31:0] count=0;wire ready=(count%3!=0);
 hmi_viz_tx #(.CLK_HZ(3600)) current(
  .clk(clk),.rst_n(rst_n),.page(page),.wave_ready(wr),.wave_bank(1'b0),
  .adsr_ready(ar),.adsr_bank(1'b0),.liss_ready(lr),.liss_bank(1'b0),
  .wave_data(wave),.adsr_data(adsr),.wave_valid(wv),.adsr_valid(av),
  .liss_x(lx),.liss_y(ly),.liss_valid(lv),.wave_rd(wrd[0]),.adsr_rd(ard[0]),.liss_rd(lrd[0]),
  .curve_addr(ca[0]),.liss_addr(la[0]),.wave_consumed(wc[0]),.adsr_consumed(ac[0]),.liss_consumed(lc[0]),
  .spec_valid(1'b0),.spec_addr(6'd0),.spec_mag(12'd0),.spec_peak(12'd0),
  .dot_valid(dot),.env_observe(20'h589ab),.valid(valid[0]),.last(last[0]),.frame_end(frame_end[0]),.data(data[0]),.ready(ready));
 baseline_hmi_viz_tx #(.CLK_HZ(3600)) baseline(
  .clk(clk),.rst_n(rst_n),.page(page),.wave_ready(wr),.wave_bank(1'b0),
  .adsr_ready(ar),.adsr_bank(1'b0),.liss_ready(lr),.liss_bank(1'b0),
  .wave_data(wave),.adsr_data(adsr),.wave_valid(wv),.adsr_valid(av),
  .liss_x(lx),.liss_y(ly),.liss_valid(lv),.wave_rd(wrd[1]),.adsr_rd(ard[1]),.liss_rd(lrd[1]),
  .curve_addr(ca[1]),.liss_addr(la[1]),.wave_consumed(wc[1]),.adsr_consumed(ac[1]),.liss_consumed(lc[1]),
  .spec_valid(1'b0),.spec_addr(6'd0),.spec_mag(12'd0),.spec_peak(12'd0),
  .dot_valid(dot),.env_observe(20'h589ab),.valid(valid[1]),.last(last[1]),.frame_end(frame_end[1]),.data(data[1]),.ready(ready));
 integer bytes_seen=0,p,xy_bytes=0;
 always @(posedge clk)begin
  count<=count+1;wv<=wrd[0];av<=ard[0];lv<=lrd[0];
  if(wrd[0])wave<=ca[0]%101;
  if(ard[0])adsr<=(ca[0]*3)%101;
  if(lrd[0])begin lx<=24+la[0]*3;ly<=64+(la[0]*7)%155;end
  if(wc[0])wr<=0;if(ac[0])ar<=0;if(lc[0])lr<=0;
 end
 always @(negedge clk)if(rst_n)begin
  if(valid[0]!==valid[1] || wrd[0]!==wrd[1] || ard[0]!==ard[1] || lrd[0]!==lrd[1] ||
     wc[0]!==wc[1] || ac[0]!==ac[1] || lc[0]!==lc[1])$fatal(1,"changed non-spectrum handshake page=%0d",page);
  if(valid[0] && ready)begin
   if(data[0]!==data[1] || last[0]!==last[1] || frame_end[0]!==frame_end[1])$fatal(1,"changed non-spectrum byte page=%0d",page);
   bytes_seen=bytes_seen+1;if(page==4)xy_bytes=xy_bytes+1;
  end
 end
 initial begin
  repeat(5)@(negedge clk);rst_n=1;wr=1;repeat(1500)@(negedge clk);
  page=2;wr=1;repeat(1500)@(negedge clk);
  page=4;lr=1;repeat(10000)@(negedge clk);
  page=5;ar=1;dot=1;@(negedge clk);dot=0;repeat(1500)@(negedge clk);
  for(p=6;p<=9;p=p+1)begin page=p;repeat(100)@(negedge clk);end
  if(xy_bytes!=562 || bytes_seen<800)$fatal(1,"insufficient protected-page coverage");
  $display("PASS non-spectrum graphics cycle/byte equality against backup: bytes=%0d XY=%0d",bytes_seen,xy_bytes);$finish;
 end
endmodule
