`timescale 1ns/1ps
module tb_hmi_polling;
 `include "hmi_defs.vh"
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,page_valid=0,cmd_valid=0;
 wire tx; wire [7:0] data; wire valid,frame_error;
 reg [HMI_TX_FIELD_COUNT*32-1:0] fields=0;
 hmi_tx #(.CLK_HZ(1843200),.FIELD_COUNT(HMI_TX_FIELD_COUNT),.QUERY_CLKS(100000)) sender(
  .clk(clk),.rst_n(rst_n),.cmd_valid(cmd_valid),.cmd(8'h1f),.value(16'd0),.fields(fields),
  .page_valid(page_valid),.page_id(16'd0),.screen_reset(1'b0),
  .aux_valid(1'b0),.aux_last(1'b0),.aux_data(8'd0),.tx(tx));
 hmi_uart_rx #(.CLK_HZ(1843200)) monitor(.clk(clk),.rst_n(rst_n),.rx(tx),
  .data(data),.valid(valid),.frame_error(frame_error));
 integer n=0,queries=0,writes=0,last_queries,last_writes;
 reg [7:0] packet[0:31];reg [31:0] tail=0;
 always @(negedge clk)begin
  page_valid=0;cmd_valid=0;
  if(rst_n)begin
   if(frame_error)$fatal(1,"polling UART framing");
   if(valid)begin
    packet[n]=data;n=n+1;tail={tail[23:0],data};
    if(tail==32'hcc33c33c)begin
     if(n==7 && packet[0]==8'haa && packet[1]==8'hb1 && packet[2]==8'h01)begin
      queries=queries+1;page_valid=1;cmd_valid=1;
     end else writes=writes+1;
     n=0;tail=0;
    end else if(n>=32)$fatal(1,"polling oversize frame");
   end
  end
 end
 initial begin
  repeat(4)@(posedge clk);#1;rst_n=1;
  repeat(500000)@(posedge clk);
  last_queries=queries;last_writes=writes;
  if(!sender.page_known || last_writes<10)$fatal(1,"initial page did not settle");
  repeat(450000)@(posedge clk);
  if(queries-last_queries<3)$fatal(1,"known page no longer polled");
  if(writes!=last_writes)$fatal(1,"same-page heartbeat redrew unchanged fields");
  $display("PASS continuous page polling: queries=%0d settled_writes=%0d additional_writes=%0d",queries,last_writes,writes-last_writes);
  $finish;
 end
endmodule
