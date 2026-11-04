module instrument_envelope_volume (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_enable,

    input  wire               note_on,
    input  wire [6:0]         note_number,
    input  wire [1:0]         timbre_select,

    input  wire [15:0]        attack_step,
    input  wire [3:0]         decay_divider_limit,
    input  wire [15:0]        sustain_level,
    input  wire [3:0]         release_divider_limit,

    input  wire signed [31:0] sample_in,
    output wire signed [31:0] sample_out
);

    localparam [2:0] STATE_IDLE    = 3'd0;
    localparam [2:0] STATE_ATTACK  = 3'd1;
    localparam [2:0] STATE_DECAY   = 3'd2;
    localparam [2:0] STATE_SUSTAIN = 3'd3;
    localparam [2:0] STATE_RELEASE = 3'd4;

    reg [2:0]  envelope_state;
    reg [15:0] gain_q15;
    reg [3:0]  rate_divider;

    reg        prev_note_on;
    reg [6:0]  prev_note;
    reg [1:0]  prev_timbre;

    wire restart_note;
    wire [15:0] peak_level;
    wire [15:0] sustain_target;
    wire [15:0] decay_amount;

    /*
     * 新按键、改变音符或者改变音色时重新起音。
     */
    assign restart_note =
        note_on &&
        (
            !prev_note_on ||
            note_number != prev_note ||
            timbre_select != prev_timbre
        );

    /*
     * 保留原来的音色音量平衡：
     *
     * 正弦、三角：32767
     * 钢琴：20480
     * 吉他：24576
     */
    assign peak_level =
        (timbre_select == 2'd2) ? 16'd20480 :
        (timbre_select == 2'd3) ? 16'd24576 :
                                  16'd32767;

    /*
     * Sustain不能超过当前音色的峰值。
     */
    assign sustain_target =
        (sustain_level > peak_level)
        ? peak_level
        : sustain_level;

    /*
     * 指数形式衰减。
     *
     * 当前音量越大，每次下降越多；
     * 当前音量越小，尾音下降越慢。
     */
    assign decay_amount =
        (gain_q15 >> 12) + 16'd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            envelope_state <= STATE_IDLE;
            gain_q15        <= 16'd0;
            rate_divider    <= 4'd0;

            prev_note_on    <= 1'b0;
            prev_note       <= 7'd0;
            prev_timbre     <= 2'd0;

        end else if (sample_enable) begin
            prev_note_on <= note_on;
            prev_note    <= note_number;
            prev_timbre  <= timbre_select;

            /*
             * 新音符从0开始进入Attack。
             */
            if (restart_note) begin
                gain_q15       <= 16'd0;
                rate_divider   <= 4'd0;
                envelope_state <= STATE_ATTACK;

            end else begin
                case (envelope_state)

                    /*
                     * 没有声音。
                     */
                    STATE_IDLE: begin
                        gain_q15     <= 16'd0;
                        rate_divider <= 4'd0;
                    end

                    /*
                     * Attack：
                     * 从0逐渐增加到peak_level。
                     */
                    STATE_ATTACK: begin
                        /*
                         * Attack尚未结束就松开按键，
                         * 直接进入Release。
                         */
                        if (!note_on) begin
                            rate_divider   <= 4'd0;
                            envelope_state <= STATE_RELEASE;

                        /*
                         * 到达峰值后进入Decay。
                         */
                        end else if (
                            attack_step >= peak_level ||
                            gain_q15 >= peak_level - attack_step
                        ) begin
                            gain_q15       <= peak_level;
                            rate_divider   <= 4'd0;
                            envelope_state <= STATE_DECAY;

                        end else begin
                            gain_q15 <=
                                gain_q15 + attack_step;
                        end
                    end

                    /*
                     * Decay：
                     * 从峰值下降到Sustain音量。
                     */
                    STATE_DECAY: begin
                        /*
                         * Decay过程中松开按键，
                         * 立即进入Release。
                         */
                        if (!note_on) begin
                            rate_divider   <= 4'd0;
                            envelope_state <= STATE_RELEASE;

                        /*
                         * 已经到达Sustain目标。
                         */
                        end else if (
                            gain_q15 <= sustain_target
                        ) begin
                            gain_q15       <= sustain_target;
                            rate_divider   <= 4'd0;
                            envelope_state <= STATE_SUSTAIN;

                        /*
                         * 到达本次衰减时间。
                         */
                        end else if (
                            rate_divider
                            >= decay_divider_limit
                        ) begin
                            rate_divider <= 4'd0;

                            if (
                                gain_q15
                                <= sustain_target
                                + decay_amount
                            ) begin
                                gain_q15       <= sustain_target;
                                envelope_state <= STATE_SUSTAIN;
                            end else begin
                                gain_q15 <=
                                    gain_q15 - decay_amount;
                            end

                        end else begin
                            rate_divider <=
                                rate_divider + 1'b1;
                        end
                    end

                    /*
                     * Sustain：
                     *
                     * 只要触摸键仍然按着，
                     * 就保持sustain_target音量。
                     *
                     * 这部分修复钢琴长按后完全消失的问题。
                     */
                    STATE_SUSTAIN: begin
                        if (!note_on) begin
                            rate_divider   <= 4'd0;
                            envelope_state <= STATE_RELEASE;
                        end else begin
                            gain_q15 <= sustain_target;
                        end
                    end

                    /*
                     * Release：
                     * 松开触摸键以后逐渐衰减到0。
                     */
                    STATE_RELEASE: begin
                        if (gain_q15 < 16'd64) begin
                            gain_q15       <= 16'd0;
                            rate_divider   <= 4'd0;
                            envelope_state <= STATE_IDLE;

                        end else if (
                            rate_divider
                            >= release_divider_limit
                        ) begin
                            rate_divider <= 4'd0;

                            if (gain_q15 <= decay_amount) begin
                                gain_q15       <= 16'd0;
                                envelope_state <= STATE_IDLE;
                            end else begin
                                gain_q15 <=
                                    gain_q15 - decay_amount;
                            end

                        end else begin
                            rate_divider <=
                                rate_divider + 1'b1;
                        end
                    end

                    default: begin
                        gain_q15       <= 16'd0;
                        rate_divider   <= 4'd0;
                        envelope_state <= STATE_IDLE;
                    end
                endcase
            end
        end
    end

    /*
     * 将Q15包络音量乘到音频数据上。
     */
    wire signed [47:0] sample_wide;
    wire signed [47:0] gain_wide;
    wire signed [47:0] scaled;

    assign sample_wide =
        {{16{sample_in[31]}}, sample_in};

    assign gain_wide =
        {32'd0, gain_q15};

    assign scaled =
        sample_wide * gain_wide;

    assign sample_out =
        scaled[46:15];

endmodule