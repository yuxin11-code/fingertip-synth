module timbre_select_control (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       key_n,
    output reg  [1:0] timbre_select
);

    localparam [13:0] DB_COUNT_MAX = 14'h3fff;

    reg key_meta;
    reg key_sync;
    reg key_stable;
    reg [13:0] key_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_meta      <= 1'b1;
            key_sync      <= 1'b1;
            key_stable    <= 1'b1;
            key_count     <= 14'd0;
            timbre_select <= 2'd0;
        end else begin
            key_meta <= key_n;
            key_sync <= key_meta;

            if (key_sync == key_stable) begin
                key_count <= 14'd0;
            end else if (key_count == DB_COUNT_MAX) begin
                key_stable <= key_sync;
                key_count  <= 14'd0;

                // 只在按下时切换
                if (!key_sync)
                    timbre_select <= timbre_select + 2'd1;
            end else begin
                key_count <= key_count + 1'b1;
            end
        end
    end

endmodule