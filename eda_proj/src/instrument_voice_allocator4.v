module instrument_voice_allocator4 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] touch_keys,
    output wire [3:0]  voice_gate,
    output wire [6:0]  voice0_note,
    output wire [6:0]  voice1_note,
    output wire [6:0]  voice2_note,
    output wire [6:0]  voice3_note
);
    reg active0, active1, active2, active3;
    reg [3:0] key0, key1, key2, key3;
    reg next_active0, next_active1, next_active2, next_active3;
    reg [3:0] next_key0, next_key1, next_key2, next_key3;
    reg [15:0] assigned_keys;
    integer i;

    function [6:0] key_to_note;
        input [3:0] key_index;
        begin
            case (key_index)
                4'd0: key_to_note=7'd60; 4'd1: key_to_note=7'd62;
                4'd2: key_to_note=7'd64; 4'd3: key_to_note=7'd65;
                4'd4: key_to_note=7'd67; 4'd5: key_to_note=7'd69;
                4'd6: key_to_note=7'd71; 4'd7: key_to_note=7'd72;
                4'd8: key_to_note=7'd74; 4'd9: key_to_note=7'd76;
                4'd10:key_to_note=7'd77; 4'd11:key_to_note=7'd79;
                4'd12:key_to_note=7'd81; 4'd13:key_to_note=7'd83;
                4'd14:key_to_note=7'd84; 4'd15:key_to_note=7'd86;
                default:key_to_note=7'd60;
            endcase
        end
    endfunction

    assign voice_gate={active3,active2,active1,active0};
    assign voice0_note=key_to_note(key0);
    assign voice1_note=key_to_note(key1);
    assign voice2_note=key_to_note(key2);
    assign voice3_note=key_to_note(key3);

    always @* begin
        next_active0=active0; next_active1=active1;
        next_active2=active2; next_active3=active3;
        next_key0=key0; next_key1=key1; next_key2=key2; next_key3=key3;
        if(active0 && !touch_keys[key0]) next_active0=1'b0;
        if(active1 && !touch_keys[key1]) next_active1=1'b0;
        if(active2 && !touch_keys[key2]) next_active2=1'b0;
        if(active3 && !touch_keys[key3]) next_active3=1'b0;
        assigned_keys=16'd0;
        if(next_active0) assigned_keys[next_key0]=1'b1;
        if(next_active1) assigned_keys[next_key1]=1'b1;
        if(next_active2) assigned_keys[next_key2]=1'b1;
        if(next_active3) assigned_keys[next_key3]=1'b1;
        for(i=0;i<16;i=i+1) begin
            if(touch_keys[i] && !assigned_keys[i]) begin
                if(!next_active0) begin next_active0=1'b1; next_key0=i; assigned_keys[i]=1'b1; end
                else if(!next_active1) begin next_active1=1'b1; next_key1=i; assigned_keys[i]=1'b1; end
                else if(!next_active2) begin next_active2=1'b1; next_key2=i; assigned_keys[i]=1'b1; end
                else if(!next_active3) begin next_active3=1'b1; next_key3=i; assigned_keys[i]=1'b1; end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            active0<=0; active1<=0; active2<=0; active3<=0;
            key0<=0; key1<=0; key2<=0; key3<=0;
        end else begin
            active0<=next_active0; active1<=next_active1;
            active2<=next_active2; active3<=next_active3;
            key0<=next_key0; key1<=next_key1; key2<=next_key2; key3<=next_key3;
        end
    end
endmodule
