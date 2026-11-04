// A transmitted byte is not proof of a live display. Only validated native
// page/touch responses refresh this watchdog; boot always invalidates it.
module mig_hmi_link #(
 parameter integer CLK_HZ=52500000,TIMEOUT_CLKS=CLK_HZ*6
)(
 input wire clk,rst_n,screen_reset,response_valid,
 output reg online,lost
);
 localparam integer WIDTH=(TIMEOUT_CLKS<2)?1:$clog2(TIMEOUT_CLKS);
 reg [WIDTH-1:0] age;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin age<=0;online<=0;lost<=0;end
  else begin
   lost<=0;
   if(screen_reset)begin age<=0;online<=0;lost<=online;end
   else if(response_valid)begin age<=0;online<=1;end
   else if(online)begin
    if(age==TIMEOUT_CLKS-1)begin age<=0;online<=0;lost<=1;end
    else age<=age+1'b1;
   end else age<=0;
  end
 end
endmodule
