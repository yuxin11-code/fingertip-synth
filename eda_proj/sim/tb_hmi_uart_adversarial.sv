`timescale 1ns/1ps
// Exercise the fractional UART at the actual 52.5 MHz system frequency.
module tb_hmi_uart_adversarial;
 reg clk=0;always #9.523809524 clk=~clk;
 reg rst_n=0,rx=1;
 wire [7:0] data;wire valid,frame_error;
 hmi_uart_rx dut(.clk(clk),.rst_n(rst_n),.rx(rx),.data(data),.valid(valid),.frame_error(frame_error));
 reg [7:0] expected[0:1023];integer wr=0,rd=0,errors=0,expected_errors=0;
 always @(negedge clk)if(rst_n)begin
  if(valid)begin
   if(rd>=wr || data!==expected[rd])$fatal(1,"UART mismatch index=%0d got=%h expected=%h",rd,data,expected[rd]);
   rd=rd+1;
  end
  if(frame_error)errors=errors+1;
 end
 task uart(input [7:0] b,input realtime bit_ns,input bit good_stop);begin
  if(good_stop)begin expected[wr]=b;wr=wr+1;end else expected_errors=expected_errors+1;
  rx=0;#(bit_ns);
  for(integer k=0;k<8;k=k+1)begin rx=b[k];#(bit_ns);end
  rx=good_stop;#(bit_ns);rx=1;
 end endtask
 integer k,seed=32'h5120cafe;reg [31:0] random_word;
 initial begin
  repeat(6)@(negedge clk);rst_n=1;#31000;
  // Short noise pulses must not produce bytes.
  repeat(12)begin rx=0;#300;rx=1;#13000;end
  for(k=0;k<256;k=k+1)uart(k[7:0],8680.555556,1);
  for(k=0;k<128;k=k+1)begin
   random_word=$random(seed);uart(random_word[7:0],8510.348584,1);
   random_word=$random(seed);uart(random_word[7:0],8857.709751,1);
  end
  uart(8'h55,8680.555556,0);#30000;
  for(k=0;k<64;k=k+1)uart(k[7:0]^8'ha5,8680.555556,1);
  #100000;
  if(rd!=wr || errors!=expected_errors)$fatal(1,"UART recovery counts received=%0d/%0d errors=%0d/%0d",rd,wr,errors,expected_errors);
  $display("PASS actual-clock UART: bytes=%0d, +/-2%% baud, back-to-back, glitches, stop error and recovery",rd);$finish;
 end
 initial begin #100000000;$fatal(1,"UART watchdog");end
endmodule
