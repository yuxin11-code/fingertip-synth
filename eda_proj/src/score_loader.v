module score_loader #(
    parameter integer CLK_HZ = 52500000//�� 115200 �����ʵ�������
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        packet_valid,
    input  wire        packet_error,
    input  wire [7:0]  packet_type,
    input  wire [15:0] packet_seq,
    input  wire [7:0]  packet_len,
    input  wire [95:0] payload,

    output reg         receiving,
    output reg         score_valid,
    output reg         receive_error,
    output reg [15:0]  received_count,

    output reg [15:0]  note_count,
    output reg [15:0]  bpm,
    output reg [15:0]  ticks_per_beat,
    output reg [31:0]  length_ticks,

    output reg         ram_we,
    output reg [7:0]   ram_waddr,
    output reg [87:0]  ram_wdata
);

    // ���׽��չ����У�2��û�����������ж���ʱ��
    localparam integer TIMEOUT_CLKS = CLK_HZ * 2;
    reg [31:0] timeout_count;
    reg [31:0] last_tick;

    // START���ֶΡ�
    wire [15:0] start_count = payload[31:16];
    wire [15:0] start_bpm   = payload[47:32];
    wire [15:0] start_tpb   = payload[63:48];
    wire [31:0] start_length= payload[95:64];

    wire start_ok =
        (packet_seq == 0) &&
        (packet_len == 12) &&
        (payload[7:0] == 1) &&        // Э��汾
        (payload[15:8] == 0) &&       // �����ֶ�
        (start_count >= 1) &&
        (start_count <= 256) &&
        (start_bpm >= 20) &&
        (start_bpm <= 300) &&
        (start_tpb >= 1) &&
        (start_tpb <= 9600) &&
        (start_length >= 1) &&
        (start_length <= 10000000);

    // NOTE���ֶΡ�
    wire [31:0] note_tick = payload[31:0];
    wire [31:0] note_duration = payload[63:32];
    wire [7:0] note_pitch = payload[71:64];
    wire [7:0] note_velocity = payload[79:72];
    wire [7:0] note_part = payload[87:80];

    wire note_ok =
        (packet_len == 11) &&
        (packet_seq == received_count + 16'd1) &&
        (received_count < note_count) &&
        (payload[95:88] == 0) &&      // δʹ���ֽ�Ӧ����
        (note_tick < length_ticks) &&
        (note_tick >= last_tick) &&
        (note_duration >= 1) &&
        // �ü����жϣ�����tick+duration�����
        (note_duration <= length_ticks - note_tick) &&
        (note_pitch <= 127) &&
        (note_velocity >= 1) &&
        (note_velocity <= 127) &&
        (note_part <= 15);

    wire end_ok =
        (packet_len == 2) &&
        (packet_seq == received_count + 16'd1) &&
        (received_count == note_count) &&
        (payload[15:0] == note_count) &&
        (payload[95:16] == 0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            receiving      <= 0;
            score_valid    <= 0;
            receive_error  <= 0;
            received_count <= 0;
            note_count     <= 0;
            bpm            <= 0;
            ticks_per_beat <= 0;
            length_ticks   <= 0;
            last_tick      <= 0;
            timeout_count  <= 0;
            ram_we         <= 0;
            ram_waddr      <= 0;
            ram_wdata      <= 0;
        end else begin
            ram_we <= 0; // Ĭ�ϲ�дRAM

            if (packet_error) begin
                receive_error <= 1;
                timeout_count <= 0;

                if (receiving) begin
                    receiving   <= 0;
                    score_valid <= 0;
                end

            end else if (packet_valid) begin
                timeout_count <= 0;

                // �¿�ʼ�����������������ա�
                if (packet_type == 8'h01) begin
                    score_valid    <= 0;
                    received_count <= 0;
                    last_tick      <= 0;

                    if (start_ok) begin
                        receiving      <= 1;
                        receive_error  <= 0;
                        note_count     <= start_count;
                        bpm            <= start_bpm;
                        ticks_per_beat <= start_tpb;
                        length_ticks   <= start_length;
                    end else begin
                        receiving     <= 0;
                        receive_error <= 1;
                    end

                end else if (receiving) begin
                    if ((packet_type == 8'h02) && note_ok) begin
                        // 0��255��ַ������256��������
                        ram_we    <= 1;
                        ram_waddr <= received_count[7:0];

                        // 11�ֽ�����ԭ���洢���ֶ�λ�ü����ġ�
                        ram_wdata <= payload[87:0];

                        received_count <= received_count + 16'd1;
                        last_tick <= note_tick;

                    end else if ((packet_type == 8'h03) && end_ok) begin
                        receiving   <= 0;
                        score_valid <= 1;
                    end else begin
                        // ��Ų��ԡ��������Ի�Ƿ��ֶεȡ�
                        receiving     <= 0;
                        score_valid   <= 0;
                        receive_error <= 1;
                    end
                end
                // ��δ�յ�STARTʱ�������չ�����NOTE/END��

            end else if (receiving) begin
                if (timeout_count == TIMEOUT_CLKS - 1) begin
                    receiving     <= 0;
                    score_valid   <= 0;
                    receive_error <= 1;
                    timeout_count <= 0;
                end else begin
                    timeout_count <= timeout_count + 1'b1;
                end
            end else begin
                timeout_count <= 0;
            end
        end
    end
endmodule
