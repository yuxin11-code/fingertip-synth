// One independent octave register per panel. Existing ADSR encoder is separate.
module mig_octave_control #(
    parameter integer CLK_HZ=52500000,
    parameter integer T_MIN=-4,
    parameter integer T_MAX=4
)(
    input wire clk,rst_n,enc_a,enc_b,enc_sw_n,
    input wire hmi_valid,input wire [7:0] hmi_cmd,input wire [15:0] hmi_value,
    output reg selected_panel,
    output reg signed [7:0] transpose_left,transpose_right
);
    wire cw,ccw,select_press;
    rotary_encoder_decoder #(.CLK_HZ(CLK_HZ)) decoder(
        .clk(clk),.rst_n(rst_n),.enc_a(enc_a),.enc_b(enc_b),
        .enc_key_n(enc_sw_n),.rotate_cw(cw),.rotate_ccw(ccw),
        .select_pulse(select_press));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            selected_panel<=0; transpose_left<=0; transpose_right<=0;
        end else begin
            if(hmi_valid && hmi_cmd==8'h15) selected_panel<=(hmi_value!=0);
            else if(select_press) selected_panel<=~selected_panel;
            // Selection wins a simultaneous press/detent: no ambiguous move.
            else if(!selected_panel) begin
                if(cw && $signed(transpose_left)<T_MAX) transpose_left<=transpose_left+8'sd1;
                else if(ccw && $signed(transpose_left)>T_MIN) transpose_left<=transpose_left-8'sd1;
            end else begin
                if(cw && $signed(transpose_right)<T_MAX) transpose_right<=transpose_right+8'sd1;
                else if(ccw && $signed(transpose_right)>T_MIN) transpose_right<=transpose_right-8'sd1;
            end
            if(hmi_valid && hmi_cmd==8'h03)
                transpose_left<=($signed(hmi_value)<T_MIN)?T_MIN:($signed(hmi_value)>T_MAX)?T_MAX:hmi_value[7:0];
            if(hmi_valid && hmi_cmd==8'h04)
                transpose_right<=($signed(hmi_value)<T_MIN)?T_MIN:($signed(hmi_value)>T_MAX)?T_MAX:hmi_value[7:0];
        end
    end
endmodule
