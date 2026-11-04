module paj7620_i2c_master #(
    parameter integer CLK_HZ   = 1500000,
    parameter integer I2C_HZ   = 100000,
    parameter [6:0]   I2C_ADDR = 7'h73
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire       read_not_write,
    input  wire [7:0] reg_addr,
    input  wire [7:0] write_data,

    output reg  [7:0] read_data,
    output reg        busy,
    output reg        done,
    output reg        nack_error,

    inout  wire       scl,
    inout  wire       sda
);

    // 1.5 MHz / (2 * 8) = 93.75 kHz, close to standard-mode 100 kHz I2C.
    localparam integer HALF_TICKS_RAW =
        (CLK_HZ + I2C_HZ) / (I2C_HZ * 2);
    localparam integer HALF_TICKS =
        (HALF_TICKS_RAW < 1) ? 1 : HALF_TICKS_RAW;

    localparam [4:0] ST_IDLE          = 5'd0;
    localparam [4:0] ST_START_RELEASE = 5'd1;
    localparam [4:0] ST_START_SDA     = 5'd2;
    localparam [4:0] ST_START_SCL     = 5'd3;
    localparam [4:0] ST_TX_SETUP      = 5'd4;
    localparam [4:0] ST_TX_HIGH       = 5'd5;
    localparam [4:0] ST_TX_LOW        = 5'd6;
    localparam [4:0] ST_ACK_HIGH      = 5'd7;
    localparam [4:0] ST_ACK_SAMPLE    = 5'd8;
    localparam [4:0] ST_RSTART_REL    = 5'd9;
    localparam [4:0] ST_RSTART_SDA    = 5'd10;
    localparam [4:0] ST_RSTART_SCL    = 5'd11;
    localparam [4:0] ST_RX_SETUP      = 5'd12;
    localparam [4:0] ST_RX_HIGH       = 5'd13;
    localparam [4:0] ST_RX_SAMPLE     = 5'd14;
    localparam [4:0] ST_NACK_SETUP    = 5'd15;
    localparam [4:0] ST_NACK_HIGH     = 5'd16;
    localparam [4:0] ST_NACK_LOW      = 5'd17;
    localparam [4:0] ST_STOP_LOW      = 5'd18;
    localparam [4:0] ST_STOP_HIGH     = 5'd19;
    localparam [4:0] ST_STOP_RELEASE  = 5'd20;

    reg [4:0]  state;
    reg [31:0] divider_count;
    reg        scl_drive_low;
    reg        sda_drive_low;
    reg        op_read;
    reg [7:0]  reg_addr_latched;
    reg [7:0]  write_data_latched;
    reg [7:0]  tx_byte;
    reg [2:0]  bit_index;
    reg [1:0]  tx_stage;

    // I2C lines are open drain: drive only zero, otherwise release the line.
    assign scl = scl_drive_low ? 1'b0 : 1'bz;
    assign sda = sda_drive_low ? 1'b0 : 1'bz;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= ST_IDLE;
            divider_count      <= 32'd0;
            scl_drive_low      <= 1'b0;
            sda_drive_low      <= 1'b0;
            op_read            <= 1'b0;
            reg_addr_latched   <= 8'd0;
            write_data_latched <= 8'd0;
            tx_byte            <= 8'd0;
            bit_index          <= 3'd7;
            tx_stage           <= 2'd0;
            read_data          <= 8'd0;
            busy               <= 1'b0;
            done               <= 1'b0;
            nack_error         <= 1'b0;
        end else begin
            done <= 1'b0;

            if (state == ST_IDLE) begin
                divider_count <= 32'd0;
                scl_drive_low <= 1'b0;
                sda_drive_low <= 1'b0;
                busy          <= 1'b0;

                if (start) begin
                    op_read            <= read_not_write;
                    reg_addr_latched   <= reg_addr;
                    write_data_latched <= write_data;
                    read_data          <= 8'd0;
                    nack_error         <= 1'b0;
                    busy               <= 1'b1;
                    state              <= ST_START_RELEASE;
                end
            end else if (divider_count >= HALF_TICKS - 1) begin
                divider_count <= 32'd0;

                case (state)
                    ST_START_RELEASE: begin
                        scl_drive_low <= 1'b0;
                        sda_drive_low <= 1'b0;
                        state         <= ST_START_SDA;
                    end

                    ST_START_SDA: begin
                        // SDA falling while SCL is high is START.
                        sda_drive_low <= 1'b1;
                        state         <= ST_START_SCL;
                    end

                    ST_START_SCL: begin
                        scl_drive_low <= 1'b1;
                        tx_byte       <= {I2C_ADDR, 1'b0};
                        bit_index     <= 3'd7;
                        tx_stage      <= 2'd0;
                        state         <= ST_TX_SETUP;
                    end

                    ST_TX_SETUP: begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= ~tx_byte[bit_index];
                        state         <= ST_TX_HIGH;
                    end

                    ST_TX_HIGH: begin
                        scl_drive_low <= 1'b0;
                        state         <= ST_TX_LOW;
                    end

                    ST_TX_LOW: begin
                        scl_drive_low <= 1'b1;
                        if (bit_index == 3'd0) begin
                            // Release SDA for the slave ACK bit.
                            sda_drive_low <= 1'b0;
                            state         <= ST_ACK_HIGH;
                        end else begin
                            bit_index <= bit_index - 1'b1;
                            state     <= ST_TX_SETUP;
                        end
                    end

                    ST_ACK_HIGH: begin
                        scl_drive_low <= 1'b0;
                        state         <= ST_ACK_SAMPLE;
                    end

                    ST_ACK_SAMPLE: begin
                        scl_drive_low <= 1'b1;
                        if (sda) begin
                            nack_error <= 1'b1;
                            state      <= ST_STOP_LOW;
                        end else begin
                            case (tx_stage)
                                2'd0: begin
                                    tx_byte   <= reg_addr_latched;
                                    bit_index <= 3'd7;
                                    tx_stage  <= 2'd1;
                                    state     <= ST_TX_SETUP;
                                end

                                2'd1: begin
                                    if (op_read) begin
                                        state <= ST_RSTART_REL;
                                    end else begin
                                        tx_byte   <= write_data_latched;
                                        bit_index <= 3'd7;
                                        tx_stage  <= 2'd2;
                                        state     <= ST_TX_SETUP;
                                    end
                                end

                                2'd2: begin
                                    state <= ST_STOP_LOW;
                                end

                                default: begin
                                    // ACK after address + read.
                                    bit_index <= 3'd7;
                                    state     <= ST_RX_SETUP;
                                end
                            endcase
                        end
                    end

                    ST_RSTART_REL: begin
                        sda_drive_low <= 1'b0;
                        scl_drive_low <= 1'b0;
                        state         <= ST_RSTART_SDA;
                    end

                    ST_RSTART_SDA: begin
                        sda_drive_low <= 1'b1;
                        state         <= ST_RSTART_SCL;
                    end

                    ST_RSTART_SCL: begin
                        scl_drive_low <= 1'b1;
                        tx_byte       <= {I2C_ADDR, 1'b1};
                        bit_index     <= 3'd7;
                        tx_stage      <= 2'd3;
                        state         <= ST_TX_SETUP;
                    end

                    ST_RX_SETUP: begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= 1'b0;
                        state         <= ST_RX_HIGH;
                    end

                    ST_RX_HIGH: begin
                        scl_drive_low <= 1'b0;
                        state         <= ST_RX_SAMPLE;
                    end

                    ST_RX_SAMPLE: begin
                        read_data[bit_index] <= sda;
                        scl_drive_low        <= 1'b1;
                        if (bit_index == 3'd0) begin
                            state <= ST_NACK_SETUP;
                        end else begin
                            bit_index <= bit_index - 1'b1;
                            state     <= ST_RX_SETUP;
                        end
                    end

                    ST_NACK_SETUP: begin
                        // Only one byte is read, so the master returns NACK.
                        sda_drive_low <= 1'b0;
                        scl_drive_low <= 1'b1;
                        state         <= ST_NACK_HIGH;
                    end

                    ST_NACK_HIGH: begin
                        scl_drive_low <= 1'b0;
                        state         <= ST_NACK_LOW;
                    end

                    ST_NACK_LOW: begin
                        scl_drive_low <= 1'b1;
                        state         <= ST_STOP_LOW;
                    end

                    ST_STOP_LOW: begin
                        scl_drive_low <= 1'b1;
                        sda_drive_low <= 1'b1;
                        state         <= ST_STOP_HIGH;
                    end

                    ST_STOP_HIGH: begin
                        scl_drive_low <= 1'b0;
                        state         <= ST_STOP_RELEASE;
                    end

                    ST_STOP_RELEASE: begin
                        // SDA rising while SCL is high is STOP.
                        sda_drive_low <= 1'b0;
                        busy          <= 1'b0;
                        done          <= 1'b1;
                        state         <= ST_IDLE;
                    end

                    default: begin
                        state <= ST_IDLE;
                    end
                endcase
            end else begin
                divider_count <= divider_count + 1'b1;
            end
        end
    end

endmodule
