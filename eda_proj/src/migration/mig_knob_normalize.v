// Vendor examples define 16-bit transport, but not the physical ADC span.
// RAW_MAX=0 learns endpoints per channel; sweep each pot to both stops once.
// A shared restoring divider avoids eight large combinational dividers.
module mig_knob_normalize #(parameter integer RAW_MIN=0,RAW_MAX=0,MIN_SPAN=32,
 parameter [5:0] REVERSE_MASK=6'b0)(
 input wire clk,rst_n,snapshot_valid,input wire [127:0] raw_values,
 output reg [5:0] write_mask,output reg [101:0] write_values,
 output wire [95:0] calibration_low,calibration_high);
 reg [15:0] lo[0:5],hi[0:5];reg [5:0] seen;
 reg [127:0] snapshot;
 reg [2:0] ch;reg [1:0] st;
 reg [15:0] denom;reg [16:0] remn;
 reg [31:0] quotient;reg [5:0] count;
 reg [101:0] staging;reg [5:0] valid_bits;
 wire [15:0] raw=snapshot[ch*16+:16];
 wire [15:0] low=(RAW_MAX>RAW_MIN)?RAW_MIN:(!seen[ch] || raw<lo[ch]?raw:lo[ch]);
 wire [15:0] high=(RAW_MAX>RAW_MIN)?RAW_MAX:(!seen[ch] || raw>hi[ch]?raw:hi[ch]);
 wire [15:0] delta=raw-low;
 wire [16:0] trial={remn[15:0],quotient[31]};
 integer i;
 genvar g;
 generate for(g=0;g<6;g=g+1)begin: calibration_export
  assign calibration_low[g*16+:16]=lo[g];
  assign calibration_high[g*16+:16]=hi[g];
 end endgenerate
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin st<=0;ch<=0;seen<=0;staging<=0;write_mask<=0;write_values<=0;snapshot<=0;denom<=0;remn<=0;quotient<=0;count<=0;valid_bits<=0;
   for(i=0;i<6;i=i+1)begin lo[i]<=0;hi[i]<=0;end
  end else begin
   write_mask<=0;
   case(st)
    0:if(snapshot_valid)begin snapshot<=raw_values;ch<=0;valid_bits<=0;st<=1;end
    1:begin
     seen[ch]<=1;lo[ch]<=low;hi[ch]<=high;
     if(high-low>=MIN_SPAN)begin
      valid_bits[ch]<=1;
      if(raw>=high)begin staging[ch*17+:17]<=17'd65536;st<=3;end
      else if(raw<=low)begin staging[ch*17+:17]<=0;st<=3;end
      else begin denom<=high-low;quotient<={delta,16'd0};remn<=0;count<=0;st<=2;end
     end else st<=3;
    end
    2:begin
     if(trial>={1'b0,denom})begin remn<=trial-denom;quotient<={quotient[30:0],1'b1};end
     else begin remn<=trial;quotient<={quotient[30:0],1'b0};end
     if(count==31)begin
      staging[ch*17+:17]<={quotient[15:0],(trial>={1'b0,denom})};st<=3;
     end else count<=count+1;
    end
    3:begin
      // Endpoint orientation can be reversed independently after bench check.
      if(ch==5)begin
       for(i=0;i<6;i=i+1)write_values[i*17+:17]<=REVERSE_MASK[i]?17'd65536-staging[i*17+:17]:staging[i*17+:17];
       write_mask<=valid_bits;st<=0;
      end else begin ch<=ch+1;st<=1;end
    end
   endcase
  end
 end
endmodule
