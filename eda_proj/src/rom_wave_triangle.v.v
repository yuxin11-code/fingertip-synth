module rom_wave_triangle (
    input  wire              clk,
    input  wire              rst_n,
    input  wire [7:0]        addr,
    output reg signed [15:0] data
);

    function signed [15:0] triangle_value;
        input [7:0] phase_addr;

        reg signed [16:0] offset;
        reg signed [16:0] value;

        begin
            offset = $signed({1'b0, phase_addr[5:0], 9'b0});

            case (phase_addr[7:6])
                2'b00: value = offset;
                2'b01: value = 17'sd32767 - offset;
                2'b10: value = -offset;
                2'b11: value = -17'sd32768 + offset;
                default: value = 17'sd0;
            endcase

            triangle_value = value[15:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            data <= 16'sd0;
        else
            data <= triangle_value(addr);
    end

endmodule