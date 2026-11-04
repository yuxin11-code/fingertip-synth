`timescale 1ns/1ps
module rp108_slave_model(inout wire scl,sda,input wire enabled,
 input wire [127:0] values,input wire bad_id);
 reg pull_low=0;assign sda=pull_low?1'b0:1'bz;
 reg [7:0] addr,regno,readaddr;reg [15:0] value;
 integer j;reg ack;
 task recv_byte(output reg [7:0] data);
  integer b;
  begin for(b=7;b>=0;b=b-1)begin @(posedge scl);data[b]=sda;end end
 endtask
 task send_ack(input bit yes);
  begin @(negedge scl);pull_low=yes;@(posedge scl);@(negedge scl);pull_low=0;end
 endtask
 task send_byte(input [7:0] data);
  integer b;
  begin
   if(scl!==0)@(negedge scl);
   for(b=7;b>=0;b=b-1)begin
    pull_low=!data[b];@(posedge scl);
    if(b!=0)@(negedge scl);
   end
  end
 endtask
 task recv_ack(output reg yes);
  begin @(negedge scl);pull_low=0;@(posedge scl);yes=!sda;end
 endtask
 initial forever begin
  @(negedge sda);
  if(scl===1 && enabled)begin
   recv_byte(addr);
   if(addr==8'h40)begin
    send_ack(1);recv_byte(regno);send_ack(1);
    // Repeated START, no STOP between pointer and read.
    @(negedge sda);
    if(scl!==1)$fatal(1,"RP108 expected repeated start");
    recv_byte(readaddr);
    if(readaddr!==8'h41)$fatal(1,"RP108 read address");
    send_ack(1);
    if(regno==8'hfb)value=bad_id?16'h0200:16'h0201;
    else if(regno>=8'h50 && regno<=8'h5e && !regno[0])value=values[((regno-8'h50)/2)*16+:16];
    else $fatal(1,"RP108 wrong register %h",regno);
    send_byte(value[7:0]);recv_ack(ack);if(!ack)$fatal(1,"master must ACK low byte");
    send_byte(value[15:8]);recv_ack(ack);if(ack)$fatal(1,"master must NACK high byte");
    @(negedge scl);pull_low=0;
   end else send_ack(0);
  end
 end
endmodule
