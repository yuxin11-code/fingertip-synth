// CF-Design native transmitter. Field/page/control tables are generated from
// hmi/assets/ui_manifest.json into hmi_defs.vh.
module hmi_tx #(
 parameter integer CLK_HZ=52500000,BAUD=115200,FIELD_COUNT=86,LINK_DIAGNOSTICS=0,SYNTH_MODE=1,
 HEARTBEAT_CLKS=CLK_HZ,QUERY_CLKS=CLK_HZ*2,
 // Native graphics frames run at the configured UART baud, with a bounded
 // quiet interval between packets for the display CPU. Ordinary fields keep
 // their existing conservative byte pacing. No UART format/baud change.
 AUX_PACKET_PAUSE_CLKS=CLK_HZ/500
)(
 input wire clk,rst_n,cmd_valid,input wire [7:0] cmd,input wire [15:0] value,
 input wire [FIELD_COUNT*32-1:0] fields,
 input wire page_valid,screen_reset,input wire [15:0] page_id,
 input wire aux_valid,aux_last,input wire [7:0] aux_data,output wire aux_ready,
 input wire aux_frame_end,
 output wire tx,output reg [3:0] current_page,
 output reg [31:0] byte_count);
 `define HMI_DEFINE_TX_TABLE
 `include "hmi_defs.vh"
 `undef HMI_DEFINE_TX_TABLE
 localparam integer N=HMI_TX_FIELD_COUNT;
 localparam integer BANKS=(N+7)/8;
 localparam integer SCAN_W=$clog2(N);
 localparam integer GAP=(CLK_HZ*10/BAUD*5+2)/3;
 localparam integer HW=(HEARTBEAT_CLKS<2)?1:$clog2(HEARTBEAT_CLKS);
 localparam integer QW=(QUERY_CLKS<2)?1:$clog2(QUERY_CLKS);
 reg [HW-1:0] heartbeat_timer;reg [QW-1:0] query_timer;
 reg query_pending,page_known,heartbeat_pending;reg [3:0] heartbeat_page;
 reg [23:0] heartbeat_bcd;reg [1:0] frame_mode;
 integer hb_digit;reg hb_carry;
 reg [31:0] sent[0:N-1];
 reg [N*32-1:0] fields_snapshot;
 reg [N-1:0] force_dirty;
 reg [SCAN_W-1:0] scan,active;
 reg [3:0] active_page,scan_page;
 reg [15:0] active_ctrl,scan_ctrl;
 reg [3:0] active_kind,scan_kind;
 reg [31:0] snapshot,selected_value,selected_sent;
 reg scan_force;
 // Sticky invalidation also covers page A -> B -> A while a frame is busy.
 reg active_stale;
 reg [31:0] bank_value[0:BANKS-1];
 wire [BANKS*256-1:0] padded_snapshot=fields_snapshot;
 reg aux_turn,aux_end;
 reg aux_frame_done,aux_stale;
 reg [7:0] buffer[0:31];
 reg [5:0] length,pos;
 reg [4:0] state;
 reg [31:0] throttle,magnitude;
 reg [39:0] bcd,bcd_adjust;
 reg [5:0] bcd_count;
 reg uart_start;
 reg [7:0] uart_data;
 wire busy;
 assign aux_ready=(state==11 && !busy && throttle==0);
 mig_uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) uart(
  .clk(clk),.rst_n(rst_n),.start(uart_start),.data(uart_data),.tx(tx),.busy(busy));

 integer k,d;
 reg [31:0] frame_count;
 always @* begin
  bcd_adjust=bcd;
  for(d=0;d<10;d=d+1)
   if(bcd[d*4+:4]>=5)bcd_adjust[d*4+:4]=bcd[d*4+:4]+4'd3;
 end

 task put_tail;
  input integer start;
  begin
   buffer[start]<=HMI_FRAME_TAIL0;buffer[start+1]<=HMI_FRAME_TAIL1;
   buffer[start+2]<=HMI_FRAME_TAIL2;buffer[start+3]<=HMI_FRAME_TAIL3;
  end
 endtask

 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   heartbeat_timer<=0;query_timer<=0;query_pending<=1;page_known<=0;
   heartbeat_pending<=0;heartbeat_page<=0;heartbeat_bcd<=0;frame_mode<=0;
   current_page<=0;byte_count<=0;frame_count<=0;fields_snapshot<=0;force_dirty<={N{1'b1}};
   scan<=0;active<=0;active_page<=0;active_ctrl<=0;active_kind<=0;
   scan_page<=0;scan_ctrl<=0;scan_kind<=0;scan_force<=0;
   active_stale<=1;
   snapshot<=0;selected_value<=0;selected_sent<=0;
   length<=0;pos<=0;state<=0;throttle<=0;magnitude<=0;bcd<=0;bcd_count<=0;
   uart_start<=0;uart_data<=0;aux_turn<=1;aux_end<=0;aux_frame_done<=1;aux_stale<=0;
   for(k=0;k<N;k=k+1)sent[k]<=32'hffffffff;
   for(k=0;k<BANKS;k=k+1)bank_value[k]<=0;
  end else begin
   uart_start<=0;
   if(query_timer==QUERY_CLKS-1)begin query_timer<=0;query_pending<=1;end
   else query_timer<=query_timer+1'b1;
   if(LINK_DIAGNOSTICS)begin
    if(heartbeat_timer==HEARTBEAT_CLKS-1)begin
     heartbeat_timer<=0;heartbeat_pending<=1;heartbeat_page<=current_page;
     hb_carry=1;
     for(hb_digit=0;hb_digit<6;hb_digit=hb_digit+1)begin
      if(hb_carry)begin
       if(heartbeat_bcd[hb_digit*4+:4]==9)heartbeat_bcd[hb_digit*4+:4]<=0;
       else begin heartbeat_bcd[hb_digit*4+:4]<=heartbeat_bcd[hb_digit*4+:4]+1'b1;hb_carry=0;end
      end
     end
    end else heartbeat_timer<=heartbeat_timer+1'b1;
   end
   if(throttle!=0)throttle<=throttle-1'b1;
   case(state)
    0:begin
     // Refresh before each pipelined field selection. A whole-table snapshot
     // could otherwise be seconds old while graphics packets occupy the UART.
     fields_snapshot<=fields;
     if(query_pending && (aux_frame_done || aux_stale))begin
      buffer[0]<=8'haa;buffer[1]<=8'hb1;buffer[2]<=8'h01;put_tail(3);
      length<=7;pos<=0;frame_mode<=2;query_pending<=0;state<=4;
     end else if(LINK_DIAGNOSTICS && heartbeat_pending && (aux_frame_done || aux_stale))begin
      buffer[0]<=8'haa;buffer[1]<=8'hb1;buffer[2]<=8'h10;
      buffer[3]<=0;buffer[4]<={4'd0,heartbeat_page};buffer[5]<=8'h03;buffer[6]<=8'h84;
      buffer[7]<=8'h48;buffer[8]<=8'h42;
      for(k=0;k<6;k=k+1)buffer[9+k]<=8'h30+heartbeat_bcd[(5-k)*4+:4];
      put_tail(15);length<=19;pos<=0;frame_mode<=1;state<=4;
     end else if(aux_valid===1'b1 && aux_turn)begin
      state<=11;aux_turn<=0;aux_stale<=0;
     end
     else begin state<=8;end
    end
    8:begin
     for(k=0;k<BANKS;k=k+1)bank_value[k]<=padded_snapshot[(k*8+scan[2:0])*32+:32];
     selected_sent<=sent[scan];scan_page<=hmi_field_page(scan);
     scan_ctrl<=hmi_field_ctrl(scan);scan_kind<=hmi_field_kind(scan);
     scan_force<=force_dirty[scan];state<=9;
    end
    9:begin selected_value<=bank_value[scan[SCAN_W-1:3]];state<=10;end
    10:begin
     // Empty/off-page fields do not each earn another graphics packet.
     // Scan to an actual field update (or the end of the table) before yielding.
     // This bounds control starvation without a wide dynamic input mux.
     if(scan==N-1)aux_turn<=1;
     if((scan_page==current_page || scan_page==14) && (scan_force || selected_value!=selected_sent))begin
      active<=scan;active_page<=current_page;active_ctrl<=scan_ctrl;active_kind<=scan_kind;
      active_stale<=0;
      snapshot<=selected_value;frame_mode<=0;state<=1;
     end else state<=0;
     scan<=(scan==N-1)?0:scan+1'b1;
    end
    1:begin
     buffer[0]<=HMI_FRAME_HEAD;buffer[1]<=HMI_CMD_CONTROL;
     buffer[2]<=(active_kind==2)?HMI_OP_ICON_FRAME:HMI_OP_WRITE;
     buffer[3]<=8'd0;buffer[4]<={4'd0,active_page};
     buffer[5]<=active_ctrl[15:8];buffer[6]<=active_ctrl[7:0];
     if(active_kind==0 || active_kind==1 || active_kind==8 || active_kind==9 || active_kind==11 || active_kind==13)begin
      magnitude<=((active_kind==1 || active_kind==9) && snapshot[31])?-snapshot:snapshot;
      bcd<=0;bcd_count<=0;state<=2;
     end else if(active_kind==10)begin
      // GBK short timbre names fit the shared 35-pixel status cells.
      case(snapshot[2:0])
       0:begin buffer[7]<=8'hb8;buffer[8]<=8'hd6;buffer[9]<=8'hc7;buffer[10]<=8'hd9;end
       1:begin buffer[7]<=8'hbc;buffer[8]<=8'haa;buffer[9]<=8'hcb;buffer[10]<=8'hfb;end
       2:begin buffer[7]<=8'hcc;buffer[8]<=8'he1;buffer[9]<=8'hc7;buffer[10]<=8'hd9;end
       3:begin buffer[7]<=8'hb9;buffer[8]<=8'hc5;buffer[9]<=8'hf3;buffer[10]<=8'hdd;end
       default:begin buffer[7]<=8'hc5;buffer[8]<=8'hfd;buffer[9]<=8'hc5;buffer[10]<=8'hc3;end
      endcase
      put_tail(11);length<=15;pos<=0;state<=4;
     end else if(active_kind==5)begin
      buffer[7]<=8'h41;buffer[8]<=8'h30+snapshot[7:4];buffer[9]<=8'h20;
      buffer[10]<=8'h42;buffer[11]<=8'h30+snapshot[3:0];buffer[12]<=8'h20;
      put_tail(13);length<=17;pos<=0;state<=4;
     end else if(active_kind==6)begin
      buffer[7]<=snapshot!=0?8'h7e:8'h20;
      for(k=8;k<13;k=k+1)buffer[k]<=8'h20;
      put_tail(13);length<=17;pos<=0;state<=4;
     end else if(active_kind==7)begin
      // GBK: please import score / timed / wait / pause / complete.
      if(snapshot==0)begin
       buffer[7]<=8'hc7;buffer[8]<=8'heb;buffer[9]<=8'hcf;buffer[10]<=8'hc8;
       buffer[11]<=8'hb5;buffer[12]<=8'hbc;buffer[13]<=8'hc8;buffer[14]<=8'heb;
       buffer[15]<=8'hc7;buffer[16]<=8'hfa;buffer[17]<=8'hc6;buffer[18]<=8'hd7;
       put_tail(19);length<=23;
      end else begin
       buffer[7]<=snapshot[3]?8'hb5:8'hb8;buffer[8]<=snapshot[3]?8'hc8:8'hfa;
       buffer[9]<=snapshot[3]?8'hb4:8'hc5;buffer[10]<=snapshot[3]?8'hfd:8'hc4;
       buffer[11]<=8'h20;
       buffer[12]<=snapshot[5:4]==0?8'h31:(snapshot[5:4]==1?8'h37:8'h35);
       buffer[13]<=snapshot[5:4]==0?8'h30:(snapshot[5:4]==1?8'h35:8'h30);
       buffer[14]<=snapshot[5:4]==0?8'h30:8'h25;buffer[15]<=snapshot[5:4]==0?8'h25:8'h20;
       buffer[16]<=8'h20;
       buffer[17]<=snapshot[6]?8'hcd:snapshot[2]?8'hd4:snapshot[1]?8'hd4:8'hbe;
       buffer[18]<=snapshot[6]?8'hea:snapshot[2]?8'hdd:snapshot[1]?8'hcb:8'hcd;
       buffer[19]<=snapshot[6]?8'hb3:snapshot[2]?8'hcd:snapshot[1]?8'hd0:8'hd0;
       buffer[20]<=snapshot[6]?8'hc9:snapshot[2]?8'ha3:snapshot[1]?8'hd0:8'hf7;
       put_tail(21);length<=25;
      end
      pos<=0;state<=4;
     end else if(active_kind==12)begin
      // Vendor manual 4.1.7: one atomic visibility command may contain
      // repeated {page:u16, control:u16, visible:u8} tuples. Hidden TP is off.
      // Hide the disabled overlay when active, otherwise hide slider/value.
      buffer[2]<=8'h03;buffer[7]<=(snapshot!=0);
      buffer[8]<=0;buffer[9]<=5;
      buffer[10]<=0;buffer[11]<=8'd62+(active_ctrl-16'd120);
      buffer[12]<=(snapshot==0);
      buffer[13]<=0;buffer[14]<=5;
      buffer[15]<=0;buffer[16]<=8'd100+(active_ctrl-16'd120);
      buffer[17]<=(snapshot==0);put_tail(18);length<=22;pos<=0;state<=4;
     end else if(active_kind==2)begin
      buffer[7]<=snapshot[15:8];buffer[8]<=snapshot[7:0];
      put_tail(9);length<=13;pos<=0;state<=4;
     end else if(active_kind==3)begin
      buffer[7]<=snapshot[7:0];put_tail(8);length<=12;pos<=0;state<=4;
     end else begin
      buffer[7]<=snapshot[31:24];buffer[8]<=snapshot[23:16];
      buffer[9]<=snapshot[15:8];buffer[10]<=snapshot[7:0];
      put_tail(11);length<=15;pos<=0;state<=4;
     end
    end
    2:begin
     bcd<={bcd_adjust[38:0],magnitude[31]};magnitude<=magnitude<<1;
     if(bcd_count==31)state<=3;else bcd_count<=bcd_count+1'b1;
    end
    3:begin
     if(active_kind==13)begin
      // AV-compatible read-only progress text; the underlying field is 0..100.
      if(snapshot>=100)begin
       buffer[7]<=8'h31;buffer[8]<=8'h30;buffer[9]<=8'h30;buffer[10]<=8'h25;
       put_tail(11);length<=15;
      end else if(snapshot>=10)begin
       buffer[7]<=8'h30+bcd[7:4];buffer[8]<=8'h30+bcd[3:0];buffer[9]<=8'h25;
       put_tail(10);length<=14;
      end else begin
       buffer[7]<=8'h30+bcd[3:0];buffer[8]<=8'h25;
       put_tail(9);length<=13;
      end
      pos<=0;state<=4;
     end else if(active_kind==11)begin
      buffer[7]<=8'h30+bcd[11:8];buffer[8]<=8'h30+bcd[7:4];
      buffer[9]<=8'h2e;buffer[10]<=8'h30+bcd[3:0];
      put_tail(11);length<=15;pos<=0;state<=4;
     end else if(active_kind==9)begin
      buffer[7]<=snapshot[31]?8'h2d:8'h2b;buffer[8]<=8'h30+bcd[3:0];
      put_tail(9);length<=13;pos<=0;state<=4;
     end else if(active_kind==8 && active_page==0 && active_ctrl==5)begin
      buffer[7]<=8'h30+bcd[11:8];buffer[8]<=8'h30+bcd[7:4];buffer[9]<=8'h30+bcd[3:0];
      put_tail(10);length<=14;pos<=0;state<=4;
     end else if(active_kind==8 && active_page==0 && active_ctrl==6)begin
      buffer[7]<=8'h30+bcd[7:4];buffer[8]<=8'h30+bcd[3:0];
      put_tail(9);length<=13;pos<=0;state<=4;
     end else if(SYNTH_MODE==1 && active_kind==8 && active_page==5 && active_ctrl==102)begin
      // Input is 500..1000 tenths-percent. 50%..100% fits the 45-pixel cell.
      if(bcd[15:12]!=0)begin
       buffer[7]<=8'h31;buffer[8]<=8'h30;buffer[9]<=8'h30;buffer[10]<=8'h25;
       put_tail(11);length<=15;
      end else begin
       buffer[7]<=8'h30+bcd[11:8];buffer[8]<=8'h30+bcd[7:4];buffer[9]<=8'h25;
       put_tail(10);length<=14;
      end
      pos<=0;state<=4;
     end else if(active_kind==8 && active_page==5 && active_ctrl>=100 && active_ctrl<=103)begin
      buffer[7]<=8'h30+bcd[15:12];buffer[8]<=8'h30+bcd[11:8];
      buffer[9]<=8'h30+bcd[7:4];buffer[10]<=8'h30+bcd[3:0];
      put_tail(11);length<=15;pos<=0;state<=4;
     end else if(active_kind==8 && active_ctrl==915)begin
      buffer[7]<=8'h30+bcd[7:4];buffer[8]<=8'h30+bcd[3:0];
      put_tail(9);length<=13;pos<=0;state<=4;
     end else if(active_kind==8 && active_ctrl>=916 && active_ctrl<=918)begin
      buffer[7]<=8'h30+bcd[3:0];put_tail(8);length<=12;pos<=0;state<=4;
     end else if(active_kind==8 && active_ctrl==914)begin
      buffer[7]<=8'h30+bcd[15:12];buffer[8]<=8'h30+bcd[11:8];buffer[9]<=8'h30+bcd[7:4];buffer[10]<=8'h30+bcd[3:0];
      put_tail(11);length<=15;pos<=0;state<=4;
     end else if(active_kind==1)begin
      buffer[7]<=snapshot[31]?8'h2d:8'h2b;
      buffer[8]<=8'h30+bcd[19:16];buffer[9]<=8'h30+bcd[15:12];
      buffer[10]<=8'h30+bcd[11:8];buffer[11]<=8'h30+bcd[7:4];buffer[12]<=8'h30+bcd[3:0];
     end else begin
      buffer[7]<=8'h30+bcd[23:20];buffer[8]<=8'h30+bcd[19:16];
      buffer[9]<=8'h30+bcd[15:12];buffer[10]<=8'h30+bcd[11:8];
      buffer[11]<=8'h30+bcd[7:4];buffer[12]<=8'h30+bcd[3:0];
     end
     if(active_kind!=9 && active_kind!=11 && active_kind!=13 &&
        !(active_kind==8 && (active_ctrl>=914 && active_ctrl<=918 ||
          active_page==0 && (active_ctrl==5 || active_ctrl==6) ||
          active_page==5 && active_ctrl>=100 && active_ctrl<=103)))begin
       put_tail(13);length<=17;pos<=0;state<=4;
     end
    end
    4:if(!busy && throttle==0)begin
     if(pos==0 && frame_mode==0 && current_page!=active_page)state<=0;
     else begin uart_data<=buffer[pos];uart_start<=1;throttle<=GAP-1;byte_count<=byte_count+1'b1;state<=5;end
    end
    5:if(busy)state<=6;
    6:if(!busy)begin
     if(pos==length-1)begin
      frame_count<=frame_count+1'b1;
      if(frame_mode==0 && !active_stale && active_page==current_page)begin
       sent[active]<=snapshot;force_dirty[active]<=0;
      end
      if(frame_mode==1)begin
       heartbeat_pending<=0;
      end
      state<=0;
     end
     else begin pos<=pos+1'b1;state<=4;end
    end
    11:if(aux_valid && aux_ready)begin
     uart_data<=aux_data;uart_start<=1;aux_end<=aux_last;
     // Unconnected sideband keeps legacy one-packet fairness in old callers.
     if(aux_last)aux_frame_done<=(aux_frame_end!==1'b0);
     // busy enforces start/data/stop timing; no additional per-byte idle gap.
     byte_count<=byte_count+1'b1;state<=12;
    end
    12:if(busy)state<=13;
    13:if(!busy)begin
     state<=aux_end?0:11;
     if(aux_end)begin
      // Spectrum uses 32 short, validated single-control packets. Bound its
      // inter-packet quiet time to 100 us; other pages keep existing pacing.
      frame_count<=frame_count+1'b1;
      throttle<=(current_page==3)?CLK_HZ/10000:AUX_PACKET_PAUSE_CLKS;
      // Five short XY packets make one picture. Then scan ALL fields,
      // including changed ones, before beginning the next graphics burst.
      // Page changes still take effect at each packet boundary.
      // A switch during the final stop bit must survive this completion.
      aux_turn<=aux_stale || !aux_frame_done;
     end
    end
    default:state<=0;
   endcase
   if(cmd_valid && cmd==8'h1f)begin
    if(value[3:0]!=current_page)begin aux_turn<=1;aux_stale<=1;end
    current_page<=(value>=HMI_PAGE_COUNT)?0:value[3:0];
    if(!(page_valid===1'b1) || !page_known || value[3:0]!=current_page)begin
     force_dirty<={N{1'b1}};active_stale<=1;
    end
    if(!(page_valid===1'b1))begin page_known<=0;query_pending<=1;query_timer<=0;end
   end
   else if(cmd_valid)begin
    // Reassert authoritative selected button states after touch/release.
    // Icons (including game lamps) keep change-only transmission semantics.
    for(k=0;k<N;k=k+1)if(hmi_field_kind(k)==3)force_dirty[k]<=1;
   end
   if(page_valid===1'b1 && page_id<HMI_PAGE_COUNT)begin
    if(page_id[3:0]!=current_page)begin aux_turn<=1;aux_stale<=1;end
    current_page<=page_id[3:0];page_known<=1;query_pending<=0;
    if(!page_known || page_id[3:0]!=current_page)begin force_dirty<={N{1'b1}};active_stale<=1;end
   end
   if(screen_reset===1'b1)begin page_known<=0;query_pending<=1;query_timer<=0;force_dirty<={N{1'b1}};active_stale<=1;end
  end
 end
endmodule
