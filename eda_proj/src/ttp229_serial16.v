// TTP229-BSF proprietary two-wire interface (not I2C).
// Each frame starts from the sensor's timeout-reset boundary. D0 maps to bit 0.
module ttp229_serial16 #(
    parameter integer CLK_HZ = 1500000,
    parameter integer SCL_HZ = 20000,
    parameter integer ACTIVE_LOW = 1
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sdo,
    output reg         scl,
    output reg [15:0]  touch_keys,
    output reg         frame_valid,
    output reg         busy
);
    localparam IDLE_LEVEL = ACTIVE_LOW ? 1'b1 : 1'b0;
    localparam ACTIVE_LEVEL = !IDLE_LEVEL;
    // Four clocks minimum leaves margin for the two-stage SDO synchronizer.
    localparam integer HALF_TICKS_CALC = CLK_HZ / (SCL_HZ * 2);
    localparam integer HALF_TICKS = HALF_TICKS_CALC < 4 ? 4 : HALF_TICKS_CALC;
    localparam integer POWERUP_TICKS = CLK_HZ < 1 ? 1 : CLK_HZ; // 1 second
    localparam integer RESYNC_TICKS = (CLK_HZ / 250) < 1 ? 1 : (CLK_HZ / 250);
    localparam integer DV_POLL_TICKS =(CLK_HZ / 1000) < 1 ? 1 : (CLK_HZ / 1000);
    localparam integer GUARD_TICKS = (CLK_HZ / 50000) < 4 ? 4 : (CLK_HZ / 50000);
    localparam integer DV_STUCK_TICKS = (CLK_HZ / 500) < 1 ? 1 : (CLK_HZ / 500);

    localparam [2:0] ST_RESYNC = 3'd0;
    localparam [2:0] ST_WAIT_DV = 3'd1;
    localparam [2:0] ST_DV_END = 3'd2;
    localparam [2:0] ST_GUARD = 3'd3;
    localparam [2:0] ST_SAMPLE = 3'd4;
    localparam [2:0] ST_HIGH = 3'd5;

    // Explicit FPGA power-up values also start the wait on a cold boot when
    // the external reset button has never been pressed. Gowin maps these to GSR.
    reg [31:0] powerup_count = 32'd0;
    reg powerup_done = 1'b0;
    wire reader_rst_n = rst_n && powerup_done;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            powerup_count <= 32'd0;
            powerup_done <= 1'b0;
        end else if (!powerup_done) begin
            if (powerup_count >= POWERUP_TICKS - 1)
                powerup_done <= 1'b1;
            else
                powerup_count <= powerup_count + 1'b1;
        end
    end

    reg [2:0] state;
    reg [31:0] wait_count;
    reg [31:0] phase_count;
    reg [3:0] bit_count;
    reg [15:0] shift_data;
    reg [1:0] sdo_sync;
    wire sdo_active = (sdo_sync[1] == ACTIVE_LEVEL);
    wire bit_value = ACTIVE_LOW ? ~sdo_sync[1] : sdo_sync[1];

    always @(posedge clk or negedge reader_rst_n) begin
        if (!reader_rst_n) begin
            sdo_sync <= {2{IDLE_LEVEL}};
            state <= ST_RESYNC;
            scl <= IDLE_LEVEL;
            wait_count <= 32'd0;
            phase_count <= 32'd0;
            bit_count <= 4'd0;
            shift_data <= 16'd0;
            touch_keys <= 16'd0;
            frame_valid <= 1'b0;
            busy <= 1'b0;
        end else begin
            sdo_sync <= {sdo_sync[0], sdo};
            frame_valid <= 1'b0;
            case (state)
                ST_RESYNC: begin
                    scl <= IDLE_LEVEL;
                    busy <= 1'b0;
                    phase_count <= 32'd0;
                    // 4 ms without any SCL edge exceeds the 2 ms device timeout.
                    // Reset BOTH ends of the frame, not only the FPGA bit index.
                    if (wait_count >= RESYNC_TICKS - 1) begin
                        wait_count <= 32'd0;
                        state <= ST_WAIT_DV;
                    end else
                        wait_count <= wait_count + 1'b1;
                end

                ST_WAIT_DV: begin
                    scl <= IDLE_LEVEL;
                    // Prefer the device's DV notification. Poll as a fallback
                    // for modules that suppress notifications with no changes.
                    if (sdo_active) begin
                        wait_count <= 32'd0;
                        state <= ST_DV_END;
                    end else if (wait_count >= DV_POLL_TICKS - 1) begin
                        wait_count <= 32'd0;
                        state <= ST_GUARD;
                    end else
                        wait_count <= wait_count + 1'b1;
                end

                ST_DV_END: begin
                    scl <= IDLE_LEVEL;
                    // DV is NOT D0. Wait for its actual end, not a fixed delay
                    // counted from whichever point in DV happened to be seen.
                    if (!sdo_active) begin
                        wait_count <= 32'd0;
                        state <= ST_GUARD;
                    end else if (wait_count >= DV_STUCK_TICKS - 1) begin
                        wait_count <= 32'd0;
                        touch_keys <= 16'd0;
                        state <= ST_RESYNC;
                    end else
                        wait_count <= wait_count + 1'b1;
                end

                ST_GUARD: begin
                    scl <= IDLE_LEVEL;
                    if (sdo_active) begin
                        wait_count <= 32'd0;
                        state <= ST_DV_END;
                    end else if (wait_count >= GUARD_TICKS - 1) begin
                        // Datasheet Tw >= 10 us; allow 20 us after DV returns idle.
                        wait_count <= 32'd0;
                        phase_count <= 32'd0;
                        bit_count <= 4'd0;
                        shift_data <= 16'd0;
                        busy <= 1'b1;
                        scl <= ACTIVE_LEVEL; // first edge selects D0
                        state <= ST_SAMPLE;
                    end else
                        wait_count <= wait_count + 1'b1;
                end

                ST_SAMPLE: begin
                    busy <= 1'b1;
                    if (phase_count >= HALF_TICKS - 1) begin
                        // Sample AFTER the active edge and SDO synchronization.
                        shift_data[bit_count] <= bit_value;
                        scl <= IDLE_LEVEL;
                        phase_count <= 32'd0;
                        state <= ST_HIGH;
                    end else
                        phase_count <= phase_count + 1'b1;
                end

                ST_HIGH: begin
                    busy <= 1'b1;
                    if (phase_count >= HALF_TICKS - 1) begin
                        phase_count <= 32'd0;
                        if (bit_count == 4'd15) begin
                            // Bit 15 was stored in ST_SAMPLE on an earlier clock.
                            frame_valid <= 1'b1;
                            busy <= 1'b0;
                            touch_keys <= shift_data;
                            wait_count <= 32'd0;
                            state <= ST_RESYNC;
                        end else begin
                            bit_count <= bit_count + 1'b1;
                            scl <= ACTIVE_LEVEL;
                            state <= ST_SAMPLE;
                        end
                    end else
                        phase_count <= phase_count + 1'b1;
                end

                default: begin
                    scl <= IDLE_LEVEL;
                    busy <= 1'b0;
                    wait_count <= 32'd0;
                    touch_keys <= 16'd0;
                    state <= ST_RESYNC;
                end
            endcase
        end
    end
endmodule
