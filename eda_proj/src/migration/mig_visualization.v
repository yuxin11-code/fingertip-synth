// Read-only observations in clk_sys; no signal returns to the audio datapath.
module mig_visualization # (parameter integer CLK_HZ=52500000,REAL_ADSR=0,SPECTRUM_ENABLE=1)(
 input wire clk,rst_n,frame_tick,input wire [3:0] page,
 input wire signed [15:0] pcm_left,pcm_right,
 input wire signed [39:0] panel_a,panel_b,
 input wire [19:0] env_observe,input wire [3:0] a,d,s,r,
 input wire cmd_valid,input wire [7:0] cmd,input wire [15:0] value,
 output wire aux_valid,aux_last,aux_frame_end,output wire [7:0] aux_data,input wire aux_ready,
 output reg liss_mode);
 reg [1:0] decim;
 reg signed [15:0] a_q,b_q,left_q,right_q;
 function signed [15:0] panel_sample;input signed [39:0] sample;reg signed [39:0] v;begin
  v=sample>>>4;panel_sample=(v>32767)?16'sd32767:(v< -32768)?-16'sd32768:v[15:0];
 end endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin decim<=0;liss_mode<=0;a_q<=0;b_q<=0;left_q<=0;right_q<=0;end
  else begin
   a_q<=panel_sample(panel_a);b_q<=panel_sample(panel_b);left_q<=pcm_left;right_q<=pcm_right;
   if(cmd_valid && cmd==8'h40)decim<=value[1:0];
   if(cmd_valid && cmd==8'h41)liss_mode<=value[0];
  end
 end
 wire wave_ready,adsr_ready,liss_ready,wbank,abank,lbank;
 wire wave_rd,adsr_rd,liss_rd,wvalid,avalid,lvalid;
  wire [7:0] caddr,wdata,adata,laddr;
 wire [15:0] lx,ly;wire wcons,acons,lcons,dot_valid;
  viz_capture #(.LEGACY_PACKED(0),.LISS_POINTS(128),.FS_TICKS(993),.REAL_ADSR(REAL_ADSR)) capture(
  .clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.sample_valid(1'b1),
  .wave_sample(left_q),.dry_sample(left_q),.wet_sample(right_q),.voice_a_sample(a_q),.voice_b_sample(b_q),
  .wave_decim(decim),.wave_arm(page==2 || page==0),.wave_consumed(wcons),
  .liss_arm(page==4),.liss_mode_a(!liss_mode),.liss_voice_count(2'd2),.liss_consumed(lcons),.liss_ready(liss_ready),
  .adsr_arm(page==5),.adsr_consumed(acons),.adsr_a(a),.adsr_d(d),.adsr_s(s),.adsr_r(r),
  .env_value(env_observe[16:0]),.env_stage(env_observe[19:17]),
  .wave_ready(wave_ready),.wave_data(),.wave_mem_rd_en(wave_rd),.wave_mem_rd_addr(caddr),.wave_mem_rd_data(wdata),.wave_mem_rd_valid(wvalid),.wave_mem_bank(wbank),
  .liss_valid(),.liss_index(),.liss_x(),.liss_y(),.liss_done(),.liss_mem_rd_en(liss_rd),.liss_mem_rd_addr(laddr),.liss_mem_rd_x(lx),.liss_mem_rd_y(ly),.liss_mem_rd_valid(lvalid),.liss_mem_bank(lbank),
  .adsr_ready(adsr_ready),.adsr_data(),.adsr_mem_rd_en(adsr_rd),.adsr_mem_rd_addr(caddr),.adsr_mem_rd_data(adata),.adsr_mem_rd_valid(avalid),.adsr_mem_bank(abank),
  .adsr_point_valid(dot_valid),.adsr_point_x(),.adsr_point_y(),.adsr_point_stage());
 wire [5:0] spec_addr;wire [11:0] spec_mag,spec_peak;wire spec_valid;
 // Analysis is observation only: enable/disable never reaches audio control.
 spectrum #(.BINS(32),.N(256),.STEREO(1)) analyser(.clk(clk),.rst_n(rst_n),.tick(frame_tick && SPECTRUM_ENABLE),.sample(left_q),.sample_right(right_q),.fast(1'b0),.clk_aud(clk),.rst_n_aud(rst_n),.frame_strobe(frame_tick),.addr(spec_addr),.mag(spec_mag),.peak(spec_peak),.valid(spec_valid));
 hmi_viz_tx #(.CLK_HZ(CLK_HZ)) sender(.clk(clk),.rst_n(rst_n),.page(page),
  .wave_ready(wave_ready),.wave_bank(wbank),.adsr_ready(adsr_ready),.adsr_bank(abank),.liss_ready(liss_ready),.liss_bank(lbank),
  .wave_data(wdata),.adsr_data(adata),.wave_valid(wvalid),.adsr_valid(avalid),.liss_x(lx),.liss_y(ly),.liss_valid(lvalid),
  .wave_rd(wave_rd),.adsr_rd(adsr_rd),.liss_rd(liss_rd),.curve_addr(caddr),.liss_addr(laddr),
  .wave_consumed(wcons),.adsr_consumed(acons),.liss_consumed(lcons),.spec_valid(spec_valid),.spec_addr(spec_addr),.spec_mag(spec_mag),.spec_peak(spec_peak),
  .dot_valid(dot_valid),.env_observe(env_observe),.valid(aux_valid),.last(aux_last),.frame_end(aux_frame_end),.data(aux_data),.ready(aux_ready));
endmodule

// Read-only measurements; a shared iterative divider keeps timing predictable.
module hmi_scope_metrics #(parameter integer CLK_HZ=52500000)(
 input wire clk,rst_n,tick,input wire signed [15:0] sample,
 output reg [31:0] frequency,output reg [15:0] peak);
 reg [31:0] period,period_q;
 reg [15:0] maximum;
 reg [6:0] samples;
 reg negative,start;
 wire [15:0] magnitude=sample[15]?-sample:sample;
 wire busy,done;wire [35:0] quotient;
 localparam [35:0] CLOCKS_PER_SECOND=CLK_HZ;
 serial_divider divide(.clk(clk),.rst_n(rst_n),.start(start),.numerator(CLOCKS_PER_SECOND),.denominator({4'd0,period_q}),.busy(busy),.done(done),.quotient(quotient));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin frequency<=0;peak<=0;period<=0;period_q<=1;maximum<=0;samples<=0;negative<=0;start<=0;end
  else begin
   start<=0;
   if(period<CLK_HZ)period<=period+1'b1;else frequency<=0;
   if(done)frequency<=quotient[31:0];
   if(tick)begin
    if(sample< -16'sd32)negative<=1;
    if(negative && sample>16'sd32)begin
     negative<=0;
     if(!busy && period>CLK_HZ/24000)begin period_q<=period;start<=1;end
     period<=0;
    end
    if(magnitude>maximum)maximum<=magnitude;
    samples<=samples+1'b1;
    if(samples==127)begin peak<=(magnitude>maximum)?magnitude:maximum;maximum<=0;end
   end
  end
 end
endmodule
