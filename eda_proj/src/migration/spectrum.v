// Real stereo 32-band 63Hz..2kHz analyser (coefficients in spectrum_bins.v).
// Two cascaded biquads per independent logarithmic band; N is publish cadence,
// not an FFT length. Audio input and amplitude mapping are unchanged.
// L/R run in parallel through registered multipliers and a 64x128 sync RAM.
// No ready signal returns to the audio producer. UART can never stall audio.
`default_nettype none
module spectrum #(parameter integer BINS=32,N=256,STEREO=0)(
 input wire clk,rst_n,tick,fast,clk_aud,rst_n_aud,
 input wire signed [15:0] sample,sample_right,input wire frame_strobe,
 output reg [5:0] addr,output reg [11:0] mag,output reg valid,
 output reg [11:0] peak,output wire busy,
 output reg [31:0] overrun_count,output reg [10:0] cycles_last
);
 localparam [3:0] INIT=0,IDLE=1,READ=2,SET_B=3,WAIT_B=4,ACC_B=5,
  WAIT_A1=6,ACC_A1=7,WAIT_A2=8,SUM=9,STORE=10,ENVELOPE=11,LEVEL=12,MAP=13,PUBLISH=14;
 reg [3:0] state;reg [4:0] band;reg section;
 reg [5:0] init_addr;reg [15:0] sample_count;reg publish;
 (* syn_ramstyle="block_ram" *)reg [127:0] filter_mem[0:63];
 (* syn_ramstyle="registers" *)reg [31:0] env_mem[0:31];
 reg [6:0] peak_mem[0:31];reg [5:0] hold_mem[0:31];
 // Display-only falling ballistics, as in Music-Spectrum's per-column RAM.
 // Do not spread energy to unrelated bands or alter the audio producer.
 reg [6:0] display_mem[0:31];
 reg [127:0] filter_q;
 reg [31:0] env_q,env_next;reg [6:0] peak_q;reg [5:0] hold_q;
 reg signed [31:0] y1_l,y1_r,pass_y2_l,pass_y2_r,pass_l,pass_r;
 reg signed [15:0] l1,l2,r1,r2;
 reg signed [28:0] delta_l,delta_r;
 reg signed [32:0] mul_l,mul_r;reg signed [23:0] mul_c;
 (* syn_dspstyle="dsp" *)reg signed [56:0] product_l,product_r;
 reg signed [58:0] accumulator_l,accumulator_r;
 reg [31:0] band_peak;reg [8:0] level_address;wire [6:0] level_q;
 reg [10:0] work_cycles;
 wire [5:0] state_addr={band,section};
 wire signed [23:0] b0,a1,a2;
 spectrum_bins coefficients(.clk(clk),.bin(band),.b0(b0),.a1(a1),.a2(a2));
 spectrum_level_rom level_rom(.clk(clk),.address(level_address),.level(level_q));
 wire signed [58:0] product_ext_l={{2{product_l[56]}},product_l};
 wire signed [58:0] product_ext_r={{2{product_r[56]}},product_r};
 function signed [31:0] saturated(input signed [58:0] a);
  reg signed [58:0] shifted;begin shifted=a>>>22;
   saturated=(shifted>59'sd2147483647)?32'sd2147483647:(shifted< -59'sd2147483648)?32'sh80000000:shifted[31:0];
  end
 endfunction
 wire signed [31:0] filtered_l=saturated(accumulator_l),filtered_r=saturated(accumulator_r);
 wire [31:0] abs_l=filtered_l[31]?(~filtered_l+32'd1):filtered_l;
 wire [31:0] abs_r=filtered_r[31]?(~filtered_r+32'd1):filtered_r;
 wire signed [32:0] env_delta=$signed({1'b0,band_peak})-$signed({1'b0,env_q});
 // Fast attack ~1.3ms; release ~10.3ms at the actual PCM cadence.
 // The former 41ms release plus a separate 0.5s display fall retained the
 // previous note long after a pitch change. Do not hold old spectral energy.
 wire signed [32:0] env_step=env_delta>>>((env_delta>0)?6:9);
 wire signed [32:0] env_increment=(env_delta!=0 && env_step==0)?33'sd1:env_step;
 wire signed [32:0] env_result=$signed({1'b0,env_q})+env_increment;
 function [8:0] level_index(input [31:0] envelope);
  integer k,j;reg [31:0] normalised;begin
   k=0;for(j=0;j<32;j=j+1)if(envelope[j])k=j;
   normalised=(k>=4)?(envelope>>(k-4)):(envelope<<(4-k));
   level_index={k[4:0],normalised[3:0]};
  end
 endfunction
 wire [6:0] peak_next=(level_q>=peak_q)?level_q:(hold_q!=0)?peak_q:((peak_q>level_q)?peak_q-7'd1:level_q);
 wire [5:0] hold_next=(level_q>=peak_q)?6'd30:(hold_q!=0)?hold_q-6'd1:6'd0;
 // Instant rise; fall by at most four percentage points per 256-sample
 // publication (~5.15ms). Clamp at the measured level and at zero: do not
 // create phantom peaks, undershoot real energy or wrap unsigned subtraction.
 wire [6:0] display_previous=display_mem[band];
 wire [6:0] display_floor=(display_previous>7'd4)?display_previous-7'd4:7'd0;
 wire [6:0] display_next=(level_q>=display_floor)?level_q:display_floor;
 assign busy=(state!=IDLE && state!=INIT);
 always @(posedge clk)begin
  product_l<=mul_l*mul_c;product_r<=mul_r*mul_c;
  if(rst_n)begin
   if(state==INIT)filter_mem[init_addr]<=0;
   else if(state==READ)filter_q<=filter_mem[state_addr];
   else if(state==STORE)filter_mem[state_addr]<={filtered_l,y1_l,filtered_r,y1_r};
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=INIT;init_addr<=0;band<=0;section<=0;sample_count<=0;publish<=0;
   addr<=0;mag<=0;peak<=0;valid<=0;overrun_count<=0;cycles_last<=0;work_cycles<=0;
   l1<=0;l2<=0;r1<=0;r2<=0;delta_l<=0;delta_r<=0;mul_l<=0;mul_r<=0;mul_c<=0;
   accumulator_l<=0;accumulator_r<=0;y1_l<=0;y1_r<=0;pass_y2_l<=0;pass_y2_r<=0;
   pass_l<=0;pass_r<=0;band_peak<=0;env_q<=0;env_next<=0;peak_q<=0;hold_q<=0;level_address<=0;
  end else begin
   valid<=0;
   if(busy)work_cycles<=work_cycles+1'b1;
   if(tick && busy)overrun_count<=overrun_count+1'b1;
   case(state)
    INIT:begin
     if(init_addr<32)begin env_mem[init_addr[4:0]]<=0;peak_mem[init_addr[4:0]]<=0;hold_mem[init_addr[4:0]]<=0;display_mem[init_addr[4:0]]<=0;end
     if(init_addr==63)state<=IDLE;else init_addr<=init_addr+1'b1;
    end
    IDLE:if(tick)begin
     delta_l<=($signed({sample[15],sample})-$signed({l2[15],l2}))<<<12;
     delta_r<=STEREO?($signed({sample_right[15],sample_right})-$signed({r2[15],r2}))<<<12:
                      ($signed({sample[15],sample})-$signed({r2[15],r2}))<<<12;
     l2<=l1;l1<=sample;r2<=r1;r1<=STEREO?sample_right:sample;
     band<=0;section<=0;work_cycles<=1;
     publish<=(sample_count==N-1);sample_count<=(sample_count==N-1)?16'd0:sample_count+16'd1;state<=READ;
    end
    READ:begin env_q<=env_mem[band];peak_q<=peak_mem[band];hold_q<=hold_mem[band];state<=SET_B;end
    SET_B:begin
     y1_l<=filter_q[127:96];y1_r<=filter_q[63:32];
     mul_l<=section?($signed({pass_l[31],pass_l})-$signed({pass_y2_l[31],pass_y2_l})):{{4{delta_l[28]}},delta_l};
     mul_r<=section?($signed({pass_r[31],pass_r})-$signed({pass_y2_r[31],pass_y2_r})):{{4{delta_r[28]}},delta_r};
     mul_c<=b0;state<=WAIT_B;
     if(!section)begin pass_y2_l<=filter_q[95:64];pass_y2_r<=filter_q[31:0];end
    end
    WAIT_B:state<=ACC_B;
    ACC_B:begin accumulator_l<=product_ext_l;accumulator_r<=product_ext_r;mul_l<={filter_q[127],filter_q[127:96]};mul_r<={filter_q[63],filter_q[63:32]};mul_c<=a1;state<=WAIT_A1;end
    WAIT_A1:state<=ACC_A1;
    ACC_A1:begin accumulator_l<=accumulator_l-product_ext_l;accumulator_r<=accumulator_r-product_ext_r;mul_l<={filter_q[95],filter_q[95:64]};mul_r<={filter_q[31],filter_q[31:0]};mul_c<=a2;state<=WAIT_A2;end
    WAIT_A2:state<=SUM;
    SUM:begin accumulator_l<=accumulator_l-product_ext_l;accumulator_r<=accumulator_r-product_ext_r;state<=STORE;end
    STORE:begin
     if(!section)begin pass_l<=filtered_l;pass_r<=filtered_r;section<=1;state<=READ;end
     else begin band_peak<=(abs_l>abs_r)?abs_l:abs_r;state<=ENVELOPE;end
    end
    ENVELOPE:begin env_next<=env_result[32]?32'd0:env_result[31:0];state<=LEVEL;end
    LEVEL:begin env_mem[band]<=env_next;level_address<=level_index(env_next);state<=MAP;end
    MAP:state<=PUBLISH;
    PUBLISH:begin
     if(publish)begin addr<={1'b0,band};mag<={5'd0,display_next};display_mem[band]<=display_next;peak<={5'd0,peak_next};valid<=1;peak_mem[band]<=peak_next;hold_mem[band]<=hold_next;end
     if(band==31)begin state<=IDLE;cycles_last<=work_cycles;end
     else begin band<=band+1'b1;section<=0;state<=READ;end
    end
    default:state<=INIT;
   endcase
  end
 end
 wire _unused=fast^clk_aud^rst_n_aud^frame_strobe^(BINS==32);
endmodule
`default_nettype wire
