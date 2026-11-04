`timescale 1ns/1ps
module tb_migration_cdc;
reg src_clk=0,dst_clk=0,rst_n=0;
always #3 src_clk=~src_clk; always #11 dst_clk=~dst_clk;
reg [7:0] count=0; wire [15:0] src_data={count,~count}; wire [15:0] dst_data;
mig_cdc_snapshot #(.WIDTH(16)) dut(.*);
always @(negedge src_clk) if(rst_n) count<=count+1;
integer changes=0; reg [15:0] last=0;
always @(negedge dst_clk) if(rst_n && dst_data!=0) begin
 if(dst_data[7:0]!==~dst_data[15:8]) $fatal(1,"torn CDC word");
 if(last!=dst_data) changes=changes+1;
 last=dst_data;
end
initial begin
 #50; rst_n=1; #10000;
 if(changes<20) $fatal(1,"CDC stalled");
 rst_n=0; #100; if(dst_data!==0) $fatal(1,"CDC reset"); rst_n=1; #500;
 $display("PASS migration cdc"); $finish;
end
endmodule
