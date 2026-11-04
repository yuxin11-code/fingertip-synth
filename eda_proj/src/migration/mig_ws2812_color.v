// Single-pixel GRB driver. Latch the complete color between frames.
module mig_ws2812_color #(parameter integer CLK_HZ=52500000)(
 input wire clk,rst_n,input wire [23:0] color,output reg data_out);
 localparam integer RESET_CYCLES=CLK_HZ/2500;
 reg sending;reg [15:0] reset_count;reg [6:0] bit_cycle;
 reg [4:0] bit_index;reg [23:0] shift_data;
 wire [6:0] high_cycles=shift_data[bit_index]?7'd37:7'd18;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin sending<=0;reset_count<=0;bit_cycle<=0;bit_index<=23;shift_data<=0;data_out<=0;end
  else if(!sending)begin
   data_out<=0;
   if(reset_count==RESET_CYCLES-1)begin
    reset_count<=0;shift_data<=color;bit_index<=23;bit_cycle<=0;sending<=1;data_out<=1;
   end else reset_count<=reset_count+1'b1;
  end else begin
   if(bit_cycle==high_cycles-1'b1)data_out<=0;
   if(bit_cycle==65)begin
    bit_cycle<=0;
    if(bit_index==0)begin sending<=0;reset_count<=0;bit_index<=23;data_out<=0;end
    else begin bit_index<=bit_index-1'b1;data_out<=1;end
   end else bit_cycle<=bit_cycle+1'b1;
  end
 end
endmodule
