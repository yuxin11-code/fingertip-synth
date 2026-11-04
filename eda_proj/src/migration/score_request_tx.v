// One request per accepted button press. Existing score is not invalidated.
// Response remains the existing AA 55 START/NOTE/END stream on BLE_RX.
module score_request_tx #(
 parameter integer CLK_HZ=52500000,BAUD=115200,COOLDOWN_CLKS=CLK_HZ*3
)(input wire clk,rst_n,request,inhibit,output wire tx,output wire busy,
  output wire accepted);
 localparam integer W=(COOLDOWN_CLKS<2)?1:$clog2(COOLDOWN_CLKS+1);
 reg [W-1:0] cooldown;
 reg [1:0] state;
 reg [2:0] index;
 reg start;
 reg [7:0] data;
 wire uart_busy;
 assign busy=(state!=0 || cooldown!=0);
 // Expose the actual handshake, not every touch pulse, for the red/green UI.
 assign accepted=request && !inhibit && state==0 && cooldown==0;
 mig_uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) uart(
  .clk(clk),.rst_n(rst_n),.start(start),.data(data),.tx(tx),.busy(uart_busy));
 function [7:0] message_byte;
  input [2:0] n;
  case(n)
   0:message_byte="S";1:message_byte="C";2:message_byte="O";
   3:message_byte="R";4:message_byte="E";5:message_byte="?";
   default:message_byte=8'h0a;
  endcase
 endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin cooldown<=0;state<=0;index<=0;start<=0;data<=0;end
  else begin
   start<=0;
   if(cooldown!=0)cooldown<=cooldown-1'b1;
   case(state)
    0:if(accepted)begin
      index<=0;state<=1;cooldown<=COOLDOWN_CLKS;
     end
    1:if(!uart_busy)begin data<=message_byte(index);start<=1;state<=2;end
    2:if(uart_busy)state<=3;
    3:if(!uart_busy)begin
      if(index==6)state<=0;
      else begin index<=index+1'b1;state<=1;end
     end
   endcase
  end
 end
endmodule
