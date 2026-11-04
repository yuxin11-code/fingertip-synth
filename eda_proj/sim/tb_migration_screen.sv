`timescale 1ns/1ps
module tb_migration_screen;
reg clk=0; always #5 clk=~clk;
reg rst_n=0; reg [1:0] inst_l=0,inst_r=1; reg [5:0] active_voices=17;
reg [16:0] volume_q16=65536; reg [3:0] adsr_a=6,adsr_d=4,adsr_s=12,adsr_r=5;
reg test_mode=1,strum_active=0;
wire uart_busy,uart_start; wire [7:0] uart_data; wire tx;
mig_screen_status #(.CLK_HZ(20000),.PERIOD_MS(10)) dut(.*);
mig_uart_tx #(.CLK_HZ(20000),.BAUD(1000)) uart(.clk(clk),.rst_n(rst_n),.start(uart_start),.data(uart_data),.busy(uart_busy),.tx(tx));
reg [7:0] received[0:12]; reg [7:0] crc; integer i,j,k;
initial begin
 repeat(3) @(negedge clk); rst_n=1;
 for(i=0;i<13;i=i+1) begin
  @(negedge tx); repeat(30) @(posedge clk); #1;
  for(j=0;j<8;j=j+1) begin
   received[i][j]=tx; repeat(20) @(posedge clk); #1;
  end
  if(tx!==1) $fatal(1,"UART stop bit");
  if(i==0) begin inst_l=2; inst_r=0; active_voices=1; volume_q16=0; adsr_a=1; end
 end
 if(received[0]!=8'haa || received[1]!=8'h55 || received[2]!=1 || received[3]!=8) $fatal(1,"UART header");
 if(received[4]!=0 || received[5]!=1 || received[6]!=17 || received[7]!=255 || received[8]!=8'h64 || received[9]!=8'hc5 || received[10]!=1) $fatal(1,"status snapshot/full volume %h %h %h",received[4],received[7],received[8]);
 crc=0;
 for(i=2;i<12;i=i+1) begin crc=crc^received[i]; for(k=0;k<8;k=k+1) crc=crc[7]?((crc<<1)^8'h07):(crc<<1); end
 if(crc!=received[12]) $fatal(1,"CRC mismatch");
 $display("PASS migration screen"); $finish;
end
initial begin #1000000; $fatal(1,"timeout"); end
endmodule
