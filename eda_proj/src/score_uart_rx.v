module score_uart_rx #(
    parameter integer CLK_HZ = 52500000,
    parameter integer BAUD   = 115200
)(
    input  wire       clk,
    input  wire       rst_n,       // �͵�ƽ��λ
    input  wire       rx,

    output reg [7:0]  rx_data,
    output reg        rx_valid,    // �յ�һ���ֽڣ�����һ��ʱ������
    output reg        frame_error  // ֹͣλ��������һ��ʱ������
);

    // �����������һ������λ��Ӧ����ϵͳʱ�ӡ�
    // 52.5 MHz / 115200��ԼΪ456��ʱ�ӡ�
    localparam integer BIT_CLKS =
        (CLK_HZ + BAUD / 2) / BAUD;

    localparam [1:0]
        IDLE  = 2'd0,
        START = 2'd1,
        DATA  = 2'd2,
        STOP  = 2'd3;

    reg [1:0]  state;
    reg [31:0] clk_count;
    reg [2:0]  bit_index;
    reg [7:0]  shift_data;

    // RX����ESP32����FPGAʱ�Ӳ�ͬ����
    // �Ⱦ��������Ĵ������ٽ���״̬����
    reg rx_meta;
    reg rx_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            clk_count   <= 0;
            bit_index   <= 0;
            shift_data  <= 0;
            rx_data     <= 0;
            rx_valid    <= 0;
            frame_error <= 0;
        end else begin
            // Ĭ�����㣬ʹ���������ֻά��һ��ʱ�����ڡ�
            rx_valid    <= 1'b0;
            frame_error <= 1'b0;

            case (state)

                IDLE: begin
                    clk_count <= 0;
                    bit_index <= 0;

                    // UART����Ϊ�ߣ��͵�ƽ��ʾ���ܳ�����ʼλ��
                    if (!rx_sync)
                        state <= START;
                end

                START: begin
                    // �ȵ���ʼλ�е㣬��ȷ������ȻΪ�͡�
                    if (clk_count == BIT_CLKS / 2 - 1) begin
                        clk_count <= 0;

                        if (!rx_sync)
                            state <= DATA;
                        else
                            state <= IDLE; // ��ë�̣�����������ʼλ
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                DATA: begin
                    // ����ʼλ�е��ٵȴ�һλʱ�䣬
                    // �͵����һ������λ���е㡣
                    if (clk_count == BIT_CLKS - 1) begin
                        clk_count <= 0;

                        // UART�ȷ������λ��
                        shift_data[bit_index] <= rx_sync;

                        if (bit_index == 3'd7) begin
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                STOP: begin
                    if (clk_count == BIT_CLKS - 1) begin
                        clk_count <= 0;
                        state     <= IDLE;

                        // ֹͣλ�����Ǹߵ�ƽ��
                        if (rx_sync) begin
                            rx_data  <= shift_data;
                            rx_valid <= 1'b1;
                        end else begin
                            frame_error <= 1'b1;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                default: begin
                    state     <= IDLE;
                    clk_count <= 0;
                end

            endcase
        end
    end

endmodule
