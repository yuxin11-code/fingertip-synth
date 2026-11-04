module instrument_dds_nco (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              sample_enable,
    input  wire [31:0]       phase_step,
    input  wire [1:0]        timbre_select,
    output wire signed [15:0] sample
);

    reg [31:0] phase;
    wire [7:0] rom_address;

    assign rom_address = phase[31:24];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            phase <= 32'd0;
        else if (sample_enable)
            phase <= phase + phase_step;
    end

    instrument_wavetable_bank wavetable_bank (
        .clk           (clk),
        .rst_n         (rst_n),
        .timbre_select (timbre_select),
        .address       (rom_address),
        .sample        (sample)
    );

endmodule