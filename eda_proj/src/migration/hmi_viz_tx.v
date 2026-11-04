// Current-page graphics producer. Entire native packets are locked by hmi_tx.
// Capture RAMs are read synchronously; there is no 128-byte register vector.
module hmi_viz_tx # (parameter integer CLK_HZ=52500000)(
 input wire clk,rst_n,input wire [3:0] page,
 input wire wave_ready,wave_bank,adsr_ready,adsr_bank,liss_ready,liss_bank,
 input wire [7:0] wave_data,adsr_data,input wire wave_valid,adsr_valid,
 input wire [15:0] liss_x,liss_y,input wire liss_valid,
 output reg wave_rd,adsr_rd,liss_rd,output reg [7:0] curve_addr,liss_addr,
 output reg wave_consumed,adsr_consumed,liss_consumed,
 input wire spec_valid,input wire [5:0] spec_addr,input wire [11:0] spec_mag,spec_peak,
 input wire dot_valid,input wire [19:0] env_observe,
 output wire valid,last,frame_end,output reg [7:0] data,input wire ready);
 // Three banks: frozen UART frame, latest complete frame, analysis writer.
 // Never queue obsolete frames or overwrite the UART's active bank.
 (* syn_ramstyle="block_ram" *) reg [13:0] bars[0:95];
 reg [13:0] bar_q;
 reg spec_new_packet;
 reg spec_collecting,spec_sending;
 reg [1:0] spec_write_bank,spec_latest_bank,spec_read_bank;
 // Freeze the newest complete analysis only when the UART accepts its header,
 // not when this producer first prepares a packet behind pending UI fields.
 wire spec_start=state==1 && op==8'h10 && packet_page==3 && pos==0 && ready && !spec_sending;
 wire [1:0] spec_reserved_bank=spec_sending?spec_read_bank:
                              (spec_start?spec_latest_bank:2'd3);
 wire spec_capture=spec_valid && page==3 &&
   (spec_collecting || spec_addr==0);
 always @(posedge clk)begin
  if(spec_capture && spec_addr<32)bars[{spec_write_bank,spec_addr[4:0]}]<={((spec_peak>100)?7'd100:spec_peak[6:0]),((spec_mag>100)?7'd100:spec_mag[6:0])};
  bar_q<=bars[{spec_read_bank,index[4:0]}];
 end
 reg [3:0] state,packet_page,last_page;
 reg [7:0] op,pos,total,pixel;
 reg [15:0] ctrl,x,y;
 reg [6:0] index;
 reg native_draw,restore_page;
 // Vendor simulator UartCmdInitHandlerList: 0x50=FG/BG RGB565,
 // 0x6a=background rectangle fill, 0x66=absolute XY connected points.
 // Max 60 points/246 bytes, below the vendor assembler's 254-byte limit.
 // Adjacent chunks share ONE endpoint, never a duplicate line segment.
 localparam [15:0] XY_FORE=16'h26dd,XY_BACK=16'h08e5;
 reg curve_append,wave_sending,adsr_sending,liss_sending;
 reg spec_have,dot_pending;
 reg [19:0] env_q;
 reg [31:0] wait_count;
 // 18 complete spectra/s; latest-complete banking drops stale analyses.
 reg [31:0] spec_wait_count;
 wire [23:0] env_scale=env_q[16:0]*7'd73;
 // Peak coordinates are registered, with a bounded constant-coefficient map.
 // 1.70 pixels/level (rounded via /128 shift); endpoints stay in the plot.
 function [15:0] peak_y;input [6:0] v;reg [14:0] t;begin
  t=({8'd0,v}<<7)+({8'd0,v}<<6)+({8'd0,v}<<4)+({8'd0,v}<<3)+{8'd0,v}+15'd64;
  peak_y=16'd230-(t>>7);
 end endfunction
 assign valid=state==1;
 assign last=pos==total-1;
 // Keep the five XY packets adjacent. An old-page packet finishing after a
 // switch must not spend the new page's graphics turn on a field-table sweep.
 assign frame_end=(page!=packet_page) ||
                  !((packet_page==4 && liss_sending &&
                     !(native_draw && op==8'h66 && index==127)) ||
                    (packet_page==3 && op==8'h10 && index<31));
 always @*begin
  data=0;
  if(pos==0)data=8'haa;
  else if(pos==total-4)data=8'hcc;
  else if(pos==total-3)data=8'h33;
  else if(pos==total-2)data=8'hc3;
  else if(pos==total-1)data=8'h3c;
   else if(native_draw)begin
    if(pos==1)data=op;
    else if(op==8'h50)case(pos)
     2:data=XY_FORE[15:8];3:data=XY_FORE[7:0];
     4:data=XY_BACK[15:8];5:data=XY_BACK[7:0];default:data=0;
    endcase
    else if(op==8'h6a)case(pos)
     2:data=0;3:data=24;4:data=0;5:data=64;
     6:data=1;7:data=196;8:data=0;9:data=218;default:data=0;
    endcase
    else if(op==8'h66)case((pos-8'd2)&8'd3)
     0:data=x[15:8];1:data=x[7:0];2:data=y[15:8];3:data=y[7:0];
    endcase
   end
   else if(pos==1)data=8'hb1;
   else if(pos==2)data=op;
  // B1 10 progress writes are ONE {page,id,value32} per 15-byte command.
  // The vendor variable-value handler consumes only the first tuple of a
  // multi-tuple B1 10 packet; never batch the 32 progress-control writes.
  // B1 28 retains its existing position-command layout.
  else if(op==8'h28 || op==8'h10)begin
   case((pos-8'd3)&8'd7)
    0:data=0;1:data={4'd0,packet_page};2:data=ctrl[15:8];3:data=ctrl[7:0];
    4:data=(op==8'h28)?x[15:8]:8'd0;
    5:data=(op==8'h28)?x[7:0]:8'd0;
    6:data=(op==8'h28)?y[15:8]:8'd0;
    7:data=(op==8'h28)?y[7:0]:x[7:0];
   endcase
  end
  else if(pos==3)data=0;
  else if(pos==4)data={4'd0,packet_page};
  else if(pos==5)data=ctrl[15:8];
  else if(pos==6)data=ctrl[7:0];
  else if(op==8'h32)begin
   if(pos==7 || pos==8)data=0;
   else if(pos==9)data=(packet_page==0)?64:128;
   else data=pixel;
  end
 end
 task packet;input [7:0] code,size;input [15:0] id;begin
   op<=code;total<=size;ctrl<=id;pos<=0;packet_page<=page;state<=1;native_draw<=0;
 end endtask
  task xy_packet;input [7:0] code,size;begin
   op<=code;total<=size;pos<=0;packet_page<=4;state<=1;native_draw<=1;
  end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=0;packet_page<=0;last_page<=15;op<=0;pos<=0;total<=0;ctrl<=0;x<=0;y<=0;index<=0;pixel<=0;
   wave_rd<=0;adsr_rd<=0;liss_rd<=0;curve_addr<=0;liss_addr<=0;
   wave_consumed<=0;adsr_consumed<=0;liss_consumed<=0;
   curve_append<=0;wave_sending<=0;adsr_sending<=0;liss_sending<=0;
   spec_have<=0;spec_collecting<=0;spec_sending<=0;dot_pending<=0;env_q<=0;wait_count<=0;
   spec_write_bank<=0;spec_latest_bank<=1;spec_read_bank<=2;spec_new_packet<=0;spec_wait_count<=0;
   native_draw<=0;restore_page<=0;
  end else begin
   wave_rd<=0;adsr_rd<=0;liss_rd<=0;
   wave_consumed<=0;adsr_consumed<=0;liss_consumed<=0;
   if(spec_capture)begin
    if(spec_addr==31)begin
     spec_have<=1;spec_collecting<=0;spec_latest_bank<=spec_write_bank;
     if(spec_write_bank!=0 && spec_reserved_bank!=0)spec_write_bank<=0;
     else if(spec_write_bank!=1 && spec_reserved_bank!=1)spec_write_bank<=1;
     else spec_write_bank<=2;
    end
    else spec_collecting<=1;
   end
   if(dot_valid)begin dot_pending<=1;env_q<=env_observe;end
   if(spec_start)begin
    spec_sending<=1;spec_read_bank<=spec_latest_bank;
    spec_wait_count<=CLK_HZ/18;
    if(!(spec_capture && spec_addr==31))spec_have<=0;
   end
   if(wait_count!=0)wait_count<=wait_count-1'b1;
   if(spec_wait_count!=0)spec_wait_count<=spec_wait_count-1'b1;
   case(state)
    0:begin
     if(page!=last_page)begin
      // The UART may still be shifting the last byte even after this producer
      // handed it off. Restore on EVERY exit, including that final-stop window.
      if(last_page==4 && page!=4)restore_page<=1;
      last_page<=page;index<=0;curve_append<=0;wave_sending<=0;adsr_sending<=0;liss_sending<=0;
      spec_have<=0;spec_collecting<=0;spec_sending<=0;spec_new_packet<=0;spec_wait_count<=0;
     end else if(restore_page)begin
      // Raw graphics target the visible framebuffer. Restore the newly selected
      // page after finishing an in-flight old-page packet (never truncate UART).
      restore_page<=0;packet(8'h00,9,0);
     end else if((page==2 || page==0) && wave_ready && !wave_consumed)begin
      wave_sending<=1;
      packet(curve_append?8'h32:8'h33,curve_append?((page==0)?8'd78:8'd142):8'd12,60);
     end else if(page==5 && adsr_ready && !adsr_consumed)begin
      adsr_sending<=1;
      packet(curve_append?8'h32:8'h33,curve_append?8'd142:8'd12,60);
     end else if(page==4 && liss_ready && !liss_consumed && wait_count==0)begin
      liss_sending<=1;index<=0;
      xy_packet(8'h50,10);
     end else if(page==3 && (spec_sending || (spec_have && spec_wait_count==0)))begin
      // 32 manufacturer-compatible 15-byte packets, one real value each.
      // Freeze one complete analysis through all 32 independent controls.
      spec_new_packet<=1;state<=8;
     end
     else if(page==5 && dot_pending)begin
      x<=20+((env_q[19:17]>4)?16'd208:({13'd0,env_q[19:17]}*16'd52));y<=249-env_scale[23:16];
      dot_pending<=0;packet(8'h28,15,61);
     end
    end
    1:if(ready)begin
      // Pace from the accepted UART header, not an earlier prepared frame.
      if(native_draw && op==8'h50 && pos==0)wait_count<=CLK_HZ/15;
     if(last)begin
      state<=0;
       if(packet_page==4 && page!=4 && native_draw)begin
        restore_page<=1;liss_sending<=0;index<=0;
       end else if(liss_sending && native_draw)begin
        if(op==8'h50)xy_packet(8'h6a,14);
        else if(op==8'h6a)begin
         liss_addr<={liss_bank,7'd0};liss_rd<=1;state<=4;
        end else if(index==127)begin
         index<=0;liss_consumed<=1;liss_sending<=0;
        end else begin
         liss_addr<={liss_bank,index};liss_rd<=1;state<=4;
        end
       end else if(op==8'h33)curve_append<=1;
      else if(op==8'h32)begin
       curve_append<=0;
       if(wave_sending)wave_consumed<=1;
       if(adsr_sending)adsr_consumed<=1;
       wave_sending<=0;adsr_sending<=0;
      end else if(packet_page==3 && op==8'h10)begin
       if(index==31)begin index<=0;spec_sending<=0;end
       else index<=index+1'b1;
      end
     end else begin
      pos<=pos+1'b1;
      if(spec_start)state<=10;
       else if(!native_draw && op==8'h32 && pos>=9 && pos<total-5)begin
       curve_addr<=((wave_sending?wave_bank:adsr_bank)?8'd128:8'd0)+((packet_page==0)?((pos-8'd9)<<1):(pos-8'd9));
       if(wave_sending)wave_rd<=1;else adsr_rd<=1;
       state<=2;
       end else if(native_draw && op==8'h66 && pos>=5 &&
                   ((pos-8'd2)&8'd3)==3 && pos<total-5)begin
        index<=index+1'b1;liss_addr<={liss_bank,index+7'd1};liss_rd<=1;state<=6;
      end
     end
    end
    2:state<=3;
    3:if((wave_sending && wave_valid) || (adsr_sending && adsr_valid))begin
     pixel<=wave_sending?wave_data:adsr_data;state<=1;
    end
    4:if(liss_valid)begin
     x<=liss_x;y<=liss_y;
     xy_packet(8'h66,(index<68)?8'd246:((8'd128-{1'b0,index})<<2)+8'd6);
    end
    6:if(liss_valid)begin x<=liss_x;y<=liss_y;state<=1;end
    8:state<=9;
    9:begin
     x<={9'd0,bar_q[6:0]};
     ctrl<=16'd101+index;
     if(spec_new_packet)begin
      spec_new_packet<=0;packet(8'h10,15,16'd101+index);
     end else state<=1;
    end
    10:state<=11;
    11:begin x<={9'd0,bar_q[6:0]};state<=1;end
    default:state<=0;
   endcase
  end
 end
endmodule
