`timescale 1ns/1ps
module tb_real_adsr;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,frame_tick=0,adsr_consumed=0;
 reg [16:0] env_value=0;
 reg [2:0] env_stage=0;
 wire adsr_ready,adsr_mem_bank,adsr_point_valid;
 wire [15:0] adsr_point_x,adsr_point_y;
 wire [2:0] adsr_point_stage;
 viz_capture #(.FS_TICKS(3),.LEGACY_PACKED(0),.REAL_ADSR(1)) dut(
  .clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.sample_valid(1'b1),
  .wave_sample(16'sd0),.dry_sample(16'sd0),.wet_sample(16'sd0),
  .voice_a_sample(16'sd0),.voice_b_sample(16'sd0),.wave_decim(2'd0),
  .wave_arm(1'b0),.wave_consumed(1'b0),.liss_arm(1'b0),
  .liss_mode_a(1'b0),.liss_voice_count(2'd0),.liss_consumed(1'b0),
  .adsr_arm(1'b1),.adsr_consumed(adsr_consumed),.adsr_a(4'd0),
  .adsr_d(4'd0),.adsr_s(4'd0),.adsr_r(4'd0),
  .env_value(env_value),.env_stage(env_stage),
  .wave_ready(),.wave_data(),.wave_mem_rd_en(1'b0),.wave_mem_rd_addr(8'd0),
  .wave_mem_rd_data(),.wave_mem_rd_valid(),.wave_mem_bank(),
  .liss_valid(),.liss_index(),.liss_x(),.liss_y(),.liss_done(),
  .liss_mem_rd_en(1'b0),.liss_mem_rd_addr(8'd0),.liss_mem_rd_x(),
  .liss_mem_rd_y(),.liss_mem_rd_valid(),.liss_mem_bank(),.liss_ready(),
  .adsr_ready(adsr_ready),.adsr_data(),.adsr_mem_rd_en(1'b0),
  .adsr_mem_rd_addr(8'd0),.adsr_mem_rd_data(),.adsr_mem_rd_valid(),
  .adsr_mem_bank(adsr_mem_bank),.adsr_point_valid(adsr_point_valid),
  .adsr_point_x(adsr_point_x),.adsr_point_y(adsr_point_y),
  .adsr_point_stage(adsr_point_stage));
 task tick;begin @(negedge clk);frame_tick=1;@(negedge clk);frame_tick=0;end endtask
 task consume;begin @(negedge clk);adsr_consumed=1;@(negedge clk);adsr_consumed=0;end endtask
 integer i;
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  env_value=65536;env_stage=1;
  repeat(3)tick();
  if(!adsr_point_valid || adsr_point_stage!=1)$fatal(1,"attack stage not sampled");
  wait(adsr_ready);@(negedge clk);
  for(i=0;i<127;i=i+1)if(dut.adsr_mem[{adsr_mem_bank,i[6:0]}]!==0)
   $fatal(1,"synthetic or uninitialized history point %0d",i);
  if(dut.adsr_mem[{adsr_mem_bank,7'd127}]!==100)$fatal(1,"amplitude not captured");
  consume();env_value=32768;env_stage=4;
  repeat(3)tick();
  if(!adsr_point_valid || adsr_point_stage!=4)$fatal(1,"release stage not sampled");
  wait(adsr_ready);@(negedge clk);
  if(dut.adsr_mem[{adsr_mem_bank,7'd126}]!==100 ||
     dut.adsr_mem[{adsr_mem_bank,7'd127}]!==50)
   $fatal(1,"real history failed: %0d %0d",dut.adsr_mem[{adsr_mem_bank,7'd126}],dut.adsr_mem[{adsr_mem_bank,7'd127}]);
  $display("PASS real ADSR amplitude history and stages");$finish;
 end
endmodule
