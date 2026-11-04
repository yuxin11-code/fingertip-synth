// Musical actions, never PCM: {delta milliseconds[15:0], 32 note gates}.
// The final entry is an all-off EOT identified by its position (length-1),
// so every 48-bit value remains available for ordinary events/keepalives.
module mig_action_recorder #(
 parameter integer CLK_HZ=52500000,DEBOUNCE_MS=15,
 parameter integer DEPTH=32768,LOOP_PLAYBACK=0,LOOP_GAP_MS=1
)(
 input wire clk,rst_n,record_n,play_n,input wire suspend,
 input wire hmi_valid,input wire [7:0] hmi_cmd,input wire [15:0] hmi_value,
 output reg loop_enabled,
 output reg [31:0] duration_ms,
 output wire [31:0] elapsed_ms,
 input wire [31:0] live_keys,
 output reg [31:0] replay_keys,
 output wire record_stable,play_stable,
 output wire recording,playing,record_led,play_led,
 output reg full,
 output reg [$clog2(DEPTH):0] length
);
 localparam integer AW=$clog2(DEPTH);
 localparam integer MS_CYCLES=(CLK_HZ/1000<1)?1:CLK_HZ/1000;
 localparam integer MW=(MS_CYCLES<2)?1:$clog2(MS_CYCLES);
 localparam integer DB_CYCLES=(MS_CYCLES*DEBOUNCE_MS<1)?1:MS_CYCLES*DEBOUNCE_MS;
 localparam integer DW=(DB_CYCLES<2)?1:$clog2(DB_CYCLES+1);
 localparam [1:0] IDLE=0,RECORD=1,PLAY=2;
 reg [1:0] state;
 reg [1:0] btn_meta,btn_sync,btn_stable,btn_previous;
 reg [DW-1:0] db_count[0:1];
 wire record_press=btn_previous[0] & ~btn_stable[0];
 wire play_press=btn_previous[1] & ~btn_stable[1];
 assign record_stable=~btn_stable[0];assign play_stable=~btn_stable[1];
 assign recording=(state==RECORD);assign playing=(state==PLAY);
 reg [MW-1:0] ms_div;
 reg [31:0] now_ms,last_record_ms;
 wire [31:0] elapsed=now_ms-last_record_ms;
 reg [31:0] previous_keys;
 reg valid,finish_full;
 // No reset or initialization of the RAM array: infer synchronous BSRAM.
 (* syn_ramstyle="block_ram" *) reg [47:0] memory[0:DEPTH-1];
 reg wr_en;reg [AW-1:0] wr_addr,rd_addr,play_index;
 reg [47:0] wr_data,rd_data,event_word;
 reg [1:0] read_phase;
 reg [31:0] play_base_ms,due_ms;
 reg [31:0] record_start_ms,play_start_ms;
 assign elapsed_ms=playing?(now_ms-play_start_ms):32'd0;
 // Keep the physical buttons usable when an older standalone integration
 // leaves the optional HMI port unconnected (Z/X).
 wire hmi_active=(hmi_valid===1'b1);
 wire paused=(suspend===1'b1);
 wire remote_record=hmi_active && hmi_cmd==8'h10;
 wire remote_play=hmi_active && hmi_cmd==8'h11;
 always @(posedge clk)begin
  if(wr_en)memory[wr_addr]<=wr_data;
  rd_data<=memory[rd_addr];
 end
 assign record_led=full?now_ms[6]:(recording && now_ms[8]);
 assign play_led=playing;
 integer b;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   btn_meta<=3;btn_sync<=3;btn_stable<=3;btn_previous<=3;
   for(b=0;b<2;b=b+1)db_count[b]<=0;
   ms_div<=0;now_ms<=0;
  end else begin
   btn_meta<={play_n,record_n};btn_sync<=btn_meta;btn_previous<=btn_stable;
   for(b=0;b<2;b=b+1)begin
    if(btn_sync[b]==btn_stable[b])db_count[b]<=0;
    else if(db_count[b]>=DB_CYCLES-1)begin btn_stable[b]<=btn_sync[b];db_count[b]<=0;end
    else db_count[b]<=db_count[b]+1'b1;
   end
   if(!paused)begin
    if(ms_div==MS_CYCLES-1)begin ms_div<=0;now_ms<=now_ms+1'b1;end
    else ms_div<=ms_div+1'b1;
   end
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;valid<=0;full<=0;finish_full<=0;length<=0;
   loop_enabled<=(LOOP_PLAYBACK!=0);duration_ms<=0;record_start_ms<=0;play_start_ms<=0;
   replay_keys<=0;previous_keys<=0;last_record_ms<=0;
   wr_en<=0;wr_addr<=0;wr_data<=0;rd_addr<=0;play_index<=0;
   read_phase<=0;event_word<=0;play_base_ms<=0;due_ms<=0;
  end else begin
   wr_en<=0;
   if(!paused)begin
   if(hmi_valid && hmi_cmd==8'h13)loop_enabled<=(hmi_value!=0);
   if(recording)duration_ms<=now_ms-record_start_ms;
   case(state)
    IDLE:begin
     replay_keys<=0;
     // K3 wins simultaneous idle commands; K4 cannot erase a take.
     if(hmi_valid && hmi_cmd==8'h14)begin valid<=0;length<=0;full<=0;duration_ms<=0;end
     else if((record_press && !remote_record) || (remote_record && hmi_value!=0))begin
      state<=RECORD;valid<=0;full<=0;finish_full<=0;length<=1;
      record_start_ms<=now_ms;duration_ms<=0;
      previous_keys<=live_keys;last_record_ms<=now_ms;
      wr_en<=1;wr_addr<=0;wr_data<={16'd0,live_keys};
     end else if(((play_press && !remote_play) || (remote_play && hmi_value!=0)) && valid)begin
      state<=PLAY;rd_addr<=0;play_index<=0;read_phase<=0;play_base_ms<=now_ms;
      play_start_ms<=now_ms;
     end
    end
    RECORD:begin
     if(finish_full || (record_press && !remote_record) || (remote_record && hmi_value==0))begin
      // Always reserve one entry for EOT; stopping releases only replay.
      wr_en<=1;wr_addr<=length[AW-1:0];wr_data<={elapsed[15:0],32'd0};
      length<=length+1'b1;valid<=1;state<=IDLE;finish_full<=0;
      if(finish_full)full<=1;
     end else if(elapsed>=65535 || live_keys!=previous_keys)begin
      wr_en<=1;wr_addr<=length[AW-1:0];length<=length+1'b1;
      if(elapsed>=65535)begin
       // A long wait repeats the previous bitmap; ZERO would release notes.
       wr_data<={16'hffff,previous_keys};last_record_ms<=last_record_ms+32'd65535;
      end else begin
       wr_data<={elapsed[15:0],live_keys};previous_keys<=live_keys;last_record_ms<=now_ms;
      end
      if(length==DEPTH-2)finish_full<=1;
     end
    end
    PLAY:begin
     if((play_press && !remote_play) || (remote_play && hmi_value==0))begin state<=IDLE;replay_keys<=0;read_phase<=0;end
     else case(read_phase)
      0:read_phase<=1; // address -> synchronous RAM -> registered data
      1:begin event_word<=rd_data;due_ms<=play_base_ms+{16'd0,rd_data[47:32]};read_phase<=2;end
      2:if($signed(now_ms-due_ms)>=0)begin
       if({1'b0,play_index}==length-1'b1)begin
        replay_keys<=0;
        if(loop_enabled)begin
         rd_addr<=0;play_index<=0;read_phase<=0;play_base_ms<=due_ms+LOOP_GAP_MS;
         play_start_ms<=due_ms+LOOP_GAP_MS;
        end else begin state<=IDLE;read_phase<=0;end
       end else begin
        replay_keys<=event_word[31:0];play_base_ms<=due_ms;
        play_index<=play_index+1'b1;rd_addr<=play_index+1'b1;read_phase<=0;
       end
      end
      default:read_phase<=0;
     endcase
    end
    default:begin state<=IDLE;replay_keys<=0;end
   endcase
   end
  end
 end
endmodule
