module paj7620_controller #(
    parameter integer CLK_HZ = 1500000
)(
    input  wire       clk,
    input  wire       rst_n,
    inout  wire       paj_scl,
    inout  wire       paj_sda,

    output reg        right_pulse,
    output reg        left_pulse,
    output reg        gesture_valid,
    output reg  [3:0] gesture_code,
    output reg        init_ok,
    output reg        sensor_error
);

    localparam integer POWERUP_TICKS = CLK_HZ / 200; // 5 ms
    localparam integer POLL_TICKS    = CLK_HZ / 100; // 10 ms
    localparam integer RETRY_TICKS   = CLK_HZ / 2;   // retry every 500 ms
    localparam [7:0]   LAST_INIT_INDEX = 8'd218;

    localparam [4:0] ST_POWER_WAIT     = 5'd0;
    localparam [4:0] ST_BANK0_CMD      = 5'd1;
    localparam [4:0] ST_BANK0_WAIT     = 5'd2;
    localparam [4:0] ST_ID0_CMD        = 5'd3;
    localparam [4:0] ST_ID0_WAIT       = 5'd4;
    localparam [4:0] ST_ID1_CMD        = 5'd5;
    localparam [4:0] ST_ID1_WAIT       = 5'd6;
    localparam [4:0] ST_INIT_CMD       = 5'd7;
    localparam [4:0] ST_INIT_WAIT      = 5'd8;
    localparam [4:0] ST_FINAL_BANK_CMD = 5'd9;
    localparam [4:0] ST_FINAL_BANK_WAIT= 5'd10;
    localparam [4:0] ST_POLL_DELAY     = 5'd11;
    localparam [4:0] ST_GES0_CMD       = 5'd12;
    localparam [4:0] ST_GES0_WAIT      = 5'd13;
    localparam [4:0] ST_GES1_CMD       = 5'd14;
    localparam [4:0] ST_GES1_WAIT      = 5'd15;
    localparam [4:0] ST_ERROR          = 5'd16;

    localparam [3:0] GESTURE_NONE      = 4'd0;
    localparam [3:0] GESTURE_RIGHT     = 4'd1;
    localparam [3:0] GESTURE_LEFT      = 4'd2;
    localparam [3:0] GESTURE_UP        = 4'd3;
    localparam [3:0] GESTURE_DOWN      = 4'd4;
    localparam [3:0] GESTURE_FORWARD   = 4'd5;
    localparam [3:0] GESTURE_BACKWARD  = 4'd6;
    localparam [3:0] GESTURE_CLOCKWISE = 4'd7;
    localparam [3:0] GESTURE_ANTICLOCK = 4'd8;
    localparam [3:0] GESTURE_WAVE      = 4'd9;

    reg [4:0]  state;
    reg [31:0] wait_count;
    reg [7:0]  init_index;
    reg [7:0]  gesture0;
    reg        gesture_armed;
    reg        bank0_write_count;

    wire [7:0] init_reg_addr;
    wire [7:0] init_reg_data;

    reg        i2c_start;
    reg        i2c_read;
    reg [7:0]  i2c_reg_addr;
    reg [7:0]  i2c_write_data;
    wire [7:0] i2c_read_data;
    wire       i2c_busy;
    wire       i2c_done;
    wire       i2c_nack;

    paj7620_init_rom init_rom(
        .index(init_index),
        .reg_addr(init_reg_addr),
        .reg_data(init_reg_data)
    );

    paj7620_i2c_master #(
        .CLK_HZ(CLK_HZ),
        .I2C_HZ(100000),
        .I2C_ADDR(7'h73)
    ) i2c_master(
        .clk(clk),
        .rst_n(rst_n),
        .start(i2c_start),
        .read_not_write(i2c_read),
        .reg_addr(i2c_reg_addr),
        .write_data(i2c_write_data),
        .read_data(i2c_read_data),
        .busy(i2c_busy),
        .done(i2c_done),
        .nack_error(i2c_nack),
        .scl(paj_scl),
        .sda(paj_sda)
    );

    // Present a stable command for a full clock before the I2C master latches it.
    always @* begin
        i2c_start      = 1'b0;
        i2c_read       = 1'b0;
        i2c_reg_addr   = 8'h00;
        i2c_write_data = 8'h00;

        case (state)
            ST_BANK0_CMD,
            ST_FINAL_BANK_CMD: begin
                i2c_start      = !i2c_busy;
                i2c_read       = 1'b0;
                i2c_reg_addr   = 8'hEF;
                i2c_write_data = 8'h00;
            end

            ST_ID0_CMD: begin
                i2c_start    = !i2c_busy;
                i2c_read     = 1'b1;
                i2c_reg_addr = 8'h00;
            end

            ST_ID1_CMD: begin
                i2c_start    = !i2c_busy;
                i2c_read     = 1'b1;
                i2c_reg_addr = 8'h01;
            end

            ST_INIT_CMD: begin
                i2c_start      = !i2c_busy;
                i2c_read       = 1'b0;
                i2c_reg_addr   = init_reg_addr;
                i2c_write_data = init_reg_data;
            end

            ST_GES0_CMD: begin
                i2c_start    = !i2c_busy;
                i2c_read     = 1'b1;
                i2c_reg_addr = 8'h43;
            end

            ST_GES1_CMD: begin
                i2c_start    = !i2c_busy;
                i2c_read     = 1'b1;
                i2c_reg_addr = 8'h44;
            end

            default: begin
                i2c_start      = 1'b0;
                i2c_read       = 1'b0;
                i2c_reg_addr   = 8'h00;
                i2c_write_data = 8'h00;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_POWER_WAIT;
            wait_count      <= 32'd0;
            init_index      <= 8'd0;
            gesture0        <= 8'd0;
            gesture_armed   <= 1'b1;
            bank0_write_count <= 1'b0;
            right_pulse     <= 1'b0;
            left_pulse      <= 1'b0;
            gesture_valid   <= 1'b0;
            gesture_code    <= GESTURE_NONE;
            init_ok         <= 1'b0;
            sensor_error    <= 1'b0;
        end else begin
            right_pulse   <= 1'b0;
            left_pulse    <= 1'b0;
            gesture_valid <= 1'b0;

            case (state)
                ST_POWER_WAIT: begin
                    if (wait_count >= POWERUP_TICKS - 1) begin
                        wait_count <= 32'd0;
                        state      <= ST_BANK0_CMD;
                    end else begin
                        wait_count <= wait_count + 1'b1;
                    end
                end

                ST_BANK0_CMD: begin
                    if (!i2c_busy)
                        state <= ST_BANK0_WAIT;
                end

                ST_BANK0_WAIT: begin
                    if (i2c_done) begin
                        if (i2c_nack) begin
                            sensor_error <= 1'b1;
                            state        <= ST_ERROR;
                        end else if (!bank0_write_count) begin
                            // The supplied Arduino library writes Bank0 twice
                            // while waking the PAJ7620U2.
                            bank0_write_count <= 1'b1;
                            state             <= ST_BANK0_CMD;
                        end else begin
                            state <= ST_ID0_CMD;
                        end
                    end
                end

                ST_ID0_CMD: begin
                    if (!i2c_busy)
                        state <= ST_ID0_WAIT;
                end

                ST_ID0_WAIT: begin
                    if (i2c_done) begin
                        if (i2c_nack || i2c_read_data != 8'h20) begin
                            sensor_error <= 1'b1;
                            state        <= ST_ERROR;
                        end else begin
                            state <= ST_ID1_CMD;
                        end
                    end
                end

                ST_ID1_CMD: begin
                    if (!i2c_busy)
                        state <= ST_ID1_WAIT;
                end

                ST_ID1_WAIT: begin
                    if (i2c_done) begin
                        if (i2c_nack || i2c_read_data != 8'h76) begin
                            sensor_error <= 1'b1;
                            state        <= ST_ERROR;
                        end else begin
                            init_index <= 8'd0;
                            state      <= ST_INIT_CMD;
                        end
                    end
                end

                ST_INIT_CMD: begin
                    if (!i2c_busy)
                        state <= ST_INIT_WAIT;
                end

                ST_INIT_WAIT: begin
                    if (i2c_done) begin
                        if (i2c_nack) begin
                            sensor_error <= 1'b1;
                            state        <= ST_ERROR;
                        end else if (init_index == LAST_INIT_INDEX) begin
                            state <= ST_FINAL_BANK_CMD;
                        end else begin
                            init_index <= init_index + 1'b1;
                            state      <= ST_INIT_CMD;
                        end
                    end
                end

                ST_FINAL_BANK_CMD: begin
                    if (!i2c_busy)
                        state <= ST_FINAL_BANK_WAIT;
                end

                ST_FINAL_BANK_WAIT: begin
                    if (i2c_done) begin
                        if (i2c_nack) begin
                            sensor_error <= 1'b1;
                            state        <= ST_ERROR;
                        end else begin
                            init_ok       <= 1'b1;
                            wait_count    <= 32'd0;
                            gesture_armed <= 1'b1;
                            state         <= ST_POLL_DELAY;
                        end
                    end
                end

                ST_POLL_DELAY: begin
                    if (wait_count >= POLL_TICKS - 1) begin
                        wait_count <= 32'd0;
                        state      <= ST_GES0_CMD;
                    end else begin
                        wait_count <= wait_count + 1'b1;
                    end
                end

                ST_GES0_CMD: begin
                    if (!i2c_busy)
                        state <= ST_GES0_WAIT;
                end

                ST_GES0_WAIT: begin
                    if (i2c_done) begin
                        if (i2c_nack) begin
                            sensor_error <= 1'b1;
                            state        <= ST_ERROR;
                        end else begin
                            gesture0 <= i2c_read_data;
                            state    <= ST_GES1_CMD;
                        end
                    end
                end

                ST_GES1_CMD: begin
                    if (!i2c_busy)
                        state <= ST_GES1_WAIT;
                end

                ST_GES1_WAIT: begin
                    if (i2c_done) begin
                        if (i2c_nack) begin
                            sensor_error <= 1'b1;
                            state        <= ST_ERROR;
                        end else begin
                            if (gesture0 == 8'h00 && i2c_read_data == 8'h00) begin
                                gesture_armed <= 1'b1;
                            end else if (gesture_armed) begin
                                gesture_armed <= 1'b0;
                                gesture_valid <= 1'b1;

                                if (gesture0[0]) begin
                                    gesture_code <= GESTURE_RIGHT;
                                    right_pulse  <= 1'b1;
                                end else if (gesture0[1]) begin
                                    gesture_code <= GESTURE_LEFT;
                                    left_pulse   <= 1'b1;
                                end else if (gesture0[2]) begin
                                    gesture_code <= GESTURE_UP;
                                end else if (gesture0[3]) begin
                                    gesture_code <= GESTURE_DOWN;
                                end else if (gesture0[4]) begin
                                    gesture_code <= GESTURE_FORWARD;
                                end else if (gesture0[5]) begin
                                    gesture_code <= GESTURE_BACKWARD;
                                end else if (gesture0[6]) begin
                                    gesture_code <= GESTURE_CLOCKWISE;
                                end else if (gesture0[7]) begin
                                    gesture_code <= GESTURE_ANTICLOCK;
                                end else if (i2c_read_data[0]) begin
                                    gesture_code <= GESTURE_WAVE;
                                end else begin
                                    gesture_code <= GESTURE_NONE;
                                end
                            end

                            wait_count <= 32'd0;
                            state      <= ST_POLL_DELAY;
                        end
                    end
                end

                ST_ERROR: begin
                    init_ok <= 1'b0;
                    if (wait_count >= RETRY_TICKS - 1) begin
                        wait_count         <= 32'd0;
                        init_index        <= 8'd0;
                        gesture0          <= 8'd0;
                        gesture_armed     <= 1'b1;
                        bank0_write_count <= 1'b0;
                        sensor_error      <= 1'b0;
                        state             <= ST_POWER_WAIT;
                    end else begin
                        wait_count <= wait_count + 1'b1;
                    end
                end

                default: begin
                    state <= ST_POWER_WAIT;
                end
            endcase
        end
    end

endmodule
