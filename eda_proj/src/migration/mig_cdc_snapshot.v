// Bundled-data mailbox. Source hold is immutable until destination acknowledges.
// Both domains must share rst_n (asynchronous assert); receiver starts at zero.
module mig_cdc_snapshot #(parameter integer WIDTH=16)(
 input wire src_clk, dst_clk, rst_n,
 input wire [WIDTH-1:0] src_data,
 output reg [WIDTH-1:0] dst_data
);
 reg [WIDTH-1:0] hold_data;
 reg request,ack;
 reg [1:0] ack_sync;
 reg [2:0] req_sync;
 always @(posedge src_clk or negedge rst_n) begin
  if(!rst_n) begin hold_data<=0; request<=0; ack_sync<=0; end
  else begin
   ack_sync<={ack_sync[0],ack};
   if(request==ack_sync[1]) begin hold_data<=src_data; request<=~request; end
  end
 end
 always @(posedge dst_clk or negedge rst_n) begin
  if(!rst_n) begin req_sync<=0; ack<=0; dst_data<=0; end
  else begin
   req_sync<={req_sync[1:0],request};
   if(req_sync[2]!=ack) begin dst_data<=hold_data; ack<=req_sync[2]; end
  end
 end
endmodule
