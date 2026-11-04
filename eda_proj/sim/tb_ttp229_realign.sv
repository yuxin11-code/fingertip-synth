`timescale 1ns/1ns

// Device model follows the datasheet interface, not the reader state machine:
// D0..D15 appear 2 us AFTER each active SCL edge; 2 ms without edges resets it.
module ttp229_case #(
    parameter integer ACTIVE_LOW = 1,
    parameter integer SEND_DV = 1,
    parameter integer CASE_ID = 0,
    parameter integer COLD_BOOT = 0,
    parameter integer CLOCK_HZ = 1000000,
    parameter integer DV_NS = 93000
)(output reg done = 0);
    localparam IDLE_LEVEL = ACTIVE_LOW ? 1'b1 : 1'b0;
    localparam ACTIVE_LEVEL = !IDLE_LEVEL;
    reg clk = 0;
    localparam real HALF_CLK_NS = 500000000.0 / CLOCK_HZ;
    always #(HALF_CLK_NS) clk = !clk;
    reg rst_n = COLD_BOOT ? 1'b1 : 1'b0;
    reg sdo = IDLE_LEVEL;
    wire scl;
    wire [15:0] touch_keys;
    wire frame_valid, busy;
    reg ready = 0;
    reg dv_active = 0;
    reg timeout_seen = 1;
    integer drop_edges_remaining = 0;
    reg [15:0] keys = 0;
    reg [15:0] latched_keys = 0;
    integer device_index = 0;
    integer edge_count = 0;
    integer frame_count = 0;
    integer burst_edges = 0;
    time last_edge = 0;
    time last_dv_end = 0;
    time burst_start = 0;

    ttp229_serial16 #(.CLK_HZ(CLOCK_HZ), .SCL_HZ(20000),
                     .ACTIVE_LOW(ACTIVE_LOW)) dut (
        .clk(clk), .rst_n(rst_n), .sdo(sdo), .scl(scl),
        .touch_keys(touch_keys), .frame_valid(frame_valid), .busy(busy)
    );

    task fail(input string message);
        $display("FAIL case=%0d time=%0t: %s", CASE_ID, $time, message);
        $fatal(1);
    endtask

    task on_active_edge;
        begin
            if (rst_n && $time > 50000) begin
                edge_count = edge_count + 1;
                if ($time < 550000000)
                    fail("SCL clocks during the sensor power-up stabilization interval");
                if (burst_edges == 0) burst_start = $time;
                burst_edges = burst_edges + 1;
                if (burst_edges > 16) fail("more than 16 clocks between timeout boundaries");
                last_edge = $time;
                timeout_seen = 0;
                if (ready) begin
                    if (dv_active) fail("clock started during the data-valid pulse");
                    if (SEND_DV && $time - last_dv_end < 10000)
                        fail("less than datasheet Tw=10 us after DV");
                    if (drop_edges_remaining > 0) begin
                        drop_edges_remaining = drop_edges_remaining - 1;
                    end else begin
                        if (device_index == 0) latched_keys = keys;
                        sdo <= #2000 (latched_keys[device_index] ? ACTIVE_LEVEL : IDLE_LEVEL);
                        device_index = (device_index + 1) % 16;
                    end
                end
            end
        end
    endtask
    generate
        if (ACTIVE_LOW) begin
            always @(negedge scl) on_active_edge();
        end else begin
            always @(posedge scl) on_active_edge();
        end
    endgenerate

    // Device timeout is independent of the FPGA's bit counter and reset.
    always begin
        #1000;
        if (!timeout_seen && $time - last_edge > 2000000) begin
            timeout_seen = 1;
            device_index = 0;
            burst_edges = 0;
            if (!dv_active) sdo <= IDLE_LEVEL;
        end
    end

    // Independent scan clock, deliberately asynchronous to the reader.
    initial begin
        #(620000000 + CASE_ID * 37000);
        forever begin
            #32000000;
            if (SEND_DV && ready && timeout_seen) begin
                dv_active = 1;
                sdo <= ACTIVE_LEVEL;
                #(DV_NS);
                sdo <= IDLE_LEVEL;
                dv_active = 0;
                last_dv_end = $time;
            end
        end
    end

    always @(posedge clk) begin
        if (frame_valid) frame_count = frame_count + 1;
    end

    task expect_keys(input [15:0] expected);
        integer elapsed;
        begin
            keys = expected;
            elapsed = 0;
            while (touch_keys !== expected && elapsed < 250) begin
                #1000000;
                elapsed = elapsed + 1;
            end
            if (touch_keys !== expected) begin
                $display("expected=%04h actual=%04h", expected, touch_keys);
                fail("key bitmap did not converge to the physical electrodes");
            end
            #80000000;
            if (touch_keys !== expected) fail("bitmap changed during a held key/chord");
        end
    endtask

    integer k;
    initial begin
        #50000;
        if (scl !== IDLE_LEVEL) fail("wrong SCL idle polarity during reset");
        rst_n = 1;
        #550000000;
        if (edge_count != 0) fail("no sensor stabilization wait");
        ready = 1;
        #650000000;
        if (frame_count < 2) fail("reader never produced complete frames");
        expect_keys(16'h0000);
        for (k = 0; k < 16; k = k + 1) expect_keys(16'h0001 << k);
        expect_keys(16'h8001);
        expect_keys(16'h00f0);
        expect_keys(16'ha55a);
        expect_keys(16'hffff);
        expect_keys(16'h0000);

        // Lose a clock at the device only. The next timeout must recover D0.
        drop_edges_remaining = 1;
        expect_keys(16'h0010);
        expect_keys(16'h8000);
        expect_keys(16'h0000);

        // Exercise every possible retained frame offset, including 15 = -1.
        for (k = 1; k < 16; k = k + 1) begin
            drop_edges_remaining = k;
            expect_keys(16'h0001 << k);
        end
        expect_keys(16'h0000);

        // Sensor-only power cycle while FPGA keeps running, with late readiness.
        ready = 0;
        sdo = IDLE_LEVEL;
        keys = 16'h0100;
        #570123000;
        device_index = 11;
        ready = 1;
        expect_keys(16'h0100);
        expect_keys(16'h0000);

        // FPGA-only reset: the sensor may be in the middle of a serial frame.
        device_index = 7;
        rst_n = 0;
        #50000;
        rst_n = 1;
        #1100000000;
        expect_keys(16'h0001);
        expect_keys(16'h0000);
        $display("PASS case=%0d active_low=%0d DV=%0d cold_boot=%0d clk=%0d: 16 keys, chords, release, all 15 lost-edge offsets, sensor/FPGA resets (%0d frames)",
                 CASE_ID, ACTIVE_LOW, SEND_DV, COLD_BOOT, CLOCK_HZ, frame_count);
        done = 1;
    end
endmodule

module tb_ttp229_realign;
    wire done0, done1, done2, done3;
    ttp229_case #(.CASE_ID(0)) low_dv(done0);
    ttp229_case #(.ACTIVE_LOW(0), .CASE_ID(1)) high_dv(done1);
    ttp229_case #(.SEND_DV(0), .CASE_ID(2)) polling(done2);
    ttp229_case #(.COLD_BOOT(1), .CLOCK_HZ(1500000), .DV_NS(170000),
                 .CASE_ID(3)) cold_boot(done3);
    initial begin
        wait(done0 && done1 && done2 && done3);
        $display("ALL TTP229 RTL REGRESSIONS PASSED");
        $finish;
    end
    initial begin
        #(64'd16000000000);
        $fatal(1, "global test watchdog");
    end
endmodule
