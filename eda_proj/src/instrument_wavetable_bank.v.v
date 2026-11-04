module instrument_wavetable_bank (
    input  wire              clk,
    input  wire              rst_n,
    input  wire [1:0]        timbre_select,
    input  wire [7:0]        address,
    output reg signed [15:0] sample
);

    /*
     * 使用不同地址读取同一张正弦波表：
     *
     * address     = 基波
     * address×2   = 二次谐波
     * address×3   = 三次谐波
     * address×4   = 四次谐波
     */

    wire [7:0] address_h2;
    wire [7:0] address_h3;
    wire [7:0] address_h4;

    assign address_h2 = {address[6:0], 1'b0};
    assign address_h3 = address + {address[6:0], 1'b0};
    assign address_h4 = {address[5:0], 2'b00};

    wire signed [15:0] sine_h1;
    wire signed [15:0] sine_h2;
    wire signed [15:0] sine_h3;
    wire signed [15:0] sine_h4;
    wire signed [15:0] triangle_sample;
    wire signed [15:0] piano_wave_sample;

    rom_wave_piano piano_rom (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (address),
        .data  (piano_wave_sample)
    );
    rom_save_sin sine_rom_h1 (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (address),
        .data  (sine_h1)
    );

    rom_save_sin sine_rom_h2 (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (address_h2),
        .data  (sine_h2)
    );

    rom_save_sin sine_rom_h3 (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (address_h3),
        .data  (sine_h3)
    );

    rom_save_sin sine_rom_h4 (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (address_h4),
        .data  (sine_h4)
    );

    rom_wave_triangle triangle_rom (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (address),
        .data  (triangle_sample)
    );

    // 扩展符号位，避免相加溢出
    wire signed [17:0] h1;
    wire signed [17:0] h2;
    wire signed [17:0] h3;
    wire signed [17:0] h4;

    assign h1 = {{2{sine_h1[15]}}, sine_h1};
    assign h2 = {{2{sine_h2[15]}}, sine_h2};
    assign h3 = {{2{sine_h3[15]}}, sine_h3};
    assign h4 = {{2{sine_h4[15]}}, sine_h4};

    /*
     * 简化吉他音色：
     * 加强三次谐波，使拨弦声音更明亮。
     */
    wire signed [17:0] guitar_sample;

    assign guitar_sample =
          (h1 >>> 1)
        + (h2 >>> 3)
        + (h3 >>> 2)
        + (h4 >>> 4);

    always @* begin
        case (timbre_select)
            2'd0: sample = sine_h1;
            2'd1: sample = triangle_sample;
            2'd2: sample = piano_wave_sample;
            2'd3: sample = guitar_sample[15:0];
            default: sample = 16'sd0;
        endcase
    end

endmodule