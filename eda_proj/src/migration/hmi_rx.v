// Dual receiver: keeps the proven 5A A5 command frame and also accepts the
// CF-Design V2.16 native AA B1 ... CC 33 C3 3C control notifications.
module hmi_rx #(parameter integer CLK_HZ=52500000)(
 input wire selected_panel,clear_keys,
 input wire clk,rst_n,byte_valid,frame_error,input wire [7:0] byte_data,
 output reg cmd_valid,output reg [7:0] cmd,output reg [15:0] value,
 output reg frame_valid,frame_invalid,page_valid,screen_reset,
 output reg [15:0] page_id);
 `define HMI_DEFINE_RX_TABLE
 `include "hmi_defs.vh"
 `undef HMI_DEFINE_RX_TABLE
 localparam integer TIMEOUT=(CLK_HZ/1000)*5;
 reg [2:0] state;
 reg [31:0] idle_count;
 reg [7:0] command,hi,lo;
 reg [7:0] native_frame[0:31];
 reg [5:0] native_len;
 reg native_active,native_overflow;
 reg [31:0] native_tail,native_idle;
 reg native_panel;
 reg [15:0] native_left,native_right;
 wire native_tail_hit=({native_tail[23:0],byte_data}==32'hcc33c33c);
 wire [15:0] native_page={native_frame[3],native_frame[4]};
 wire [15:0] native_ctrl={native_frame[5],native_frame[6]};
 wire [31:0] native_slider={native_frame[8],native_frame[9],native_frame[10],native_frame[11]};
 // Hardware manual specifies u32; CF-Design V2.16 virtual screen emits u16.
 wire [15:0] native_slider_value=(native_len==13)?{native_frame[8],native_frame[9]}:native_slider[15:0];
 wire [15:0] native_key_bit=16'h0001 << (native_ctrl-16'd100);
 integer i;

 task emit;
  input [7:0] c;input [15:0] v;
  begin cmd<=c;value<=v;cmd_valid<=1'b1;end
 endtask

 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   state<=0;idle_count<=0;command<=0;hi<=0;lo<=0;cmd_valid<=0;cmd<=0;value<=0;
   native_len<=0;native_active<=0;native_overflow<=0;native_tail<=0;native_idle<=0;
   native_panel<=0;native_left<=0;native_right<=0;
   frame_valid<=0;frame_invalid<=0;page_valid<=0;page_id<=0;screen_reset<=0;
   for(i=0;i<32;i=i+1)native_frame[i]<=0;
  end else begin
   cmd_valid<=0;frame_valid<=0;frame_invalid<=0;page_valid<=0;screen_reset<=0;
   // Physical board selection also invalidates the screen's held-key mask.
   if((selected_panel===1'b0 || selected_panel===1'b1) && selected_panel!=native_panel)begin
    native_panel<=selected_panel;native_left<=0;native_right<=0;
   end
   if(frame_error)begin
    frame_invalid<=1;state<=0;idle_count<=0;native_active<=0;native_len<=0;native_tail<=0;native_idle<=0;
   end else begin
    if(state!=0 && !byte_valid)begin
     if(idle_count>=TIMEOUT)begin state<=0;idle_count<=0;frame_invalid<=1;end
     else idle_count<=idle_count+1'b1;
    end
    if(native_active && !byte_valid)begin
     if(native_idle>=TIMEOUT)begin frame_invalid<=1;native_active<=0;native_len<=0;native_tail<=0;native_idle<=0;end
     else native_idle<=native_idle+1'b1;
    end
    if(byte_valid)begin
     idle_count<=0;native_idle<=0;
     if(native_active)begin
      native_tail<={native_tail[23:0],byte_data};
      if(native_len<32)begin native_frame[native_len]<=byte_data;native_len<=native_len+1'b1;end
      else native_overflow<=1;
      if(native_tail_hit)begin
       native_active<=0;native_tail<=0;
       if(!native_overflow && native_len==5 && (native_frame[1]==8'h07 || native_frame[1]==8'h55))begin
        frame_valid<=1;
        if(native_frame[1]==8'h07)begin
         screen_reset<=1;native_left<=0;native_right<=0;
        end
       end else if(!native_overflow && native_frame[1]==HMI_CMD_CONTROL)begin
        if(native_frame[2]==HMI_OP_PAGE_READ && native_len==8 && native_page<HMI_PAGE_COUNT)begin
        frame_valid<=1;page_valid<=1;page_id<=native_page;emit(8'h1f,native_page);
        if(native_page!=1)begin native_left<=0;native_right<=0;end
        end else if(native_frame[2]==8'h11 && native_len==13 && native_frame[7]==8'h10 && native_frame[8]<=1 && native_frame[9]<=1 && native_page<HMI_PAGE_COUNT)begin
         frame_valid<=1;
         // Teammate's c48 request is accepted as an alias.  The installed
         // page keeps c75 and follows its unchanged generated-table mapping.
         if(native_page==16'd7 && native_ctrl==16'd48)begin
          page_valid<=1;page_id<=native_page;
          if(native_frame[9]==1)emit(8'h57,16'd1);
         end else if(hmi_native_type(native_page,native_ctrl)!=0)begin
          if(hmi_native_cmd(native_page,native_ctrl)!=8'h1f)begin page_valid<=1;page_id<=native_page;end
          if(hmi_native_type(native_page,native_ctrl)==3)begin
           if((selected_panel===1'b1) || (selected_panel!==1'b0 && native_panel))begin
            native_right<=native_frame[9]?native_right|native_key_bit:native_right&~native_key_bit;
            emit(8'h31,native_frame[9]?native_right|native_key_bit:native_right&~native_key_bit);
           end else begin
            native_left<=native_frame[9]?native_left|native_key_bit:native_left&~native_key_bit;
            emit(8'h30,native_frame[9]?native_left|native_key_bit:native_left&~native_key_bit);
           end
          end else if(hmi_native_toggle(native_page,native_ctrl))emit(hmi_native_cmd(native_page,native_ctrl),{15'd0,native_frame[9][0]});
          else if(native_frame[9]!=0)begin
           emit(hmi_native_cmd(native_page,native_ctrl),hmi_native_value(native_page,native_ctrl));
           if(hmi_native_cmd(native_page,native_ctrl)==8'h15)begin native_panel<=hmi_native_value(native_page,native_ctrl);native_left<=0;native_right<=0;end
           if(hmi_native_cmd(native_page,native_ctrl)==8'h1f)begin native_left<=0;native_right<=0;end
          end else emit(8'h7f,0);
         end
        end else if(native_frame[2]==8'h11 && native_frame[7]==8'h13 && (native_len==15 || native_len==13) && native_page<HMI_PAGE_COUNT && hmi_native_type(native_page,native_ctrl)==2)begin
         frame_valid<=1;page_valid<=1;page_id<=native_page;
         emit(hmi_native_cmd(native_page,native_ctrl),native_slider_value-hmi_native_offset(native_page,native_ctrl));
        end else frame_invalid<=1;
       end else frame_invalid<=1;
       native_len<=0;native_overflow<=0;
      end
     end else if(state==0 && byte_data==HMI_FRAME_HEAD)begin
      native_frame[0]<=byte_data;native_len<=1;native_active<=1;native_overflow<=0;native_tail<=0;
     end else begin
      case(state)
       0:if(byte_data==8'h5a)state<=1;
       1:if(byte_data==8'ha5)state<=2;else state<=(byte_data==8'h5a)?1:0;
       2:begin command<=byte_data;state<=3;end
       3:begin hi<=byte_data;state<=4;end
       4:begin lo<=byte_data;state<=5;end
       5:begin state<=0;if(byte_data==(command^hi^lo))begin emit(command,{hi,lo});frame_valid<=1;end else frame_invalid<=1;end
       default:state<=0;
      endcase
     end
    end
   end
   // Highest priority: never let a tail byte overwrite watchdog key clearing.
   // Discard the partial native packet so it cannot restore a stale held mask.
   if(clear_keys===1'b1)begin
    native_left<=0;native_right<=0;
    native_active<=0;native_len<=0;native_tail<=0;native_idle<=0;native_overflow<=0;
    cmd_valid<=0;page_valid<=0;frame_valid<=0;
   end
  end
 end
endmodule
