`timescale 1ns/1ps
module tb_migration_audio;
reg clk_sys=0,clk_aud=0,rst_n=0;
always #5 clk_sys=~clk_sys; always #165 clk_aud=~clk_aud;
reg signed [15:0] pcm_sys=16'h1234;
wire signed [15:0] pcm_right_sys=pcm_sys;
wire frame_tick,HP_BCK,HP_WS,HP_DIN;
mig_audio_bridge dut(.*);
integer frames=0,bits=0,words=0; reg old_ws=0; reg [15:0] word=0,left_word=0;
always @(posedge clk_sys) if(rst_n && frame_tick) frames=frames+1;
always @(negedge HP_BCK) if(rst_n) begin
 if(HP_WS!=old_ws) begin
  if(bits==16) begin
   if(!old_ws) left_word=word;
   else if(words>3 && word!==left_word) $fatal(1,"stereo words differ %h %h",left_word,word);
   words=words+1;
  end
  bits=0; word=0; old_ws=HP_WS;
 end
 word={word[14:0],HP_DIN}; bits=bits+1;
end
initial begin
 #500; rst_n=1; #90000; pcm_sys=16'h8123; #90000;
 if(frames<15 || words<28) $fatal(1,"audio frame stalled");
 if(left_word!==16'h8123) $fatal(1,"serializer value wrong %h",left_word);
 $display("PASS migration audio"); $finish;
end
endmodule
