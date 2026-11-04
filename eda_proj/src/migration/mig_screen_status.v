// Imported from instrument_v1 on 2026-10-22; adapted for audio.gprj.
// ============================================================
//  instrument_v1 - serial screen status frame
//
//  Frame (13 bytes):
//    0  AA
//    1  55
//    2  01              command: status
//    3  08              payload length
//    4  left instrument (0 piano / 1 guitar / 2 violin / 3 guzheng / 4 pipa)
//    5  right instrument
//    6  active voices (0..32)
//    7  volume, high 8 bit of Q16
//    8  A (high nibble), D (low nibble)
//    9  S (high nibble), R (low nibble)
//   10  bit0 test mode, bit1 strum active
//   11  reserved low bits: bit0 K3 stable, bit1 K4 stable
//   12  CRC8 (poly 0x07) over bytes 2..11
//
//  The byte map is the only part that has to change once the
//  screen's own command set is known.
// ============================================================
`default_nettype none

module mig_screen_status #(
    parameter integer LEGACY_MODE = 0,
    parameter integer CLK_HZ    = 52500000,
    parameter integer PERIOD_MS = 100
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [2:0]  inst_l,
    input  wire [2:0]  inst_r,
    input  wire [5:0]  active_voices,
    input  wire [16:0] volume_q16,
    input  wire [3:0]  adsr_a,
    input  wire [3:0]  adsr_d,
    input  wire [3:0]  adsr_s,
    input  wire [3:0]  adsr_r,
    input  wire        test_mode,
    input  wire        strum_active,
    input  wire        aux3_stable,
    input  wire        aux4_stable,

    input  wire        uart_busy,
    output reg         uart_start,
    output reg  [7:0]  uart_data
);

    localparam integer TICKS = (CLK_HZ / 1000) * PERIOD_MS;

    reg [31:0] period_cnt;
    reg [4:0]  idx;
    reg        sending;
    reg [7:0]  crc;
    reg        wait_busy;
    reg        wait_done;

    function [7:0] crc8_next;
        input [7:0] c;
        input [7:0] d;
        integer k;
        reg [7:0] x;
        begin
            x = c ^ d;
            for (k = 0; k < 8; k = k + 1)
                x = x[7] ? ((x << 1) ^ 8'h07) : (x << 1);
            crc8_next = x;
        end
    endfunction

    reg [2:0] snap_inst_l;
    reg [2:0] snap_inst_r;
    reg [5:0] snap_active_voices;
    reg [16:0] snap_volume_q16;
    reg [3:0] snap_adsr_a;
    reg [3:0] snap_adsr_d;
    reg [3:0] snap_adsr_s;
    reg [3:0] snap_adsr_r;
    reg [0:0] snap_test_mode;
    reg [0:0] snap_strum_active;
    reg [0:0] snap_aux3;
    reg [0:0] snap_aux4;

    function [7:0] byte_for;
        input [4:0] i;
        begin
            case (i)
                5'd0:  byte_for = 8'hAA;
                5'd1:  byte_for = 8'h55;
                5'd2:  byte_for = 8'h01;
                5'd3:  byte_for = 8'h08;
                5'd4:  byte_for = {5'd0, snap_inst_l};
                5'd5:  byte_for = {5'd0, snap_inst_r};
                5'd6:  byte_for = {2'd0, snap_active_voices};
                5'd7:  byte_for = (snap_volume_q16[16] ? 8'hff : snap_volume_q16[15:8]);
                5'd8:  byte_for = {snap_adsr_a, snap_adsr_d};
                5'd9:  byte_for = {snap_adsr_s, snap_adsr_r};
                5'd10: byte_for = {5'd0, (LEGACY_MODE != 0), snap_strum_active, snap_test_mode};
                5'd11: byte_for = {6'd0, snap_aux4, snap_aux3};
                default: byte_for = crc;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            snap_inst_l <= 0;
            snap_inst_r <= 0;
            snap_active_voices <= 0;
            snap_volume_q16 <= 0;
            snap_adsr_a <= 0;
            snap_adsr_d <= 0;
            snap_adsr_s <= 0;
            snap_adsr_r <= 0;
            snap_test_mode <= 0;
            snap_strum_active <= 0;
            snap_aux3 <= 0;
            snap_aux4 <= 0;
            period_cnt <= 32'd0;
            idx        <= 5'd0;
            sending    <= 1'b0;
            crc        <= 8'd0;
            wait_busy  <= 1'b0;
            wait_done  <= 1'b0;
            uart_start <= 1'b0;
            uart_data  <= 8'd0;
        end else begin
            uart_start <= 1'b0;

            if (!sending) begin
                if (period_cnt >= TICKS - 1) begin
                    snap_inst_l <= inst_l;
                    snap_inst_r <= inst_r;
                    snap_active_voices <= active_voices;
                    snap_volume_q16 <= volume_q16;
                    snap_adsr_a <= adsr_a;
                    snap_adsr_d <= adsr_d;
                    snap_adsr_s <= adsr_s;
                    snap_adsr_r <= adsr_r;
                    snap_test_mode <= test_mode;
                    snap_strum_active <= strum_active;
                    snap_aux3 <= aux3_stable;
                    snap_aux4 <= aux4_stable;

                    period_cnt <= 32'd0;
                    sending    <= 1'b1;
                    idx        <= 5'd0;
                    crc        <= 8'd0;
                    wait_busy  <= 1'b0;
                    wait_done  <= 1'b0;
                end else begin
                    period_cnt <= period_cnt + 32'd1;
                end
            end else begin
                // ------------------------------------------------------------------
                // three step handshake: start pulse -> wait busy high -> wait busy low
                // (a single !busy test would lose every other byte because mig_uart_tx
                //  raises busy one cycle after it sees start)
                // ------------------------------------------------------------------
                if (wait_busy) begin
                    if (uart_busy) begin
                        wait_busy <= 1'b0;
                        wait_done <= 1'b1;
                    end
                end else if (wait_done) begin
                    if (!uart_busy) begin
                        wait_done <= 1'b0;
                        if (idx == 5'd12) begin
                            sending <= 1'b0;
                            idx     <= 5'd0;
                        end else begin
                            idx <= idx + 5'd1;
                        end
                    end
                end else begin
                    uart_data  <= byte_for(idx);
                    uart_start <= 1'b1;
                    wait_busy  <= 1'b1;

                    if (idx < 5'd12 && idx >= 5'd2)
                        crc <= crc8_next(crc, byte_for(idx));
                end
            end
        end
    end

endmodule

`default_nettype wire
