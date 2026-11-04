// Frame-budget counters for the additive engine and HMI readback.
module mig_engine_diagnostics(
 input wire clk,rst_n,frame_tick,busy,sample_valid,
 output reg [11:0] last_frame_cycles,
 output reg [31:0] deadline_count,sample_count
);
 reg [11:0] frame_cycles;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   frame_cycles<=0;last_frame_cycles<=0;deadline_count<=0;sample_count<=0;
  end else begin
   if(frame_tick)begin
    frame_cycles<=0;
    if(busy)deadline_count<=deadline_count+1'b1;
   end else if(frame_cycles!=12'hfff)frame_cycles<=frame_cycles+1'b1;
   if(sample_valid)begin
    last_frame_cycles<=frame_cycles;
    sample_count<=sample_count+1'b1;
   end
  end
 end
endmodule
