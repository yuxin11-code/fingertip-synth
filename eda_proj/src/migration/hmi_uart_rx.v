// Independent 8N1 receiver. Fractional 16x tick, centre sampling, stop check.
module hmi_uart_rx #(parameter integer CLK_HZ=52500000, BAUD=115200)(
 input wire clk,rst_n,rx,output reg [7:0] data,
 output reg valid,frame_error);
 reg [1:0] sync;
 reg [31:0] acc;
 reg [1:0] state;
 reg [3:0] phase;
 reg [2:0] bitno;
 reg [7:0] shift;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin sync<=3;acc<=0;state<=0;phase<=0;bitno<=0;shift<=0;data<=0;valid<=0;frame_error<=0;end
  else begin
   sync<={sync[0],rx};valid<=0;frame_error<=0;
   if(acc>=CLK_HZ-BAUD*16) begin
    acc<=acc+BAUD*16-CLK_HZ;
    case(state)
     0:if(!sync[1])begin phase<=0;state<=1;end
     1:if(phase==7)begin phase<=0;if(!sync[1])begin state<=2;bitno<=0;end else state<=0;end else phase<=phase+1'b1;
     2:if(phase==15)begin
        phase<=0;shift[bitno]<=sync[1];
        if(bitno==7)state<=3;else bitno<=bitno+1'b1;
       end else phase<=phase+1'b1;
     3:if(phase==15)begin
        state<=0;phase<=0;
        if(sync[1])begin data<=shift;valid<=1;end else frame_error<=1;
       end else phase<=phase+1'b1;
    endcase
   end else acc<=acc+BAUD*16;
  end
 end
endmodule
