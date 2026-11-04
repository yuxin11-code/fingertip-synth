module score_ram (
    input  wire        clk,

    input  wire        we,
    input  wire [7:0]  waddr,
    input  wire [87:0] wdata,

    input  wire        rd_en,
    input  wire [7:0]  raddr,
    output reg [87:0]  rdata
);

    // 256��������ÿ��88λ��
    reg [87:0] memory [0:255];

    // ͬ��д�롢ͬ����ȡ�������ۺ�ΪƬ��RAM��
    always @(posedge clk) begin
        if (we)
            memory[waddr] <= wdata;

        if (rd_en)
            rdata <= memory[raddr];
    end
endmodule
