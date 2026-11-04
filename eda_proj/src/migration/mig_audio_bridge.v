// Reuse the original PT8211 serializer. Snapshot an atomic left/right pair.
// STEREO=0 duplicates pcm_sys for backwards-compatible mono operation.
module mig_audio_bridge #(parameter STEREO=0)(
 input wire clk_sys,clk_aud,rst_n,
 input wire signed [15:0] pcm_sys,
 input wire signed [15:0] pcm_right_sys,
 output wire frame_tick,
 output wire HP_BCK,HP_WS,HP_DIN
);
 // clk_aud starts only AFTER the system reset releases CLKDIV. Releasing
 // the serializer reset with the system reset leaves it without a local
 // clock/reset overlap. Hold the whole mailbox/serializer link reset for
 // three actual audio clocks; asynchronous assertion, local synchronous
 // release. Explicit power-up state maps to Gowin GSR and also defines the
 // no-button cold-start behaviour in RTL simulation.
 reg [2:0] audio_reset_release=3'b000;
 always @(posedge clk_aud or negedge rst_n) begin
  if(!rst_n) audio_reset_release<=3'b000;
  else audio_reset_release<={audio_reset_release[1:0],1'b1};
 end
 wire link_rst_n=rst_n && audio_reset_release[2];
 wire req;
 wire [31:0] pcm_received;
 reg [31:0] pcm_frame;
 reg [15:0] pcm_word;
 reg half_frame,frame_toggle;
 reg [2:0] toggle_sync;
 mig_cdc_snapshot #(.WIDTH(32)) transfer(
  .src_clk(clk_sys),.dst_clk(clk_aud),.rst_n(link_rst_n),
  .src_data({STEREO ? pcm_right_sys : pcm_sys,pcm_sys}),.dst_data(pcm_received));
 always @(posedge clk_aud or negedge link_rst_n) begin
  if(!link_rst_n) begin half_frame<=0; frame_toggle<=0; pcm_frame<=0; pcm_word<=0; end
  else if(req) begin
   half_frame<=~half_frame;
   if(!half_frame) begin pcm_frame<=pcm_received; pcm_word<=pcm_received[15:0]; frame_toggle<=~frame_toggle; end
   else pcm_word<=pcm_frame[31:16];
  end
 end
 always @(posedge clk_sys or negedge link_rst_n) begin
  if(!link_rst_n) toggle_sync<=0;
  else toggle_sync<={toggle_sync[1:0],frame_toggle};
 end
 assign frame_tick=toggle_sync[2]^toggle_sync[1];
 audio_drive serializer(.clk_1p536m(clk_aud),.rst_n(link_rst_n),.idata(pcm_word),
  .req(req),.HP_BCK(HP_BCK),.HP_WS(HP_WS),.HP_DIN(HP_DIN));
endmodule
