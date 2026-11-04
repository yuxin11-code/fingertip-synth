`timescale 1ns/1ps
module tb_migration_stereo;
reg clk_sys=0,clk_aud=0,rst_n=0;
always #5 clk_sys=~clk_sys;always #165 clk_aud=~clk_aud;
reg signed [15:0] pcm_sys=16'h1234,pcm_right_sys=16'hfedc;
wire frame_tick,HP_BCK,HP_WS,HP_DIN;
mig_audio_bridge #(.STEREO(1)) dut(.*);
integer bits=0,words=0;reg old_ws=0;reg [15:0] word=0,left_word=0;
always @(negedge HP_BCK) if(rst_n) begin
 if(HP_WS!=old_ws) begin
  if(bits==16) begin
   if(!old_ws) left_word=word;
   else if(words>5) begin
    if(!((left_word==16'h1234 && word==16'hfedc) ||
         (left_word==16'h8123 && word==16'h4567)))
     $fatal(1,"torn/swapped stereo pair %h %h",left_word,word);
   end
   words=words+1;
  end
  bits=0;word=0;old_ws=HP_WS;
 end
 word={word[14:0],HP_DIN};bits=bits+1;
end
initial begin
 #500;rst_n=1;#90000;
 pcm_sys=16'h8123;pcm_right_sys=16'h4567;#90000;
 if(words<28 || left_word!=16'h8123) $fatal(1,"stereo stalled");
 $display("PASS migration stereo");$finish;
end
endmodule
