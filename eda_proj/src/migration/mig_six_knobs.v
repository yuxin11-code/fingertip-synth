// Continuous absolute pot controls. Slots: volume, equal-power blend,
// stereo balance, vibrato depth, vibrato rate, auto-return pitch bend.
module mig_six_knobs #(
 parameter integer CONTROL_FRAMES=50,
 parameter integer BEND_HOLD_MS=200,BEND_RETURN_MS=100,
 parameter integer BEND_TRAVEL_DEGREES=540,BEND_DEAD_DEGREES=30,
 parameter integer RATE_STEP_MIN=259428,RATE_STEP_SPAN=432381
)(input wire clk,rst_n,frame_tick,input wire [5:0] write_mask,
 input wire [101:0] write_values,input wire [16:0] fallback_volume,
 input wire [17:0] base_pitch,
 input wire hmi_valid,input wire [7:0] hmi_cmd,input wire [15:0] hmi_value,
 input wire volume_up_event,volume_down_event,
 input wire [95:0] raw_values,calibration_low,calibration_high,
 output wire [84:0] targets,actual_values,
 output wire [16:0] master,blend,balance,
 output reg [17:0] modulated_pitch);
 reg [16:0] target[0:4],value[0:4];
 reg [4:0] locked;
 reg [15:0] anchor[0:4],previous_raw[0:4],span_at_lock[0:4],cross_at[0:4];
 wire [15:0] slider=(hmi_value>1000)?16'd1000:hmi_value;
 wire [16:0] remote_target;
 hmi_scale_exact #(.KIND(0)) exact_volume(.slider(slider),.scaled(remote_target));
 genvar g;
 generate for(g=0;g<5;g=g+1)begin: export_values
  assign targets[g*17+:17]=target[g];
  assign actual_values[g*17+:17]=value[g];
 end endgenerate
 reg bend_seen;
 reg [16:0] bend_anchor;
 reg signed [17:0] bend_target_q8,bend_value_q8;
 reg [15:0] bend_idle;
 reg [7:0] control_count;
 reg [31:0] phase;
 // Calibrated pot travel: 0..30 degrees neutral, rising to +200 cents at
 // the midpoint of the remaining travel, then falling to -200 cents.
 // All divisions below are elaboration-time constants; the curve multiply
 // is registered separately from the movement/idle detector.
 localparam integer BEND_DEAD=(65536*BEND_DEAD_DEGREES+BEND_TRAVEL_DEGREES/2)/BEND_TRAVEL_DEGREES;
 localparam integer BEND_PEAK=(65536+BEND_DEAD)/2;
 localparam [17:0] BEND_RISE_SCALE=(64'd51200*65536+(BEND_PEAK-BEND_DEAD)/2)/(BEND_PEAK-BEND_DEAD);
 localparam [17:0] BEND_FALL_SCALE=(64'd102400*65536+(65536-BEND_PEAK)/2)/(65536-BEND_PEAK);
 wire [16:0] raw_bend=(write_values[101:85]>65536)?17'd65536:write_values[101:85];
 reg [2:0] bend_map_valid;
 reg [16:0] bend_delta0,bend_raw0,bend_raw1,bend_raw2;
 reg bend_falling0,bend_falling1;
 (* syn_dspstyle="dsp" *) reg [35:0] bend_product1;
 reg signed [17:0] bend_command2;
 wire [17:0] bend_magnitude=(bend_product1+36'd32768)>>16;
 wire [16:0] movement=(bend_raw2>bend_anchor)?bend_raw2-bend_anchor:bend_anchor-bend_raw2;
 wire [48:0] rate_product=value[4]*RATE_STEP_SPAN;
 wire [31:0] phase_step=RATE_STEP_MIN+(rate_product>>16);
 wire [31:0] depth_product=value[3]*15'd12800; // 0..50 cents in Q8
 wire signed [16:0] depth_q8=$signed({1'b0,depth_product[31:16]});
 wire signed [15:0] sine_q;
 wire signed [32:0] vibrato_product=sine_q*depth_q8;
 wire signed [18:0] total_q8=$signed(bend_value_q8)+(vibrato_product>>>15);
 wire signed [18:0] cents_floor=total_q8>>>8;
 wire [8:0] cents_address=(cents_floor< -250)?9'd0:(cents_floor>250)?9'd500:(cents_floor+19'sd250);
 wire [16:0] factor_q16;
 mig_expression_rom rom(.clk(clk),.phase(phase[31:24]),.cents_address(cents_address),
  .sine_q(sine_q),.factor_q16(factor_q16));
 reg [34:0] pitch_product;
 assign master=value[0];assign blend=value[1];assign balance=value[2];
 function [16:0] slew;
  input [16:0] current,wanted;
  reg [16:0] diff,step;
  begin
   diff=(wanted>current)?wanted-current:current-wanted;
   step=(diff>>4)+(|diff[3:0]);
   slew=(wanted>current)?current+step:current-step;
  end
 endfunction
 function signed [17:0] bend_slew;
  input signed [17:0] current,wanted;
  input integer divisor;
  reg signed [18:0] diff,step;
  begin
   diff= $signed(wanted)-$signed(current);step=diff/divisor;
   if(diff!=0 && step==0)step=(diff>0)?1:-1;
   bend_slew=current+step;
  end
 endfunction
 integer i;
 reg [15:0] current_raw,raw_span,raw_move;
 reg [32:0] cross_product;
 reg takeover;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   bend_seen<=0;bend_anchor<=32768;bend_target_q8<=0;bend_value_q8<=0;
   bend_map_valid<=0;bend_delta0<=0;bend_raw0<=0;bend_raw1<=0;bend_raw2<=0;
   bend_falling0<=0;bend_falling1<=0;bend_product1<=0;bend_command2<=0;
   bend_idle<=BEND_HOLD_MS;phase<=0;control_count<=0;pitch_product<=35'd4294967296;modulated_pitch<=65536;
   locked<=0;
   for(i=0;i<5;i=i+1)begin target[i]<=(i==3)?0:32768;value[i]<=(i==3)?0:32768;
    anchor[i]<=0;previous_raw[i]<=0;span_at_lock[i]<=0;cross_at[i]<=0;end
  end else begin
   bend_map_valid<={bend_map_valid[1:0],write_mask[5]};
   if(write_mask[5])begin
    bend_raw0<=raw_bend;
    bend_falling0<=raw_bend>BEND_PEAK;
    bend_delta0<=(raw_bend<=BEND_DEAD)?17'd0:
      (raw_bend<=BEND_PEAK)?raw_bend-BEND_DEAD:raw_bend-BEND_PEAK;
   end
   if(bend_map_valid[0])begin
    bend_product1<=bend_delta0*(bend_falling0?BEND_FALL_SCALE:BEND_RISE_SCALE);
    bend_raw1<=bend_raw0;bend_falling1<=bend_falling0;
   end
   if(bend_map_valid[1])begin
    bend_raw2<=bend_raw1;
    if(bend_raw1<=BEND_DEAD)bend_command2<=0;
    else if(bend_raw1==BEND_PEAK)bend_command2<=18'sd51200;
    else if(bend_raw1==65536)bend_command2<=-18'sd51200;
    else if(bend_falling1)bend_command2<=18'sd51200-$signed(bend_magnitude);
    else bend_command2<=$signed(bend_magnitude);
   end
   // Pipeline the pitch multiply; no audio-clock combinational multiply path.
   pitch_product<=base_pitch*factor_q16;
   modulated_pitch<=(pitch_product[34:16]>262143)?18'd262143:pitch_product[33:16];
   for(i=0;i<5;i=i+1)begin
    current_raw=raw_values[i*16+:16];
    raw_move=(current_raw>anchor[i])?current_raw-anchor[i]:anchor[i]-current_raw;
    // Frozen raw endpoints prevent calibration remapping from seizing control.
    takeover=(span_at_lock[i]>=32) &&
      ((raw_move*32'd100>span_at_lock[i]*32'd3) ||
       (current_raw!=previous_raw[i] &&
        ((previous_raw[i]<=cross_at[i] && current_raw>=cross_at[i]) ||
         (previous_raw[i]>=cross_at[i] && current_raw<=cross_at[i]))));
    if(write_mask[i])begin
     previous_raw[i]<=current_raw;
     if(!locked[i] || takeover)begin
      locked[i]<=0;
      target[i]<=(write_values[i*17+:17]>65536)?17'd65536:write_values[i*17+:17];
     end
    end
    // All five targets allow screen writes. Keep the same soft takeover:
    // a stationary absolute pot holds the screen target until it moves.
    // The retired KEY1/KEY2 volume event ports remain ignored.
    if(hmi_valid && hmi_cmd==8'h06+i)begin
     locked[i]<=1;anchor[i]<=current_raw;previous_raw[i]<=current_raw;
     raw_span=calibration_high[i*16+:16]-calibration_low[i*16+:16];
     span_at_lock[i]<=raw_span;
     target[i]<=remote_target;
     cross_product=remote_target*raw_span;
     cross_at[i]<=calibration_low[i*16+:16]+(cross_product>>16);
    end
    // Calibration may be completed AFTER a screen write. Establish a new
    // raw anchor on its first valid sample; do not seize on that sample.
    if(locked[i] && span_at_lock[i]<32 && write_mask[i])begin
     raw_span=calibration_high[i*16+:16]-calibration_low[i*16+:16];
     if(raw_span>=32)begin
      anchor[i]<=current_raw;previous_raw[i]<=current_raw;span_at_lock[i]<=raw_span;
      cross_product=target[i]*raw_span;
      cross_at[i]<=calibration_low[i*16+:16]+(cross_product>>16);
     end
    end
   end
   if(frame_tick)begin
    phase<=phase+phase_step;
    if(control_count>=CONTROL_FRAMES-1)begin
     control_count<=0;
     value[0]<=slew(value[0],target[0]);
     for(i=1;i<5;i=i+1)value[i]<=slew(value[i],target[i]);
     if(bend_idle<BEND_HOLD_MS)bend_idle<=bend_idle+1;
     if(bend_idle>=BEND_HOLD_MS)begin bend_target_q8<=0;bend_value_q8<=bend_slew(bend_value_q8,18'sd0,BEND_RETURN_MS);end
     else bend_value_q8<=bend_slew(bend_value_q8,bend_target_q8,20);
    end else control_count<=control_count+1;
   end
   // Polling an unmoved absolute pot must NOT cancel auto-return.
   if(bend_map_valid[2])begin
    if(!bend_seen)begin bend_seen<=1;bend_anchor<=bend_raw2;end
    else if(movement>=256)begin bend_anchor<=bend_raw2;bend_target_q8<=bend_command2;bend_idle<=0;end
   end
  end
 end
endmodule
