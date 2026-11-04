`timescale 1ns/1ps
module tb_hmi_startup;
 reg clk=0;always #5 clk=~clk;reg rst_n=0;
 wire tx;wire [3:0] page;wire [31:0] count;
 `include "hmi_defs.vh"
 hmi_tx #(.CLK_HZ(1843200),.FIELD_COUNT(HMI_TX_FIELD_COUNT)) sender(.clk(clk),.rst_n(rst_n),.cmd_valid(1'b0),.cmd(8'd0),.value(16'd0),.fields({HMI_TX_FIELD_COUNT{32'd388}}),.aux_valid(1'b0),.aux_last(1'b0),.aux_data(8'd0),.tx(tx),.current_page(page),.byte_count(count));
 wire [7:0] data;wire valid,error;
 hmi_uart_rx #(.CLK_HZ(1843200)) monitor(.clk(clk),.rst_n(rst_n),.rx(tx),.data(data),.valid(valid),.frame_error(error));
 reg [7:0] packet[0:31];reg [31:0] tail=0;integer n=0,queries=0;
 always @(negedge clk)if(valid)begin
  packet[n]=data;n=n+1;tail={tail[23:0],data};
  if(tail==32'hcc33c33c)begin if(n==7 && packet[1]==8'hb1 && packet[2]==1)queries=queries+1;n=0;tail=0;end
 end
 initial begin repeat(5)@(negedge clk);rst_n=1;repeat(15000)@(negedge clk);
  if(queries==0)$fatal(1,"no current-screen query after FPGA boot: late screen/page cannot synchronize");
  $display("PASS startup current-screen query");$finish;
 end
endmodule
