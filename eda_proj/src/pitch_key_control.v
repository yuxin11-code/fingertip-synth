module pitch_key_control #(
    parameter integer CLK_HZ           = 1500000,
    parameter integer DEBOUNCE_MS      = 10,
    parameter integer LONG_PRESS_MS    = 400,
    parameter integer RAMP_INTERVAL_MS = 1,
    parameter integer RAMP_STEP        = 8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        key_up_n,
    input  wire        key_down_n,
    input wire hmi_valid,input wire [7:0] hmi_cmd,input wire [15:0] hmi_value,
    output reg signed [4:0] semitone,
    output wire approximate,
    output reg  [17:0] pitch_scale_q16
);

    localparam integer DEBOUNCE_TICKS =
        (CLK_HZ / 1000) * DEBOUNCE_MS;
    localparam integer LONG_TICKS =
        (CLK_HZ / 1000) * LONG_PRESS_MS;
    localparam integer RAMP_TICKS =
        (CLK_HZ / 1000) * RAMP_INTERVAL_MS;

    // Q16 音高比例
    localparam [17:0] SCALE_MIN   = 18'd32768;   // 0.5 倍，低一个八度
    localparam [17:0] SCALE_UNITY = 18'd65536;   // 1.0 倍，原音高
    localparam [17:0] SCALE_MAX   = 18'd131072;  // 2.0 倍，高一个八度
    function [17:0] pitch_of;
        input signed [5:0] n;
        begin case(n)
        -12:pitch_of=32768;-11:pitch_of=34716;-10:pitch_of=36781;
        -9:pitch_of=38968;-8:pitch_of=41285;-7:pitch_of=43740;
        -6:pitch_of=46341;-5:pitch_of=49097;-4:pitch_of=52016;
        -3:pitch_of=55109;-2:pitch_of=58386;-1:pitch_of=61858;
        0:pitch_of=65536;1:pitch_of=69433;2:pitch_of=73562;
        3:pitch_of=77936;4:pitch_of=82570;5:pitch_of=87480;
        6:pitch_of=92682;7:pitch_of=98193;8:pitch_of=104032;
        9:pitch_of=110218;10:pitch_of=116772;11:pitch_of=123715;
        default:pitch_of=131072;endcase end
    endfunction
    reg signed [4:0] nearest;
    integer n;
    always @* begin
        nearest=-12;
        for(n=-12;n<12;n=n+1)
            if(pitch_scale_q16>=((pitch_of(n)+{1'b0,pitch_of(n+1)})>>1)) nearest=n+1;
    end
    assign approximate=(pitch_scale_q16!=pitch_of(nearest));
    wire signed [15:0] requested=$signed(hmi_value);

    // 2^(1/12) 和 2^(-1/12)
    localparam [16:0] SEMITONE_UP_Q16   = 17'd69433;
    localparam [16:0] SEMITONE_DOWN_Q16 = 17'd61858;

    reg [1:0] up_sync;
    reg [1:0] down_sync;

    reg up_pressed;
    reg down_pressed;
    reg up_pressed_d;
    reg down_pressed_d;

    reg [31:0] up_debounce_count;
    reg [31:0] down_debounce_count;
    reg [31:0] hold_count;
    reg [31:0] ramp_count;

    wire up_press_pulse =
        up_pressed & ~up_pressed_d;

    wire down_press_pulse =
        down_pressed & ~down_pressed_d;

    wire [34:0] semitone_up_product =
        pitch_scale_q16 * SEMITONE_UP_Q16;

    wire [34:0] semitone_down_product =
        pitch_scale_q16 * SEMITONE_DOWN_Q16;

    wire [18:0] semitone_up_value =
        (semitone_up_product + 35'd32768) >> 16;

    wire [18:0] semitone_down_value =
        (semitone_down_product + 35'd32768) >> 16;

    // 输入同步和按键消抖
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            up_sync             <= 2'b11;
            down_sync           <= 2'b11;
            up_pressed          <= 1'b0;
            down_pressed        <= 1'b0;
            up_pressed_d        <= 1'b0;
            down_pressed_d      <= 1'b0;
            up_debounce_count   <= 32'd0;
            down_debounce_count <= 32'd0;
        end else begin
            up_sync   <= {up_sync[0], key_up_n};
            down_sync <= {down_sync[0], key_down_n};

            if ((~up_sync[1]) == up_pressed) begin
                up_debounce_count <= 32'd0;
            end else if (up_debounce_count >= DEBOUNCE_TICKS - 1) begin
                up_pressed        <= ~up_sync[1];
                up_debounce_count <= 32'd0;
            end else begin
                up_debounce_count <= up_debounce_count + 1'b1;
            end

            if ((~down_sync[1]) == down_pressed) begin
                down_debounce_count <= 32'd0;
            end else if (down_debounce_count >= DEBOUNCE_TICKS - 1) begin
                down_pressed        <= ~down_sync[1];
                down_debounce_count <= 32'd0;
            end else begin
                down_debounce_count <= down_debounce_count + 1'b1;
            end

            up_pressed_d   <= up_pressed;
            down_pressed_d <= down_pressed;
        end
    end

    // 短按半音移调，长按连续滑音
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pitch_scale_q16 <= SCALE_UNITY;
            semitone <= 0;
            hold_count      <= 32'd0;
            ramp_count      <= 32'd0;
        end

        // K1 刚刚按下：升一个半音
        else if(hmi_valid && hmi_cmd==8'h05)begin
            semitone<=(requested< -12)?-12:(requested>12)?12:requested;
            pitch_scale_q16<=pitch_of((requested< -12)?-12:(requested>12)?12:requested);
            hold_count<=0;ramp_count<=0;
        end
        else if (up_press_pulse && !down_pressed) begin
            semitone<=(nearest>=12)?12:nearest+1;
            pitch_scale_q16<=pitch_of((nearest>=12)?12:nearest+1);

            hold_count <= 32'd0;
            ramp_count <= 32'd0;
        end

        // K2 刚刚按下：降一个半音
        else if (down_press_pulse && !up_pressed) begin
            semitone<=(nearest<=-12)?-12:nearest-1;
            pitch_scale_q16<=pitch_of((nearest<=-12)?-12:nearest-1);

            hold_count <= 32'd0;
            ramp_count <= 32'd0;
        end

        // 长按 K1：连续升高
        else if (up_pressed && !down_pressed) begin
            semitone<=nearest;
            if (hold_count < LONG_TICKS - 1) begin
                hold_count <= hold_count + 1'b1;
                ramp_count <= 32'd0;
            end else if (ramp_count >= RAMP_TICKS - 1) begin
                ramp_count <= 32'd0;

                if (pitch_scale_q16 >= SCALE_MAX - RAMP_STEP)
                    pitch_scale_q16 <= SCALE_MAX;
                else
                    pitch_scale_q16 <= pitch_scale_q16 + RAMP_STEP;
            end else begin
                ramp_count <= ramp_count + 1'b1;
            end
        end

        // 长按 K2：连续降低
        else if (down_pressed && !up_pressed) begin
            semitone<=nearest;
            if (hold_count < LONG_TICKS - 1) begin
                hold_count <= hold_count + 1'b1;
                ramp_count <= 32'd0;
            end else if (ramp_count >= RAMP_TICKS - 1) begin
                ramp_count <= 32'd0;

                if (pitch_scale_q16 <= SCALE_MIN + RAMP_STEP)
                    pitch_scale_q16 <= SCALE_MIN;
                else
                    pitch_scale_q16 <= pitch_scale_q16 - RAMP_STEP;
            end else begin
                ramp_count <= ramp_count + 1'b1;
            end
        end

        else begin
            semitone<=nearest;
            hold_count <= 32'd0;
            ramp_count <= 32'd0;
        end
    end

endmodule
