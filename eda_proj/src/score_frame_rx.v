module score_frame_rx #(
    parameter integer CLK_HZ = 52500000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    input  wire        rx_error,

    output reg         packet_valid,
    output reg         packet_error,
    output reg [7:0]   packet_type,
    output reg [15:0]  packet_seq,
    output reg [7:0]   packet_len,
    output reg [95:0]  payload
);

    localparam [1:0] WAIT_AA = 0,
                     WAIT_55 = 1,
                     BODY = 2;

    // ���״̬�£�����20msû���ֽھͷ����������
    localparam integer GAP_LIMIT = CLK_HZ / 50;

    reg [1:0] state;
    reg [4:0] index;
    reg [31:0] gap_count;
    reg [15:0] crc;
    reg [7:0] crc_low;

    // ��ESP32 fpgaCrc16()������ͬ�㷨��
    function [15:0] crc_update;
        input [15:0] old_crc;
        input [7:0] data;
        reg [15:0] c;
        integer i;
        begin
            c = old_crc ^ {data, 8'h00};
            for (i = 0; i < 8; i = i + 1) begin
                if (c[15])
                    c = (c << 1) ^ 16'h1021;
                else
                    c = c << 1;
            end
            crc_update = c;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= WAIT_AA;
            index        <= 0;
            gap_count    <= 0;
            crc          <= 16'hFFFF;
            crc_low      <= 0;
            packet_valid <= 0;
            packet_error <= 0;
            packet_type  <= 0;
            packet_seq   <= 0;
            packet_len   <= 0;
            payload      <= 0;
        end else begin
            packet_valid <= 0;
            packet_error <= 0;

            if (rx_error) begin
                // ����ֹͣλ���󣬷�����ǰ����
                state        <= WAIT_AA;
                gap_count    <= 0;
                packet_error <= 1;
            end else if (rx_valid) begin
                gap_count <= 0;

                case (state)
                    WAIT_AA: begin
                        if (rx_data == 8'hAA)
                            state <= WAIT_55;
                    end

                    WAIT_55: begin
                        if (rx_data == 8'h55) begin
                            state <= BODY;
                            index <= 2;
                            crc   <= 16'hFFFF;
                        end else if (rx_data != 8'hAA) begin
                            state <= WAIT_AA;
                        end
                        // �����յ�AAʱ�������ȴ�55��
                    end

                    BODY: begin
                        // ��2��17�ֽ�ȫ������CRC���㡣
                        if (index <= 17)
                            crc <= crc_update(crc, rx_data);

                        case (index)
                            2:  packet_type     <= rx_data;
                            3:  packet_seq[7:0] <= rx_data;
                            4:  packet_seq[15:8]<= rx_data;
                            5:  packet_len      <= rx_data;
                            18: crc_low         <= rx_data;

                            19: begin
                                state <= WAIT_AA;
                                if (({rx_data, crc_low} == crc) &&      //ƴ��ESP32������CRC�����Լ���Ľ��бȶ�
                                    (packet_len <= 12))
                                    packet_valid <= 1;          //��Ч����
                                else
                                    packet_error <= 1;
                            end
                        endcase

                        // payload[7:0]��Ӧ�������ĵ�һ���ֽڡ�
                        if ((index >= 6) && (index <= 17))
                            payload[(index-6)*8 +: 8] <= rx_data;           //����ƴ��

                        if (index < 19)
                            index <= index + 1'b1;
                    end

                    default: state <= WAIT_AA;
                endcase
            end else if (state != WAIT_AA) begin
                if (gap_count == GAP_LIMIT - 1) begin
                    state        <= WAIT_AA;
                    gap_count    <= 0;
                    packet_error <= 1;
                end else begin
                    gap_count <= gap_count + 1'b1;
                end
            end else begin
                gap_count <= 0;
            end
        end
    end
endmodule
