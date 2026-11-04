// Exact round(v*1000 / DIVISOR), refreshed in the background every 34 clocks.
// Only one compare/subtract per clock; never part of the audio datapath.
module hmi_readback_scale #(parameter integer DIVISOR=4095)(
 input wire clk,rst_n,input wire [15:0] value,output reg [31:0] scaled);
 reg [31:0] numerator,quotient,remainder;
 reg [5:0] count;
 wire [31:0] trial={remainder[30:0],quotient[31]};
 wire subtract=trial>=DIVISOR;
 wire [31:0] next_q={quotient[30:0],subtract};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin numerator<=0;quotient<=0;remainder<=0;count<=0;scaled<=0;end
  else if(count==0)begin numerator<=value*32'd1000+DIVISOR/2;count<=33;end
  else if(count==33)begin quotient<=numerator;remainder<=0;count<=32;end
  else begin
   quotient<=next_q;remainder<=subtract?trial-DIVISOR:trial;count<=count-1'b1;
   if(count==1)scaled<=next_q;
  end
 end
endmodule
