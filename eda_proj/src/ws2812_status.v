/*
 * One-pixel WS2812 status driver for the Tang Mega 138K Dock.
 *
 * The 24-bit color word uses the WS2812 wire order: G[23:16], R[15:8], B[7:0].
 * At 52.5 MHz the selected timing is:
 *   bit period: 66 clocks = 1.257 us (about 795 kHz)
 *   logic 0 high: 18 clocks = 0.343 us
 *   logic 1 high: 37 clocks = 0.705 us
 *   latch/reset low: about 400 us (WS2812B-2020 requires more than 280 us)
 */
module ws2812_status #(
    parameter integer CLK_HZ = 52500000,
    parameter [23:0] IDLE_COLOR = 24'h000020,
    parameter [23:0] ON_COLOR = 24'h002000
)(
    input  wire clk,
    input  wire rst_n,
    input  wire status_on,
    output reg  data_out
);
    localparam integer BIT_CYCLES   = 66;
    localparam integer T0H_CYCLES   = 18;
    localparam integer T1H_CYCLES   = 37;
    localparam integer RESET_CYCLES = (CLK_HZ / 1000000) * 400;

    reg status_meta;
    reg status_sync;
    reg sending;
    reg [15:0] reset_count;
    reg [6:0] bit_cycle;
    reg [4:0] bit_index;
    reg [23:0] shift_data;

    wire current_bit = shift_data[bit_index];
    wire [6:0] high_cycles = current_bit ? T1H_CYCLES : T0H_CYCLES;

    // touch_keys is generated in the 1.5 MHz clock domain; synchronize it here.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            status_meta <= 1'b0;
            status_sync <= 1'b0;
        end else begin
            status_meta <= status_on;
            status_sync <= status_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out   <= 1'b0;
            sending    <= 1'b0;
            reset_count <= 16'd0;
            bit_cycle  <= 7'd0;
            bit_index  <= 5'd23;
            shift_data <= 24'd0;
        end else if (!sending) begin
            // Keep the line low long enough for the WS2812 to latch the frame.
            data_out <= 1'b0;
            if (reset_count == RESET_CYCLES - 1) begin
                reset_count <= 16'd0;
                // Idle color proves that the LED data path works independently
                // of the TTP229 channel-16 input.
                shift_data <= status_sync ? ON_COLOR : IDLE_COLOR;
                bit_index <= 5'd23;
                bit_cycle <= 7'd0;
                sending <= 1'b1;
                data_out <= 1'b1;
            end else begin
                reset_count <= reset_count + 1'b1;
            end
        end else begin
            if (bit_cycle == high_cycles - 1'b1)
                data_out <= 1'b0;

            if (bit_cycle == BIT_CYCLES - 1) begin
                bit_cycle <= 7'd0;
                if (bit_index == 0) begin
                    bit_index <= 5'd23;
                    sending <= 1'b0;
                    reset_count <= 16'd0;
                    data_out <= 1'b0;
                end else begin
                    bit_index <= bit_index - 1'b1;
                    data_out <= 1'b1;
                end
            end else begin
                bit_cycle <= bit_cycle + 1'b1;
            end
        end
    end
endmodule
