// Unsigned restoring division, one quotient bit per clock. No '/' datapath.
module serial_divider # (parameter integer W=36)(
 input wire clk,rst_n,start,input wire [W-1:0] numerator,denominator,
 output reg busy,done,output reg [W-1:0] quotient);
 reg [W-1:0] dividend,divisor;
 reg [W:0] remainder;
 reg [$clog2(W+1)-1:0] count;
 wire [W:0] trial={remainder[W-1:0],dividend[W-1]};
 wire fits=trial>={1'b0,divisor};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin busy<=0;done<=0;quotient<=0;dividend<=0;divisor<=1;remainder<=0;count<=0;end
  else begin
   done<=0;
   if(start && !busy)begin
    busy<=1;count<=W;dividend<=numerator;divisor<=(denominator==0)?{{(W-1){1'b0}},1'b1}:denominator;
    quotient<=0;remainder<=0;
   end else if(busy)begin
    remainder<=fits?trial-{1'b0,divisor}:trial;
    dividend<=dividend<<1;quotient<={quotient[W-2:0],fits};
    if(count==1)begin busy<=0;done<=1;end else count<=count-1'b1;
   end
  end
 end
endmodule
