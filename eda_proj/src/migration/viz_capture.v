// Registered observation capture with synchronous block-RAM read ports.
// The packed wave_data/adsr_data outputs are retained only as a compatibility
// shim for standalone simulation benches. The top-level sets LEGACY_PACKED=0
// and uses the one-cycle RAM read ports instead.
`default_nettype none
module viz_capture #(
    parameter integer WAVE_POINTS = 128,
    parameter integer LISS_POINTS = 128,
    parameter integer FS_TICKS = 993,
    parameter integer LEGACY_PACKED = 1,
    parameter integer REAL_ADSR = 0
)(
    input wire clk, input wire rst_n, input wire frame_tick,
    input wire sample_valid, input wire signed [15:0] wave_sample,
    input wire signed [15:0] dry_sample, input wire signed [15:0] wet_sample,
    input wire signed [15:0] voice_a_sample, input wire signed [15:0] voice_b_sample,
    input wire [1:0] wave_decim, input wire wave_arm, input wire wave_consumed,
    input wire liss_arm, input wire liss_mode_a, input wire [1:0] liss_voice_count,
    input wire liss_consumed,output reg liss_ready,
    input wire adsr_arm, input wire adsr_consumed, input wire [3:0] adsr_a, input wire [3:0] adsr_d,
    input wire [3:0] adsr_s, input wire [3:0] adsr_r,
    input wire [16:0] env_value, input wire [2:0] env_stage,

    output reg wave_ready, output reg [1023:0] wave_data,
    input wire wave_mem_rd_en, input wire [7:0] wave_mem_rd_addr,
    output reg [7:0] wave_mem_rd_data, output reg wave_mem_rd_valid,
    output reg wave_mem_bank,

    output reg liss_valid, output reg [6:0] liss_index,
    output reg [15:0] liss_x, output reg [15:0] liss_y, output reg liss_done,
    input wire liss_mem_rd_en, input wire [7:0] liss_mem_rd_addr,
    output reg [15:0] liss_mem_rd_x, output reg [15:0] liss_mem_rd_y,
    output reg liss_mem_rd_valid, output reg liss_mem_bank,

    output reg adsr_ready, output reg [1023:0] adsr_data,
    input wire adsr_mem_rd_en, input wire [7:0] adsr_mem_rd_addr,
    output reg [7:0] adsr_mem_rd_data, output reg adsr_mem_rd_valid,
    output reg adsr_mem_bank,
    output reg adsr_point_valid, output reg [15:0] adsr_point_x,
    output reg [15:0] adsr_point_y, output reg [2:0] adsr_point_stage
);
    (* syn_ramstyle = "block_ram" *) reg signed [15:0] wave_raw_mem [0:255];
    (* syn_ramstyle = "block_ram" *) reg [7:0] wave_mem [0:255];
    (* syn_ramstyle = "block_ram" *) reg [15:0] liss_raw_x_mem [0:255];
    (* syn_ramstyle = "block_ram" *) reg [15:0] liss_raw_y_mem [0:255];
    (* syn_ramstyle = "block_ram" *) reg [15:0] liss_x_mem [0:255];
    (* syn_ramstyle = "block_ram" *) reg [15:0] liss_y_mem [0:255];
    (* syn_ramstyle = "block_ram" *) reg [7:0] adsr_mem [0:255];

    localparam [2:0] W_IDLE=0, W_CAPTURE=1, W_MAP_READ=2, W_MAP_WRITE=3, W_WAIT=4;
    reg [2:0] wave_state;
    reg wave_wr_bank, wave_prev_sign;
    reg [7:0] wave_pos, wave_map_idx, wave_dec_cnt;
    reg [15:0] wave_no_trigger, wave_peak, wave_peak_latched;
    reg signed [15:0] wave_raw_rd_q;
    localparam [2:0] L_CAPTURE=0, L_MAP_READ=1, L_MAP_SCALE=2, L_MAP_WRITE=3, L_WAIT=4;
    reg [2:0] liss_state;
    reg liss_wr_bank, liss_source_a;
    reg [6:0] liss_pos;
    reg [1:0] liss_warmup;
    reg signed [15:0] liss_x_d1,liss_x_d2,liss_y_d1,liss_y_d2;
    reg [15:0] liss_peak;
    reg [3:0] liss_gain;
    reg signed [15:0] liss_raw_x_q, liss_raw_y_q;
    reg signed [15:0] liss_scaled_x_q, liss_scaled_y_q;
    wire liss_use_a=(liss_pos==0)?(liss_mode_a&&(liss_voice_count>=2)):liss_source_a;
    wire signed [15:0] liss_input_x=liss_use_a?voice_a_sample:dry_sample;
    wire signed [15:0] liss_input_y=liss_use_a?voice_b_sample:wet_sample;
    // Identical linear-phase [1 2 1]/4 FIR on BOTH display axes.  No decimation,
    // axis-dependent lag or spline overshoot; the audio producer is untouched.
    wire signed [17:0] liss_sum_x=$signed({{2{liss_input_x[15]}},liss_input_x})+
        ($signed({{2{liss_x_d1[15]}},liss_x_d1})<<<1)+$signed({{2{liss_x_d2[15]}},liss_x_d2});
    wire signed [17:0] liss_sum_y=$signed({{2{liss_input_y[15]}},liss_input_y})+
        ($signed({{2{liss_y_d1[15]}},liss_y_d1})<<<1)+$signed({{2{liss_y_d2[15]}},liss_y_d2});
    wire signed [15:0] liss_filtered_x=liss_sum_x>>>2,liss_filtered_y=liss_sum_y>>>2;
    wire [15:0] liss_input_peak=(abs16(liss_filtered_x)>abs16(liss_filtered_y))?abs16(liss_filtered_x):abs16(liss_filtered_y);
    wire [15:0] liss_next_peak=(liss_input_peak>liss_peak)?liss_input_peak:liss_peak;
    reg adsr_wr_bank, adsr_build;
    reg [6:0] adsr_build_idx;
    reg [5:0] adsr_len_a, adsr_len_d, adsr_len_r;
    reg [6:0] adsr_s_level;
    reg [3:0] adsr_last_a, adsr_last_d, adsr_last_s, adsr_last_r;
    reg adsr_params_valid;
    reg [15:0] adsr_point_counter;
    reg [7:0] adsr_history [0:127];
    wire adsr_sample_now=frame_tick && adsr_point_counter>=FS_TICKS-1;
    integer i;

    function [15:0] abs16(input signed [15:0] x);
      begin abs16 = x[15] ? (~x + 16'd1) : x; end
    endfunction
    // One common power-of-two gain per complete XY capture preserves the
    // relative axis amplitudes.  Limit the boost to 256x so near-silence
    // remains small instead of becoming a full-screen noise trace.
    function [3:0] liss_gain_shift(input [15:0] peak);
      begin
        if(peak>=16'd16384)liss_gain_shift=0;
        else if(peak>=16'd8192)liss_gain_shift=1;
        else if(peak>=16'd4096)liss_gain_shift=2;
        else if(peak>=16'd2048)liss_gain_shift=3;
        else if(peak>=16'd1024)liss_gain_shift=4;
        else if(peak>=16'd512)liss_gain_shift=5;
        else if(peak>=16'd256)liss_gain_shift=6;
        else if(peak>=16'd128)liss_gain_shift=7;
        else liss_gain_shift=8;
      end
    endfunction
    function signed [15:0] liss_scale(input signed [15:0] value,input [3:0] shift);
      reg signed [31:0] scaled;
      begin
        scaled={{16{value[15]}},value};scaled=scaled<<<shift;
        if(scaled>32'sd32767)liss_scale=16'sd32767;
        else if(scaled< -32'sd32768)liss_scale=-16'sd32768;
        else liss_scale=scaled[15:0];
      end
    endfunction
    // Fixed-width arithmetic is intentional here.  The previous integer
    // expressions inferred 32-bit signed datapaths and sixteen variable
    // dividers in the ADSR curve generator.
    function [7:0] map_sample(input signed [15:0] x, input [3:0] sh);
      reg signed [17:0] t;
      begin t = 18'sd50 + ($signed(x) >>> sh);
        if(t<0) map_sample=0; else if(t>100) map_sample=100; else map_sample=t[7:0];
      end
    endfunction
    function [15:0] map_xy_x(input signed [15:0] x);
      reg signed [16:0] xs; reg [16:0] u; reg [25:0] p; reg [17:0] t;
      begin xs=x; u=xs+17'sd32768;
        // 428 pixels inside the approved 432 pixel plot, no divider.
        p=(u<<8)+(u<<7)+(u<<5)+(u<<3)+(u<<2); t=18'd24+(p>>16);
        if(t<24)map_xy_x=24; else if(t>452)map_xy_x=452; else map_xy_x=t[15:0];
      end
    endfunction
    function [15:0] map_xy_y(input signed [15:0] x);
      reg signed [16:0] xs; reg [16:0] u; reg [24:0] p; reg [17:0] t;
      begin xs=x; u=xs+17'sd32768;
        p=(u<<7)+(u<<4)+(u<<3)+(u<<1); t=18'd64+(p>>16);
        if(t<64)map_xy_y=64; else if(t>218)map_xy_y=218; else map_xy_y=t[15:0];
      end
    endfunction
    function [7:0] env_to_y(input [16:0] x);
      reg [23:0] p; reg signed [17:0] t;
      begin p=(x<<6)+(x<<5)+(x<<2); t=18'sd100-(p>>16);
        if(t<0)env_to_y=0; else if(t>100)env_to_y=100; else env_to_y=t[7:0];
      end
    endfunction
    function [7:0] adsr_div(input [15:0] numerator, input [5:0] denominator);
      reg [15:0] recip; reg [31:0] product;
      begin
        // Reciprocal multiply replaces the old variable divider.  The
        // reciprocal is rounded to Q0.16; curve error is at most one count.
        case(denominator)
          6'd7:recip=16'd9362;  6'd9:recip=16'd7282;
          6'd11:recip=16'd5958; 6'd13:recip=16'd5041;
          6'd15:recip=16'd4369; 6'd17:recip=16'd3855;
          6'd19:recip=16'd3449; 6'd21:recip=16'd3121;
          6'd23:recip=16'd2849; 6'd25:recip=16'd2621;
          6'd27:recip=16'd2427; 6'd29:recip=16'd2260;
          6'd31:recip=16'd2114; 6'd33:recip=16'd1986;
          6'd35:recip=16'd1872; 6'd37:recip=16'd1771;
          default:recip=0;
        endcase
        product=numerator*recip; adsr_div=product[23:16];
      end
    endfunction
    function [7:0] adsr_curve_point(input [6:0] point,input [5:0] len_a,input [5:0] len_d,input [5:0] len_r,input [6:0] sustain_level);
      reg [6:0] offset; reg [15:0] numerator;
      begin
        if(point<len_a)begin numerator=point*16'd100; adsr_curve_point=adsr_div(numerator,len_a-1'b1); end
        else if(point<len_a+len_d)begin offset=point-len_a; numerator=offset*(7'd100-sustain_level); adsr_curve_point=8'd100-adsr_div(numerator,len_d-1'b1); end
        else if(point<8'd128-len_r) adsr_curve_point=sustain_level;
        else begin offset=point-(8'd128-len_r); numerator=offset*sustain_level; adsr_curve_point=sustain_level-adsr_div(numerator,len_r-1'b1); end
      end
    endfunction
    function [3:0] gain_shift(input [15:0] p);
      begin if(p>16'd24576)gain_shift=10; else if(p>16'd12288)gain_shift=9; else if(p>16'd6144)gain_shift=8; else gain_shift=7; end
    endfunction

    // Keep raw samples separate from mapped coordinates.  In-place mapping
    // inferred DPB read-before-write (WRITE_MODE0=2'b10), unsupported on the
    // GW5AST-138B.  These capture/read and map/UART pairs infer supported SDPBs;
    // Gowin packs each X/Y pair into one 32-bit SDPB instance.  Physical
    // BSRAM usage is reported by P&R, not by counting these logical instances.
    // The published-coordinate port below keeps its one-clock read latency.
    // Do not reset either the memories or their internal read registers.
    always @(posedge clk)begin
      if(rst_n && liss_arm)begin
        if(liss_state==L_CAPTURE && frame_tick && sample_valid && liss_warmup==2)begin
          liss_raw_x_mem[{liss_wr_bank,liss_pos}]<=liss_filtered_x;
          liss_raw_y_mem[{liss_wr_bank,liss_pos}]<=liss_filtered_y;
        end else if(liss_state==L_MAP_READ)begin
          liss_raw_x_q<=liss_raw_x_mem[{liss_wr_bank,liss_pos}];
          liss_raw_y_q<=liss_raw_y_mem[{liss_wr_bank,liss_pos}];
        end else if(liss_state==L_MAP_WRITE)begin
          liss_x_mem[{liss_wr_bank,liss_pos}]<=map_xy_x(liss_scaled_x_q);
          liss_y_mem[{liss_wr_bank,liss_pos}]<=map_xy_y(liss_scaled_y_q);
        end
      end
    end

    always @(posedge clk or negedge rst_n) begin
      if(!rst_n)begin
        wave_ready<=0;wave_data<=0;wave_mem_rd_data<=0;wave_mem_rd_valid<=0;wave_mem_bank<=0;
        wave_state<=W_IDLE;wave_wr_bank<=0;wave_prev_sign<=0;wave_pos<=0;wave_map_idx<=0;wave_dec_cnt<=0;wave_no_trigger<=0;wave_peak<=0;wave_peak_latched<=0;wave_raw_rd_q<=0;
        liss_valid<=0;liss_index<=0;liss_x<=0;liss_y<=0;liss_done<=0;liss_mem_rd_x<=0;liss_mem_rd_y<=0;liss_mem_rd_valid<=0;liss_mem_bank<=0;liss_wr_bank<=0;liss_pos<=0;liss_ready<=0;
        liss_state<=L_CAPTURE;liss_source_a<=0;liss_peak<=0;liss_gain<=0;liss_scaled_x_q<=0;liss_scaled_y_q<=0;
        liss_warmup<=0;liss_x_d1<=0;liss_x_d2<=0;liss_y_d1<=0;liss_y_d2<=0;
        adsr_ready<=0;adsr_data<=0;adsr_mem_rd_data<=0;adsr_mem_rd_valid<=0;adsr_mem_bank<=0;adsr_point_valid<=0;adsr_point_x<=0;adsr_point_y<=0;adsr_point_stage<=0;adsr_point_counter<=0;
        adsr_wr_bank<=0;adsr_build<=0;adsr_build_idx<=0;adsr_params_valid<=0;adsr_len_a<=8;adsr_len_d<=8;adsr_len_r<=8;adsr_s_level<=0;adsr_last_a<=0;adsr_last_d<=0;adsr_last_s<=0;adsr_last_r<=0;
        for(i=0;i<128;i=i+1)adsr_history[i]<=0;
        // Visualization RAMs are intentionally not reset: reset-time array writes
        // inhibit BSRAM inference on Gowin.  Ready/bank flags gate all reads until
        // a complete capture has populated the selected bank.
      end else begin
        wave_mem_rd_valid<=0;liss_mem_rd_valid<=0;adsr_mem_rd_valid<=0;liss_valid<=0;liss_done<=0;adsr_point_valid<=0;
        if(wave_mem_rd_en)begin wave_mem_rd_data<=wave_mem[wave_mem_rd_addr];wave_mem_rd_valid<=1;end
        if(liss_mem_rd_en)begin liss_mem_rd_x<=liss_x_mem[liss_mem_rd_addr];liss_mem_rd_y<=liss_y_mem[liss_mem_rd_addr];liss_mem_rd_valid<=1;end
        if(adsr_mem_rd_en)begin adsr_mem_rd_data<=adsr_mem[adsr_mem_rd_addr];adsr_mem_rd_valid<=1;end

        if(!wave_arm)begin wave_state<=W_IDLE;wave_ready<=0;wave_no_trigger<=0;end
        else if(wave_consumed && wave_ready)begin wave_ready<=0;wave_wr_bank<=~wave_mem_bank;wave_state<=W_IDLE;wave_pos<=0;wave_no_trigger<=0;end
        else if(frame_tick && sample_valid)begin
          wave_prev_sign<=wave_sample[15];
          case(wave_state)
            W_IDLE: if((wave_prev_sign&&!wave_sample[15])||wave_no_trigger>=FS_TICKS)begin wave_state<=W_CAPTURE;wave_pos<=0;wave_dec_cnt<=0;wave_peak<=0;wave_no_trigger<=0;end else wave_no_trigger<=wave_no_trigger+1'b1;
            W_CAPTURE: if(wave_dec_cnt==0)begin
              wave_raw_mem[{wave_wr_bank,wave_pos[6:0]}]<=wave_sample;
              if(abs16(wave_sample)>wave_peak)wave_peak<=abs16(wave_sample);
              wave_dec_cnt<=(wave_decim==0)?0:((1<<wave_decim)-1);
              if(wave_pos==WAVE_POINTS-1)begin wave_peak_latched<=(abs16(wave_sample)>wave_peak)?abs16(wave_sample):wave_peak;wave_map_idx<=0;wave_state<=W_MAP_READ;end
              else wave_pos<=wave_pos+1'b1;
            end else wave_dec_cnt<=wave_dec_cnt-1'b1;
            W_MAP_READ:begin wave_raw_rd_q<=wave_raw_mem[{wave_wr_bank,wave_map_idx[6:0]}];wave_state<=W_MAP_WRITE;end
            W_MAP_WRITE:begin
              wave_mem[{wave_wr_bank,wave_map_idx[6:0]}]<=map_sample(wave_raw_rd_q,gain_shift(wave_peak_latched));
              if(wave_map_idx==WAVE_POINTS-1)begin
                wave_mem_bank<=wave_wr_bank;wave_ready<=1;wave_state<=W_WAIT;
                if(LEGACY_PACKED)begin for(i=0;i<WAVE_POINTS;i=i+1)wave_data[i*8 +:8]<=wave_mem[{wave_wr_bank,i[6:0]}]; wave_data[(WAVE_POINTS-1)*8 +:8]<=map_sample(wave_raw_rd_q,gain_shift(wave_peak_latched)); end
              end else begin wave_map_idx<=wave_map_idx+1'b1;wave_state<=W_MAP_READ;end
            end
            default:begin end
          endcase
        end

        if(!liss_arm)begin
          liss_state<=L_CAPTURE;liss_pos<=0;liss_peak<=0;liss_ready<=0;liss_warmup<=0;
        end else case(liss_state)
          L_CAPTURE:if(frame_tick && sample_valid)begin
            if(liss_pos==0)liss_source_a<=liss_mode_a&&(liss_voice_count>=2);
            liss_x_d2<=liss_x_d1;liss_x_d1<=liss_input_x;
            liss_y_d2<=liss_y_d1;liss_y_d1<=liss_input_y;
            if(liss_warmup<2)liss_warmup<=liss_warmup+1'b1;
            else begin
              liss_peak<=liss_next_peak;
              if(liss_pos==LISS_POINTS-1)begin
                liss_gain<=liss_gain_shift(liss_next_peak);
                liss_pos<=0;liss_state<=L_MAP_READ;
              end else liss_pos<=liss_pos+1'b1;
            end
          end
          L_MAP_READ:liss_state<=L_MAP_SCALE;
          L_MAP_SCALE:begin
            liss_scaled_x_q<=liss_scale(liss_raw_x_q,liss_gain);
            liss_scaled_y_q<=liss_scale(liss_raw_y_q,liss_gain);
            liss_state<=L_MAP_WRITE;
          end
          L_MAP_WRITE:begin
            liss_valid<=1;liss_index<=liss_pos;
            liss_x<=map_xy_x(liss_scaled_x_q);liss_y<=map_xy_y(liss_scaled_y_q);
            if(liss_pos==LISS_POINTS-1)begin
              // Publish only fully mapped coordinates, never raw samples.
              liss_ready<=1;liss_done<=1;liss_mem_bank<=liss_wr_bank;
              liss_wr_bank<=~liss_wr_bank;liss_pos<=0;liss_state<=L_WAIT;
            end else begin liss_pos<=liss_pos+1'b1;liss_state<=L_MAP_READ;end
          end
          L_WAIT:if(liss_consumed && liss_ready)begin
            liss_ready<=0;liss_peak<=0;liss_pos<=0;liss_warmup<=0;liss_state<=L_CAPTURE;
          end
          default:begin liss_state<=L_CAPTURE;liss_pos<=0;liss_peak<=0;liss_ready<=0;end
        endcase

        if(REAL_ADSR!=0)begin
          if(adsr_sample_now)begin
            for(i=0;i<127;i=i+1)adsr_history[i]<=adsr_history[i+1];
            adsr_history[127]<=8'd100-env_to_y(env_value);
          end
          if(!adsr_arm)begin adsr_ready<=0;adsr_build<=0;end
          else begin
            if(adsr_sample_now && !adsr_ready && !adsr_build)begin
              adsr_build<=1;adsr_build_idx<=0;
            end else if(adsr_build)begin
              adsr_mem[{adsr_wr_bank,adsr_build_idx}]<=adsr_history[adsr_build_idx];
              if(adsr_build_idx==7'd127)begin
                adsr_build<=0;adsr_ready<=1;adsr_mem_bank<=adsr_wr_bank;
              end else adsr_build_idx<=adsr_build_idx+1'b1;
            end
            if(adsr_consumed && adsr_ready)begin adsr_ready<=0;adsr_wr_bank<=~adsr_mem_bank;end
          end
        end else if(!adsr_arm)begin adsr_ready<=0;adsr_build<=0;adsr_params_valid<=0;end
        else begin
          if(!adsr_build&&(!adsr_params_valid||adsr_a!=adsr_last_a||adsr_d!=adsr_last_d||adsr_s!=adsr_last_s||adsr_r!=adsr_last_r))begin
            adsr_last_a<=adsr_a;adsr_last_d<=adsr_d;adsr_last_s<=adsr_s;adsr_last_r<=adsr_r;adsr_len_a<=6'd8+{adsr_a,1'b0};adsr_len_d<=6'd8+{adsr_d,1'b0};adsr_len_r<=6'd8+{adsr_r,1'b0};
            // floor(100*s/15), encoded as a tiny LUT instead of a divider.
            case(adsr_s)
              4'd0:adsr_s_level<=0;   4'd1:adsr_s_level<=6;
              4'd2:adsr_s_level<=13;  4'd3:adsr_s_level<=20;
              4'd4:adsr_s_level<=26;  4'd5:adsr_s_level<=33;
              4'd6:adsr_s_level<=40;  4'd7:adsr_s_level<=46;
              4'd8:adsr_s_level<=53;  4'd9:adsr_s_level<=60;
              4'd10:adsr_s_level<=66; 4'd11:adsr_s_level<=73;
              4'd12:adsr_s_level<=80; 4'd13:adsr_s_level<=86;
              4'd14:adsr_s_level<=93; default:adsr_s_level<=100;
            endcase
            adsr_build_idx<=0;adsr_build<=1;adsr_ready<=0;adsr_params_valid<=1;
          end else if(adsr_build)begin
            adsr_mem[{adsr_wr_bank,adsr_build_idx}]<=adsr_curve_point(adsr_build_idx,adsr_len_a,adsr_len_d,adsr_len_r,adsr_s_level);
            if(adsr_build_idx==7'd127)begin adsr_build<=0;adsr_ready<=1;adsr_mem_bank<=adsr_wr_bank; if(LEGACY_PACKED)begin for(i=0;i<128;i=i+1)adsr_data[i*8 +:8]<=adsr_mem[{adsr_wr_bank,i[6:0]}];adsr_data[127*8 +:8]<=adsr_curve_point(adsr_build_idx,adsr_len_a,adsr_len_d,adsr_len_r,adsr_s_level);end end
            else adsr_build_idx<=adsr_build_idx+1'b1;
          end
          if(adsr_consumed&&adsr_ready)begin adsr_ready<=0;adsr_wr_bank<=~adsr_mem_bank;end
        end

        if(frame_tick)begin
          if(adsr_point_counter>=FS_TICKS-1)begin adsr_point_counter<=0;adsr_point_valid<=1;adsr_point_stage<=env_stage;case(env_stage)3'd1:adsr_point_x<=16'd96;3'd2:adsr_point_x<=16'd192;3'd3:adsr_point_x<=16'd288;3'd4:adsr_point_x<=16'd384;default:adsr_point_x<=16'd64;endcase adsr_point_y<=16'd55+{8'd0,env_to_y(env_value)};end
          else adsr_point_counter<=adsr_point_counter+1'b1;
        end
      end
    end
endmodule
`default_nettype wire
