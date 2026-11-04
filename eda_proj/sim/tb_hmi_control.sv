`timescale 1ns/1ps
module tb_hmi_control;
 `include "hmi_defs.vh"
 localparam HZ=1843200;
 reg clk=0;always #5 clk=~clk;
 integer progress_fd,pc=0;
 initial progress_fd=$fopen("results/hmi_control/progress.log","w");
 always @(negedge clk)begin
  pc=pc+1;
  if(pc%100000==0)begin $fdisplay(progress_fd,"clocks=%0d commands=%0d page=%0d txframes=%0d",pc,commands,page,lines);$fflush(progress_fd);end
 end
 reg rst_n=0,rx=1;
 wire [7:0] byte_data,cmd;wire byte_valid,frame_error,cmd_valid;
 wire [15:0] hmi_value;
 hmi_uart_rx #(.CLK_HZ(HZ)) uart_rx(.clk(clk),.rst_n(rst_n),.rx(rx),.data(byte_data),.valid(byte_valid),.frame_error(frame_error));
 hmi_rx #(.CLK_HZ(HZ)) parser(.clk(clk),.rst_n(rst_n),.byte_valid(byte_valid),.byte_data(byte_data),.frame_error(frame_error),.cmd_valid(cmd_valid),.cmd(cmd),.value(hmi_value));
 integer commands=0,errors=0;
 always @(posedge clk)begin if(cmd_valid)commands=commands+1;if(frame_error)errors=errors+1;end
 reg kl=1,kr=1,k1=1,k2=1,k3=1,k4=1,test_n=1,ea=1,eb=1,ec=1,oa=1,ob=1,os=1;
 wire selected_panel;wire signed [7:0] oct_l,oct_r;
 mig_octave_control #(.CLK_HZ(HZ)) octave(.clk(clk),.rst_n(rst_n),.enc_a(oa),.enc_b(ob),.enc_sw_n(os),
  .hmi_valid(cmd_valid),.hmi_cmd(cmd),.hmi_value(hmi_value),.selected_panel(selected_panel),.transpose_left(oct_l),.transpose_right(oct_r));
 reg [15:0] touch_l=0,touch_r=0,screen_l=0,screen_r=0;
 reg selected_panel_ctrl=0;
 always @(posedge clk)if(!rst_n)begin screen_l<=0;screen_r<=0;end
 else if(cmd_valid)begin if(cmd==8'h30)screen_l<=hmi_value;if(cmd==8'h31)screen_r<=hmi_value;end
 wire [31:0] live,replay;wire [255:0] notes;wire [95:0] instruments;
 wire [16:0] fallback;wire [3:0] a,d,s,r,gd,gr;wire [15:0] ga,gs;
 wire [2:0] inst_l,inst_r;wire test_mode,strum,up,down;
 mig_input_ctrl #(.CLK_HZ(HZ)) controls(.clk(clk),.rst_n(rst_n),.frame_tick(1'b1),
  .hmi_valid(cmd_valid),.hmi_cmd(cmd),.hmi_value(hmi_value),.volume_up_event(up),.volume_down_event(down),
  .selected_panel(selected_panel_ctrl),
  .keys_left(touch_l|screen_l),.keys_right(touch_r|screen_r),.strum_right(1'b0),.strum_left(1'b0),
  .key_up_n(k1),.key_dn_n(k2),.inst_left_n(kl),.inst_right_n(kr),.aux3_n(1'b1),.aux4_n(1'b1),.test_toggle_n(test_n),
  .enc_a(ea),.enc_b(eb),.enc_c_n(ec),.transpose_left(oct_l),.transpose_right(oct_r),
  .voice_gate(live),.voice_note(notes),.voice_inst(instruments),.volume_q16(fallback),.adsr_a(a),.adsr_d(d),.adsr_s(s),.adsr_r(r),
  .active_voices(),.test_mode(test_mode),.strum_active(strum),.inst_l(inst_l),.inst_r(inst_r),.aux3_stable(),.aux4_stable(),
  .guitar_attack(ga),.guitar_sustain(gs),.guitar_decay(gd),.guitar_release(gr));
 reg [5:0] write_mask=0;reg [101:0] write_values=0;reg [95:0] raw=0;
 wire [84:0] targets,actual;wire [16:0] master,blend,balance;wire [17:0] pitch;
 mig_six_knobs #(.CONTROL_FRAMES(1)) knobs(.clk(clk),.rst_n(rst_n),.frame_tick(1'b1),.write_mask(write_mask),.write_values(write_values),
  .fallback_volume(fallback),.base_pitch(18'd65536),.hmi_valid(cmd_valid),.hmi_cmd(cmd),.hmi_value(hmi_value),
  .volume_up_event(up),.volume_down_event(down),.raw_values(raw),.calibration_low(96'd0),.calibration_high({6{16'd10000}}),
  .targets(targets),.actual_values(actual),.master(master),.blend(blend),.balance(balance),.modulated_pitch(pitch));
 wire recording,playing,full,loop_enabled;wire [6:0] length;wire [31:0] duration,elapsed;
 mig_action_recorder #(.CLK_HZ(HZ),.DEPTH(64)) recorder(.clk(clk),.rst_n(rst_n),.record_n(k3),.play_n(k4),.live_keys(live),
  .hmi_valid(cmd_valid),.hmi_cmd(cmd),.hmi_value(hmi_value),.loop_enabled(loop_enabled),.duration_ms(duration),.elapsed_ms(elapsed),
  .replay_keys(replay),.record_stable(),.play_stable(),.recording(recording),.playing(playing),.record_led(),.play_led(),.full(full),.length(length));
 wire signed [4:0] semitone;wire approx;wire [17:0] base_pitch;
 reg pitch_up=1,pitch_down=1;
 pitch_key_control #(.CLK_HZ(HZ),.DEBOUNCE_MS(1),.LONG_PRESS_MS(5)) pitch_control(.clk(clk),.rst_n(rst_n),
  .key_up_n(pitch_up),.key_down_n(pitch_down),.hmi_valid(cmd_valid),.hmi_cmd(cmd),.hmi_value(hmi_value),
  .semitone(semitone),.approximate(approx),.pitch_scale_q16(base_pitch));
 reg [HMI_TX_FIELD_COUNT*32-1:0] fields;
 always @*begin fields=0;
  fields[HMI_FIELD_P5_C90_OCTAVE_LEFT*32+:32]={{24{oct_l[7]}},oct_l};
  fields[HMI_FIELD_P6_C81_KNOB_0*32+:32]=(targets[16:0]*32'd1000+32768)>>16;
  fields[HMI_FIELD_P9_C50_RECORD_STATE*32+:32]={29'd0,full,playing,recording};
  fields[HMI_FIELD_P9_C51_RECORD_LENGTH*32+:32]=length;end
 wire tx;wire [3:0] page;wire [31:0] byte_count;
 hmi_tx #(.CLK_HZ(HZ),.FIELD_COUNT(HMI_TX_FIELD_COUNT)) transmitter(.clk(clk),.rst_n(rst_n),.cmd_valid(cmd_valid),.cmd(cmd),.value(hmi_value),.fields(fields),.tx(tx),.current_page(page),.byte_count(byte_count));
 wire [7:0] tx_data;wire tx_valid,tx_error;
 hmi_uart_rx #(.CLK_HZ(HZ)) monitor(.clk(clk),.rst_n(rst_n),.rx(tx),.data(tx_data),.valid(tx_valid),.frame_error(tx_error));
 reg [7:0] nf[0:31];integer nlen=0,lines=0,illegal=0,last_volume=-1,last_octave=99,stream_fd;
 reg [31:0] ntail=0;integer ni,nmag;
 initial stream_fd=$fopen("results/hmi_control/hmi_tx_raw.bin","wb");
 always @(negedge clk)if(tx_valid)begin
  $fwrite(stream_fd,"%c",tx_data);
  nf[nlen]=tx_data;nlen=nlen+1;ntail={ntail[23:0],tx_data};
  if(ntail==32'hcc33c33c)begin
   if(nf[0]!=8'haa || nf[1]!=8'hb1 || (nlen<9 && !(nlen==7 && nf[2]==1)))illegal=illegal+1;
   else begin
    if({nf[3],nf[4]}==5 && {nf[5],nf[6]}==90 && nlen==17)begin
     nmag=(nf[8]-48)*10000+(nf[9]-48)*1000+(nf[10]-48)*100+(nf[11]-48)*10+(nf[12]-48);
     last_octave=(nf[7]==8'h2d)?-nmag:nmag;
    end
    if({nf[3],nf[4]}==6 && {nf[5],nf[6]}==81 && nlen==15)
     last_volume={nf[7],nf[8],nf[9],nf[10]};
   end
   lines=lines+1;nlen=0;ntail=0;
  end else if(nlen>=32)begin illegal=illegal+1;nlen=0;ntail=0;end
 end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task byte_send(input [7:0] b,input bit good_stop=1);integer j;begin
  rx=0;cycles(16);for(j=0;j<8;j=j+1)begin rx=b[j];cycles(16);end rx=good_stop;cycles(16);rx=1;cycles(20);
 end endtask
 task send(input [7:0] c,input [15:0] v);begin
  byte_send('h5a);byte_send('ha5);byte_send(c);byte_send(v[15:8]);byte_send(v[7:0]);byte_send(c^v[15:8]^v[7:0]);cycles(8);
 end endtask
 task native_tail;begin
  byte_send(8'hcc);byte_send(8'h33);byte_send(8'hc3);byte_send(8'h3c);cycles(8);
 end endtask
 task native_page(input [15:0] p);begin
  byte_send(8'haa);byte_send(8'hb1);byte_send(8'h01);
  byte_send(p[15:8]);byte_send(p[7:0]);native_tail;
 end endtask
 task native_button(input [15:0] p,input [15:0] c,input [7:0] subtype,input [7:0] status);begin
  byte_send(8'haa);byte_send(8'hb1);byte_send(8'h11);
  byte_send(p[15:8]);byte_send(p[7:0]);byte_send(c[15:8]);byte_send(c[7:0]);
  byte_send(8'h10);byte_send(subtype);byte_send(status);native_tail;
 end endtask
 task native_slider(input [15:0] p,input [15:0] c,input [31:0] v);begin
  byte_send(8'haa);byte_send(8'hb1);byte_send(8'h11);
  byte_send(p[15:8]);byte_send(p[7:0]);byte_send(c[15:8]);byte_send(c[7:0]);byte_send(8'h13);
  byte_send(v[31:24]);byte_send(v[23:16]);byte_send(v[15:8]);byte_send(v[7:0]);native_tail;
 end endtask
 task knob(input integer v);begin raw[15:0]=v;write_values[16:0]=(v*65536)/10000;write_mask=1;cycles(1);write_mask=0;cycles(4);end endtask
 task detent;begin oa=1;ob=0;cycles(2000);oa=0;cycles(2000);ob=1;cycles(2000);oa=1;cycles(2000);end endtask
 integer saved,i;reg [31:0] bytes_before;bit saw_left=0,saw_right=0;
 always @(negedge clk)if(playing)begin if(replay[0])saw_left=1;if(replay[17])saw_right=1;end
 initial begin
  cycles(10);rst_n=1;cycles(100);
  saved=commands;byte_send('h88);repeat(3)byte_send('hff);byte_send('h1a);repeat(3)byte_send('hff);
  repeat(3)byte_send(0);repeat(3)byte_send('hff);if(commands!=saved)$fatal(1,"TJC noise emitted command");
  byte_send('h5a);byte_send(0);byte_send(1);byte_send(0);byte_send(4);byte_send(5);
  byte_send('h5a);byte_send('ha5);byte_send(1);byte_send(0);byte_send(4);byte_send(0);
  byte_send('h5a);byte_send('ha5);byte_send(1);cycles(10000);byte_send(0);byte_send(4);byte_send(5);
  byte_send('h5a,0);cycles(50);if(commands!=saved || errors==0)$fatal(1,"invalid/timeout/framing acceptance");
  send(1,65535);if(inst_l!=4)$fatal(1,"instrument clamp");send(1,0);
  send(3,16'h8000);if(oct_l!=-4)$fatal(1,"signed clamp");send(3,0);
  send('h0b,1000);if(a!=15)$fatal(1,"ordinary ADSR scaling");
  send(1,1);send('h0b,1000);if(ga!=4096)$fatal(1,"selected guitar A scaling");
  send('h21,250);if(ga==4096)$fatal(1,"guitar direct command ignored");
  send(1,0);send('h21,1000);if(ga!=4096)$fatal(1,"guitar A scaling");
  send('h23,65535);if(gs!=32767)$fatal(1,"guitar S clamp");
  knob(2000);send(6,800);if(targets[16:0]!=13107)$fatal(1,"screen must not change knob-only volume");
  knob(2100);if(targets[16:0]!=13762)$fatal(1,"physical volume update");
  knob(2400);if(targets[16:0]!=15728)$fatal(1,"physical volume update");
  k1=0;cycles(40000);k1=1;cycles(40000);if(targets[16:0]!=15728)$fatal(1,"KEY1 changed volume");
  send(6,900);knob(2450);if(targets[16:0]!=16056)$fatal(1,"screen seized volume");
  k2=0;cycles(40000);k2=1;cycles(40000);if(targets[16:0]!=16056)$fatal(1,"KEY2 changed volume");
  knob(3000);if(targets[16:0]!=19660)$fatal(1,"pot latest did not win");
  send(6,65535);if(targets[16:0]!=19660)$fatal(1,"screen changed volume");
  knob(5000);send(6,510);knob(5150);if(targets[16:0]!=33751)$fatal(1,"physical-only volume tracking");
  send('h1f,5);send(3,1);detent;if(oct_l!=2)$fatal(1,"EC11 after remote");
  cycles(180000);if(last_octave!=2)$fatal(1,"EC11 echo %0d",last_octave);
  send(3,16'hfffe);cycles(180000);if(oct_l!=-2 || last_octave!=-2)$fatal(1,"remote after EC11 echo %0d",last_octave);
  send('h15,1);if(selected_panel!=1)$fatal(1,"panel selection remote");
  os=0;cycles(40000);os=1;cycles(40000);if(selected_panel!=0)$fatal(1,"panel selection EC11");
  send(5,4);if(semitone!=4 || approx)$fatal(1,"semitone remote");
  pitch_up=0;cycles(4000);pitch_up=1;cycles(4000);if(semitone!=5 || approx)$fatal(1,"semitone button");
  pitch_up=0;cycles(20000);if(!approx)$fatal(1,"continuous glide approximate marker");pitch_up=1;cycles(4000);
  send('h1f,16'hffff);cycles(20000);send('h1f,6);
  for(i=0;i<60;i=i+1)send(6,i*13);
  send(6,777);cycles(180000);if(last_volume!=515)$fatal(1,"physical volume readback changed %0d",last_volume);
  bytes_before=byte_count;cycles(184320);if(byte_count-bytes_before>700)$fatal(1,"bandwidth cap");
  send('h1f,16'hffff);cycles(20000);send('h1f,9);cycles(50000);
  send('h10,1);send('h10,1);if(!recording)$fatal(1,"start not idempotent");
  send('h30,1);cycles(10000);send('h31,2);cycles(10000);send('h30,0);send('h31,0);
  // K4 ignored during record, K3 stops the take.
  k4=0;cycles(30000);k4=1;cycles(30000);if(!recording)$fatal(1,"K4 disrupted recording");
  k3=0;cycles(30000);k3=1;cycles(30000);if(recording || duration==0 || length<5)$fatal(1,"K3 stop failed");
  send('h11,1);cycles(200000);if(!saw_left || !saw_right)$fatal(1,"screen notes not recorded/replayed");
  send('h11,0);if(playing || replay!=0)$fatal(1,"stop playback");
  k4=0;cycles(30000);k4=1;cycles(30000);send('h11,0);if(playing)$fatal(1,"hardware start remote stop");
  send('h10,1);send('h10,0);if(recording)$fatal(1,"remote record stop");
  send('h13,1);if(!loop_enabled)$fatal(1,"runtime loop");send('h14,0);if(length!=0)$fatal(1,"delete");
  // CF-Design native page reports and controls, including every generated page.
  for(i=0;i<11;i=i+1)begin native_page(i);if(page!=i)$fatal(1,"native page %0d",i);end
  native_button(5,44,1,1);if(inst_l!=4)$fatal(1,"native board1 instrument");
  native_button(5,47,1,1);if(inst_r!=2)$fatal(1,"native board2 instrument");
  native_slider(5,50,8);if(oct_l!=4)$fatal(1,"native board1 octave");
  native_slider(5,52,0);if(oct_r!=-4)$fatal(1,"native board2 octave");
  native_slider(5,54,19);if(semitone!=7)$fatal(1,"native semitone");
  native_slider(6,81,321);if(targets[16:0]!=33751)$fatal(1,"native screen changed physical-only volume");
  native_slider(6,82,321);if(targets[33:17]!=(321*65536/1000))$fatal(1,"native blend control");
  native_button(9,41,1,1);if(!recording)$fatal(1,"native record start");
  native_button(9,42,1,1);if(recording)$fatal(1,"native record stop");
  native_button(10,31,1,1);if(!test_mode)$fatal(1,"native 32-voice test");
  native_button(1,91,1,1);if(selected_panel!=1)$fatal(1,"native panel select");
  native_button(1,100,1,1);if(screen_r!=16'h0001)$fatal(1,"native key press");
  native_button(1,100,1,0);if(screen_r!=16'h0000)$fatal(1,"native key release");
  cycles(200000);
  if(illegal!=0)$fatal(1,"illegal transmitted frames=%0d",illegal);
  $fclose(stream_fd);
  $display("PASS UART/legacy/native-pages/native-controls/framing/noise/timeout/clamps/soft-pickup/volume/EC11/pitch/mailbox/bandwidth/recorder; commands=%0d lines=%0d illegal=%0d",commands,lines,illegal);$finish;
 end
 initial begin cycles(3000000);$fatal(1,"test watchdog");end
endmodule
