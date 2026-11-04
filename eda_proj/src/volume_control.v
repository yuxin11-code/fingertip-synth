// Button controlled digital volume for Tang Mega 138K Dock.
// KEY inputs are active-low and have the board's internal pull-ups enabled.
// The volume is changed once per debounced press: 10% .. 100%.
module volume_control(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       key_up_n,
    input  wire       key_down_n,
    output reg  [16:0] volume_q16
);
    localparam integer DB_COUNT_MAX = 14'h3fff; // about 10.9 ms at 1.5 MHz

    reg up_meta, up_sync, up_stable;
    reg down_meta, down_sync, down_stable;
    reg [13:0] up_count, down_count;
    reg [3:0] level;

    function [16:0] level_to_q16;
        input [3:0] n;
        begin
            case (n)
                4'd0:  level_to_q16 = 17'd0;
                4'd1:  level_to_q16 = 17'd6554;
                4'd2:  level_to_q16 = 17'd13107;
                4'd3:  level_to_q16 = 17'd19661;
                4'd4:  level_to_q16 = 17'd26214;
                4'd5:  level_to_q16 = 17'd32768;
                4'd6:  level_to_q16 = 17'd39322;
                4'd7:  level_to_q16 = 17'd45875;
                4'd8:  level_to_q16 = 17'd52429;
                4'd9:  level_to_q16 = 17'd58982;
                default: level_to_q16 = 17'd65536;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            up_meta     <= 1'b1;
            up_sync     <= 1'b1;
            up_stable   <= 1'b1;
            down_meta   <= 1'b1;
            down_sync   <= 1'b1;
            down_stable <= 1'b1;
            up_count    <= 14'd0;
            down_count  <= 14'd0;
            level       <= 4'd1; // required power-on default: 10%
        end else begin
            up_meta   <= key_up_n;
            up_sync   <= up_meta;
            down_meta <= key_down_n;
            down_sync <= down_meta;

            if (up_sync == up_stable) begin
                up_count <= 14'd0;
            end else if (up_count == DB_COUNT_MAX) begin
                up_stable <= up_sync;
                up_count  <= 14'd0;
                if (!up_sync && (level < 4'd10))
                    level <= level + 1'b1;
            end else begin
                up_count <= up_count + 1'b1;
            end

            if (down_sync == down_stable) begin
                down_count <= 14'd0;
            end else if (down_count == DB_COUNT_MAX) begin
                down_stable <= down_sync;
                down_count  <= 14'd0;
                if (!down_sync && (level != 4'd0))
                    level <= level - 1'b1;
            end else begin
                down_count <= down_count + 1'b1;
            end
        end
    end

    always @* begin
        volume_q16 = level_to_q16(level);
    end
endmodule
