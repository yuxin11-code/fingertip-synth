// Logical controls only. No device address, register map or I2C pins assumed.
// write_mask[0..4]: master, panel blend, stereo balance, vibrato depth/rate.
// Each packed value is unsigned 17-bit 0..65536; values above full are clamped.
// Future driver must normalize physical readings and pulse mask in clk domain.
module mig_five_knobs(
 input wire clk,rst_n,frame_tick,
 input wire [4:0] write_mask,
 input wire [84:0] write_values,
 input wire [16:0] fallback_volume,
 input wire [17:0] base_pitch,
 output wire [16:0] master,blend,balance,
 output wire [17:0] modulated_pitch
);
 reg [16:0] target[0:4],value[0:4];
 reg master_seen;
 reg [31:0] phase;
 integer i;
 function [16:0] slew;
 input [16:0] current,wanted;
 begin
  if(wanted>current) slew=(wanted-current>256)?current+17'd256:wanted;
  else slew=(current-wanted>256)?current-17'd256:wanted;
 end endfunction
 wire [16:0] master_target=master_seen?target[0]:fallback_volume;
 assign master=value[0]; assign blend=value[1]; assign balance=value[2];
 // 0.5 .. 10 Hz at 49,667.358398 frames/s; triangle LFO.
 wire [36:0] rate_product=value[4]*20'd821523;
 wire [31:0] phase_step=32'd43238+rate_product[36:16];
 wire signed [17:0] triangle=phase[31] ?
   (18'sd32767-$signed({2'b00,phase[30:15]})) :
   ($signed({2'b00,phase[30:15]})-18'sd32768);
 // Maximum +/-3% pitch factor; zero depth is bit-exact bypass.
 wire [27:0] depth_product=value[3]*11'd1966;
 wire signed [12:0] depth=$signed({1'b0,depth_product[27:16]});
 wire signed [30:0] excursion=triangle*depth;
 wire signed [31:0] factor=32'sd65536+(excursion>>>15);
 wire [49:0] pitch_product=base_pitch*$unsigned(factor);
 wire [33:0] pitched=pitch_product[49:16];
 assign modulated_pitch=(pitched>262143)?18'd262143:pitched[17:0];
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   master_seen<=0; phase<=0;
   for(i=0;i<5;i=i+1) begin
    target[i]<=(i==3)?17'd0:17'd32768;
    value[i]<=(i==3)?17'd0:17'd32768;
   end
  end else begin
   for(i=0;i<5;i=i+1) if(write_mask[i])
    target[i]<=(write_values[i*17+:17]>65536)?17'd65536:write_values[i*17+:17];
   if(write_mask[0]) master_seen<=1;
   if(frame_tick) begin
    value[0]<=slew(value[0],master_target);
    for(i=1;i<5;i=i+1) value[i]<=slew(value[i],target[i]);
    phase<=phase+phase_step;
   end
  end
 end
endmodule
