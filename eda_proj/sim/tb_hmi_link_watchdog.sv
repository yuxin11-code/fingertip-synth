`timescale 1ns/1ps
module tb_hmi_link_watchdog;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,screen_reset=0,response_valid=0;wire online,lost;
 mig_hmi_link #(.CLK_HZ(100),.TIMEOUT_CLKS(60)) dut(.*);
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task response;begin response_valid=1;cycles(1);response_valid=0;end endtask
 initial begin
  cycles(4);rst_n=1;cycles(100);
  if(online || lost)$fatal(1,"TX/idle cannot prove a connected screen");
  response();if(!online)$fatal(1,"valid reply did not establish link");
  cycles(59);if(!online || lost)$fatal(1,"premature timeout");
  cycles(1);if(online || !lost)$fatal(1,"disconnect not detected");
  cycles(1);if(lost)$fatal(1,"lost must be one clock");
  response();if(!online)$fatal(1,"reconnect failed");
  cycles(50);response();cycles(50);if(!online)$fatal(1,"reply did not refresh watchdog");
  screen_reset=1;response_valid=1;cycles(1);screen_reset=0;response_valid=0;
  if(online || !lost)$fatal(1,"boot must invalidate the previous link");
  cycles(1);response();if(!online)$fatal(1,"post-boot reply failed");
  $display("PASS HMI link: offline until RX, refresh, exact timeout, one-cycle lost, reconnect, reset priority");$finish;
 end
endmodule
