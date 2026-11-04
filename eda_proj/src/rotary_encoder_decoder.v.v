module rotary_encoder_decoder #(
    parameter integer CLK_HZ = 1500000
)(
    input  wire clk,
    input  wire rst_n,
    input  wire enc_a,
    input  wire enc_b,
    input  wire enc_key_n,

    output reg  rotate_cw,
    output reg  rotate_ccw,
    output reg  select_pulse
);

    // A/B are sampled at 2 kHz.  The full quadrature sequence filters most
    // contact bounce and produces one pulse for one mechanical detent.
    localparam integer AB_SAMPLE_DIV = CLK_HZ / 2000;
    // Push button debounce: 20 ms.
    localparam integer KEY_DB_COUNT  = CLK_HZ / 50;

    reg [1:0] a_sync;
    reg [1:0] b_sync;
    reg [1:0] key_sync;

    reg [31:0] ab_sample_count;
    reg [31:0] key_debounce_count;
    reg [1:0]  ab_previous;
    reg signed [3:0] quarter_count;
    reg        key_stable;

    wire [1:0] ab_current = {a_sync[1], b_sync[1]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_sync             <= 2'b11;
            b_sync             <= 2'b11;
            key_sync           <= 2'b11;
            ab_sample_count    <= 32'd0;
            key_debounce_count <= 32'd0;
            ab_previous        <= 2'b11;
            quarter_count      <= 4'sd0;
            key_stable         <= 1'b1;
            rotate_cw          <= 1'b0;
            rotate_ccw         <= 1'b0;
            select_pulse       <= 1'b0;
        end else begin
            a_sync   <= {a_sync[0], enc_a};
            b_sync   <= {b_sync[0], enc_b};
            key_sync <= {key_sync[0], enc_key_n};

            rotate_cw    <= 1'b0;
            rotate_ccw   <= 1'b0;
            select_pulse <= 1'b0;

            // Decode the four valid Gray-code transitions of one detent.
            if (ab_sample_count >= AB_SAMPLE_DIV - 1) begin
                ab_sample_count <= 32'd0;

                case ({ab_previous, ab_current})
                    4'b11_10, 4'b10_00,
                    4'b00_01, 4'b01_11: begin
                        if (quarter_count == 4'sd3) begin
                            quarter_count <= 4'sd0;
                            rotate_cw     <= 1'b1;
                        end else if (quarter_count < 0) begin
                            quarter_count <= 4'sd1;
                        end else begin
                            quarter_count <= quarter_count + 4'sd1;
                        end
                    end

                    4'b11_01, 4'b01_00,
                    4'b00_10, 4'b10_11: begin
                        if (quarter_count == -4'sd3) begin
                            quarter_count <= 4'sd0;
                            rotate_ccw    <= 1'b1;
                        end else if (quarter_count > 0) begin
                            quarter_count <= -4'sd1;
                        end else begin
                            quarter_count <= quarter_count - 4'sd1;
                        end
                    end

                    4'b00_00, 4'b01_01,
                    4'b10_10, 4'b11_11: begin
                        quarter_count <= quarter_count;
                    end

                    default: begin
                        // Invalid two-bit jump: discard the incomplete turn.
                        quarter_count <= 4'sd0;
                    end
                endcase

                ab_previous <= ab_current;
            end else begin
                ab_sample_count <= ab_sample_count + 1'b1;
            end

            // Active-low encoder push button, debounced for 20 ms.
            if (key_sync[1] == key_stable) begin
                key_debounce_count <= 32'd0;
            end else if (key_debounce_count >= KEY_DB_COUNT - 1) begin
                key_debounce_count <= 32'd0;
                key_stable         <= key_sync[1];
                if (!key_sync[1])
                    select_pulse <= 1'b1;
            end else begin
                key_debounce_count <= key_debounce_count + 1'b1;
            end
        end
    end

endmodule