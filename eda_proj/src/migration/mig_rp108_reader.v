// RP108: local vendor Arduino/Pico sources, address 0x20, 0x50+2*n,
// two-byte little-endian values; strict ID 01 02 at register FB.
// Independent open-drain bus, never writes device configuration.
module mig_rp108_reader #(
 parameter integer CLK_HZ=52500000,I2C_HZ=40000,GAP_MS=1,
 parameter [6:0] ADDRESS=7'h20
)(input wire clk,rst_n,inout wire scl,sda,
 output reg [127:0] raw_values,output reg snapshot_valid,
 output reg online,output reg [15:0] error_count);
 localparam integer HALF=(CLK_HZ/(2*I2C_HZ)<2)?2:CLK_HZ/(2*I2C_HZ);
 localparam integer TIMEOUT=CLK_HZ/50;
 reg dl_scl,dl_sda;
 assign scl=dl_scl?1'b0:1'bz;
 assign sda=dl_sda?1'b0:1'bz;
 reg [1:0] scl_sync,sda_sync;
 always @(posedge clk) begin scl_sync<={scl_sync[0],scl};sda_sync<={sda_sync[0],sda};end
 reg [5:0] st;
 reg [31:0] div_count,timeout_count,gap;
 reg [7:0] tx,reg_addr;
 reg [2:0] bitno,channel;
 reg [1:0] tx_stage;
 reg rx_high,id_read;
 reg [15:0] rx;
 reg [127:0] staging;
 localparam IDLE=0,START=1,START_LOW=2,TX_SET=3,TX_HIGH=4,TX_LOW=5,
 ACK_SET=6,ACK_HIGH=7,ACK_GET=8,ACK_LOW=9,RS_REL=10,RS_HIGH=11,RS_START=12,
 RS_LOW=13,RX_SET=14,RX_HIGH=15,RX_GET=16,RX_LOW=17,
 MA_SET=18,MA_HIGH=19,MA_LOW=20,STOP_LOW=21,STOP_HIGH=22,STOP_REL=23,COMMIT=24;
 wire stretch_wait=((st==START || st==TX_LOW || st==ACK_GET || st==RS_START ||
 st==RX_GET || st==MA_LOW || st==STOP_REL) && !scl_sync[1]);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   st<=IDLE;dl_scl<=0;dl_sda<=0;div_count<=0;timeout_count<=0;gap<=CLK_HZ/10;
   online<=0;error_count<=0;raw_values<=0;staging<=0;snapshot_valid<=0;
   tx<=0;reg_addr<=8'hfb;bitno<=7;channel<=0;tx_stage<=0;rx_high<=0;id_read<=1;rx<=0;
  end else begin
   snapshot_valid<=0;
   if(st==IDLE) begin
    div_count<=0;timeout_count<=0;dl_scl<=0;dl_sda<=0;
    if(gap!=0) gap<=gap-1;
    else if(scl_sync[1] && sda_sync[1]) begin
     reg_addr<=id_read?8'hfb:(8'h50+{4'd0,channel,1'b0});
     tx<={ADDRESS,1'b0};tx_stage<=0;bitno<=7;rx<=0;rx_high<=0;st<=START;
    end else begin
     timeout_count<=timeout_count+1;
     if(timeout_count>=TIMEOUT)begin
      online<=0;id_read<=1;channel<=0;timeout_count<=0;gap<=CLK_HZ/10;
      if(error_count!=65535)error_count<=error_count+1'b1;
     end
    end
   end else if(timeout_count>=TIMEOUT) begin
    dl_scl<=0;dl_sda<=0;st<=IDLE;gap<=CLK_HZ/10;id_read<=1;online<=0;
    if(error_count!=65535)error_count<=error_count+1'b1;
   end else begin
    timeout_count<=timeout_count+1;
    if(div_count<HALF-1) div_count<=div_count+1;
    else if(!stretch_wait) begin
     div_count<=0;
     case(st)
      START:begin dl_sda<=1;st<=START_LOW;end
      START_LOW:begin dl_scl<=1;st<=TX_SET;end
      TX_SET:begin dl_sda<=!tx[bitno];st<=TX_HIGH;end
      TX_HIGH:begin dl_scl<=0;st<=TX_LOW;end
      TX_LOW:begin dl_scl<=1;if(bitno==0)st<=ACK_SET;else begin bitno<=bitno-1;st<=TX_SET;end end
      ACK_SET:begin dl_sda<=0;st<=ACK_HIGH;end
      ACK_HIGH:begin dl_scl<=0;st<=ACK_GET;end
      ACK_GET:begin
       dl_scl<=1;
       if(sda_sync[1])begin online<=0;id_read<=1;channel<=0;st<=STOP_LOW;
        if(error_count!=65535)error_count<=error_count+1'b1;end
       else st<=ACK_LOW;
      end
      ACK_LOW:begin
       bitno<=7;
       if(tx_stage==0)begin tx<=reg_addr;tx_stage<=1;st<=TX_SET;end
       else if(tx_stage==1)st<=RS_REL;
       else st<=RX_SET;
      end
      RS_REL:begin dl_sda<=0;st<=RS_HIGH;end
      RS_HIGH:begin dl_scl<=0;st<=RS_START;end
      RS_START:begin dl_sda<=1;st<=RS_LOW;end
      RS_LOW:begin dl_scl<=1;tx<={ADDRESS,1'b1};tx_stage<=2;bitno<=7;st<=TX_SET;end
      RX_SET:begin dl_sda<=0;st<=RX_HIGH;end
      RX_HIGH:begin dl_scl<=0;st<=RX_GET;end
      RX_GET:begin rx[(rx_high?8:0)+bitno]<=sda_sync[1];dl_scl<=1;st<=RX_LOW;end
      RX_LOW:begin if(bitno==0)st<=MA_SET;else begin bitno<=bitno-1;st<=RX_SET;end end
      MA_SET:begin dl_sda<=!rx_high;st<=MA_HIGH;end // ACK low byte, NACK high byte
      MA_HIGH:begin dl_scl<=0;st<=MA_LOW;end
      MA_LOW:begin dl_scl<=1;dl_sda<=0;
       if(rx_high)st<=STOP_LOW;else begin rx_high<=1;bitno<=7;st<=RX_SET;end
      end
      STOP_LOW:begin dl_scl<=1;dl_sda<=1;st<=STOP_HIGH;end
      STOP_HIGH:begin dl_scl<=0;st<=STOP_REL;end
      STOP_REL:begin dl_sda<=0;st<=COMMIT;end
      COMMIT:begin
       gap<=(CLK_HZ/1000)*GAP_MS;st<=IDLE;
       // NACK resets id_read and online; only complete acknowledged transfers commit.
       if(tx_stage==2 && rx_high)begin
        if(id_read)begin
         if(rx==16'h0201)begin online<=1;id_read<=0;channel<=0;end
         else begin online<=0;gap<=CLK_HZ/10;if(error_count!=65535)error_count<=error_count+1'b1;end
        end else if(online)begin
         staging[channel*16+:16]<=rx;
         if(channel==7)begin raw_values<={rx,staging[111:0]};snapshot_valid<=1;channel<=0;end
         else channel<=channel+1;
        end
       end
      end
      default:begin st<=IDLE;id_read<=1;online<=0;end
     endcase
    end
   end
  end
 end
endmodule
