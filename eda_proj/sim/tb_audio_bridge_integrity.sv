`timescale 1ns/1ps
// Every decoded PT8211 sample is checked. Mirrors real clock ratio and
// engine/mixer commit latency; a zero mismatch result is NOT a board-noise test.
module tb_audio_bridge_integrity;
 reg clk_sys=0,clk_aud=0,rst_n=0;
 always #9.524 clk_sys=~clk_sys;
 always #314.593 clk_aud=~clk_aud;
 reg signed [15:0] pcm_sys=0,pcm_right_sys=0;
 wire frame_tick,HP_BCK,HP_WS,HP_DIN;
 mig_audio_bridge #(.STEREO(1)) dut(.*);
 integer generation=0,pending=-1,commit_delay=570,target=20000;
 function [15:0] pattern(input integer index);begin pattern=index*257+16'h1357;end endfunction
 always @(posedge clk_sys)if(rst_n)begin
  if(frame_tick)begin generation=generation+1;pending=commit_delay+(generation&7);end
  else if(pending>0)pending=pending-1;
  else if(pending==0)begin pcm_sys<=pattern(generation);pcm_right_sys<=~pattern(generation);pending=-1;end
 end
 integer bits=0,pairs=0,expected_id=1;
 reg old_ws=0,started=0;
 reg [15:0] word=0,left_word=0;
 // Decode on the actual PT8211 sampling edge, not the output launch edge.
 always @(posedge HP_BCK)if(rst_n)begin
  if(HP_WS!==0 && HP_WS!==1)$fatal(1,"unknown WS");
  if(HP_DIN!==0 && HP_DIN!==1)$fatal(1,"unknown data");
  if(HP_WS!=old_ws)begin
   if(bits==16)begin
    if(!old_ws)left_word=word;
    else begin
     if(!started && left_word==pattern(1) && word==~left_word)started=1;
     if(started)begin
      if(word!==~left_word)$fatal(1,"torn/swapped pair %0d %h/%h",pairs,left_word,word);
      if(left_word!==pattern(expected_id))$fatal(1,"dropped/duplicated/corrupt sample pair=%0d id=%0d got=%h expected=%h",pairs,expected_id,left_word,pattern(expected_id));
      pairs=pairs+1;expected_id=expected_id+1;
      if(pairs==target)begin
       $display("PASS audio bridge integrity: pairs=%0d mismatches=0 delay=%0d..%0d clocks=52.5MHz/1.589MHz",pairs,commit_delay,commit_delay+7);
       $finish;
      end
     end
    end
   end else if(started)$fatal(1,"serial word length=%0d",bits);
   bits=0;word=0;old_ws=HP_WS;
  end
  word={word[14:0],HP_DIN};bits=bits+1;
 end
 initial begin
  if($value$plusargs("DELAY=%d",commit_delay))begin end
  if($value$plusargs("PAIRS=%d",target))begin end
  #1000;rst_n=1;
 end
 initial begin #5000000000;$fatal(1,"bridge watchdog pairs=%0d generation=%0d",pairs,generation);end
endmodule
