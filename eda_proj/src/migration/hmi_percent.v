// Background restoring divider, no long combinational division path.
module hmi_percent(input wire clk,rst_n,input wire [31:0] numerator,denominator,
 output reg [6:0] percent);
 reg [39:0] quotient,remainder;
 reg [31:0] divisor;
 reg [5:0] count;
 wire [39:0] trial={remainder[38:0],quotient[39]};
 wire subtract=trial>={8'd0,divisor};
 wire [39:0] next_q={quotient[38:0],subtract};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin quotient<=0;remainder<=0;divisor<=1;count<=0;percent<=0;end
  else if(count==0)begin
   quotient<=((numerator>denominator)?denominator:numerator)*40'd100;
   divisor<=(denominator==0)?32'd1:denominator;remainder<=0;count<=40;
  end else begin
   remainder<=subtract?trial-divisor:trial;quotient<=next_q;count<=count-1'b1;
   if(count==1)percent<=(next_q>100)?7'd100:next_q[6:0];
  end
 end
endmodule
