`timescale 1ns/1ps
module tb_curve_native_transport #(parameter integer CLK_HZ=1843200);
 `define HMI_DEFINE_TX_TABLE
 `include "hmi_defs.vh"
 `undef HMI_DEFINE_TX_TABLE
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg cv=0;reg[7:0] cmd=0;reg[15:0] value=0;
 wire[3:0] page;wire tx,av,al,afe,ar;wire[7:0] ad;
 reg[HMI_TX_FIELD_COUNT*32-1:0] fields=0;
 wire rd,cons;wire[7:0] addr;
 reg lr=0,lv=0;reg[15:0] lx=0,ly=0;
 reg sv=0;reg[5:0] sa=0;reg[11:0] sm=0;
 hmi_tx #(.CLK_HZ(CLK_HZ),.FIELD_COUNT(HMI_TX_FIELD_COUNT),.LINK_DIAGNOSTICS(1)) txer(
  .clk(clk),.rst_n(rst_n),.cmd_valid(cv),.cmd(cmd),.value(value),.fields(fields),
  .page_valid(1'b0),.page_id(16'd0),.screen_reset(1'b0),.current_page(page),.tx(tx),
  .aux_valid(av),.aux_last(al),.aux_frame_end(afe),.aux_data(ad),.aux_ready(ar),.byte_count());
 hmi_viz_tx #(.CLK_HZ(CLK_HZ)) dut(.clk(clk),.rst_n(rst_n),.page(page),
  .wave_ready(1'b0),.wave_bank(1'b0),.adsr_ready(1'b0),.adsr_bank(1'b0),
  .liss_ready(lr),.liss_bank(1'b0),.wave_data(8'd0),.adsr_data(8'd0),
  .wave_valid(1'b0),.adsr_valid(1'b0),.liss_x(lx),.liss_y(ly),.liss_valid(lv),
  .wave_rd(),.adsr_rd(),.liss_rd(rd),.curve_addr(),.liss_addr(addr),
  .wave_consumed(),.adsr_consumed(),.liss_consumed(cons),
  .spec_valid(sv),.spec_addr(sa),.spec_mag(sm),.spec_peak(12'd0),
  .dot_valid(1'b0),.env_observe(20'd0),.valid(av),.last(al),.frame_end(afe),.data(ad),.ready(ar));
 always @(posedge clk)begin
  lv<=rd;
  if(rd)begin lx<=24+addr*3;ly<=64+(addr*7)%155;end
  if(!rst_n)lr<=0;else if(cons)lr<=0;else if(page==4)lr<=1;
 end
 wire[7:0] bd;wire bv,fe;
 hmi_uart_rx #(.CLK_HZ(CLK_HZ)) rx(.clk(clk),.rst_n(rst_n),.rx(tx),.data(bd),.valid(bv),.frame_error(fe));
 reg[7:0] p[0:255];reg[31:0] tail=0;
 integer n=0,cycle=0,frames=0,chunk=0,next_point=0,lines=0,bytes_frame=0,first_start=0,last_start=0;
 integer frame_start=0,restores=0,restores3=0,sweeps=0,next_bar=101,mode_echo=0,change_cycle=0;
 integer fd,td,i,x,y,expected,gen,off,wire_start=0,control_deadline=0;
 real interval_ms;
 initial begin fd=$fopen("uart.bin","wb");td=$fopen("uart_timestamps.csv","w");end
 always @(negedge clk)begin
  cycle=cycle+1;
  if(page!=3)next_bar=101;
  sv=0;off=cycle%(CLK_HZ/194);gen=cycle/(CLK_HZ/194);
  if(page==3 && off<704 && off%22==0)begin sv=1;sa=off/22;sm=20+sa;end
  if(av && ar && dut.pos==0 && dut.native_draw && dut.op==8'h50)wire_start=cycle;
  if(fe)$fatal(1,"UART framing error");
  if(bv)begin
   $fwrite(fd,"%c",bd);$fwrite(td,"%0d,%0d\n",cycle,bd);
   p[n]=bd;n=n+1;tail={tail[23:0],bd};
   if(n>254)$fatal(1,"manufacturer packet limit exceeded");
   if(tail==32'hcc33c33c)begin
    if(p[0]!=8'haa)$fatal(1,"bad header");
    if(p[1]==8'h50)begin
     if(n!=10 || p[2]!=8'h26 || p[3]!=8'hdd || p[4]!=8'h08 || p[5]!=8'he5)$fatal(1,"RGB565 format");
     bytes_frame=n;chunk=0;next_point=0;lines=0;frame_start=wire_start;
     if(last_start)begin
      interval_ms=1000.0*(frame_start-last_start)/CLK_HZ;
      if(interval_ms<66.60)$fatal(1,"XY frame limiter interval=%f",interval_ms);
      $display("METRIC liss_interval_ms=%0.6f fps=%0.6f",interval_ms,1000.0/interval_ms);
     end
     last_start=frame_start;
    end else if(p[1]==8'h6a)begin
     if(n!=14 || {p[2],p[3]}!=24 || {p[4],p[5]}!=64 || {p[6],p[7]}!=452 || {p[8],p[9]}!=218)$fatal(1,"clear outside plot");
     bytes_frame=bytes_frame+n;
    end else if(p[1]==8'h66)begin
     if(n!=((chunk<2)?246:46))$fatal(1,"polyline packet length chunk=%0d bytes=%0d",chunk,n);
     for(i=2;i<n-4;i=i+4)begin
      expected=next_point;x={p[i],p[i+1]};y={p[i+2],p[i+3]};
      if(x!=24+expected*3 || y!=64+(expected*7)%155)$fatal(1,"XY point/bank/order %0d got %0d,%0d",expected,x,y);
      if(i>2)lines=lines+1;
      next_point=next_point+1;
     end
     bytes_frame=bytes_frame+n;chunk=chunk+1;
     if(next_point==128)begin
      if(lines!=127 || bytes_frame!=562 || chunk!=3)$fatal(1,"broken/duplicated polyline segments");
      frames=frames+1;
      $display("METRIC XY_frame=%0d bytes=%0d segments=%0d wire_ms=%0.6f",frames,bytes_frame,lines,1000.0*(cycle-frame_start)/CLK_HZ);
     end else next_point=next_point-1;
    end else if(p[1]==8'hb1)begin
     if(p[2]==8'h00 && {p[3],p[4]}==2)restores=restores+1;
     if(p[2]==8'h00 && {p[3],p[4]}==3)restores3=restores3+1;
     if(p[2]==8'h28 && {p[3],p[4]}==4)$fatal(1,"old moving-dot substitute remains");
     if(p[2]==8'h10 && {p[3],p[4]}==4 && {p[5],p[6]}==65 && p[7]==1)begin
      mode_echo=mode_echo+1;
      if(change_cycle)begin
       if(cycle-change_cycle>CLK_HZ/10)$fatal(1,"control starvation");
       $display("METRIC control_echo_ms=%0.6f",1000.0*(cycle-change_cycle)/CLK_HZ);
       change_cycle=0;
      end
     end
     if(page==3 && p[2]==8'h10 && {p[3],p[4]}==3 && {p[5],p[6]}>=101 && {p[5],p[6]}<=132)begin
      if(n!=135)$fatal(1,"spectrum packet size");
      for(i=3;i<n-4;i=i+8)begin
       if({p[i],p[i+1]}!=3 || {p[i+2],p[i+3]}!=next_bar || p[i+7]!=20+next_bar-101)$fatal(1,"spectrum mapping");
       if(next_bar==132)begin sweeps=sweeps+1;next_bar=101;end else next_bar=next_bar+1;
      end
     end
    end else $fatal(1,"unknown packet opcode");
    n=0;tail=0;
   end
  end
 end
 task command(input[7:0] c,input[15:0] v);begin
  @(negedge clk);cmd=c;value=v;cv=1;@(negedge clk);cv=0;
 end endtask
 initial begin
  repeat(10)@(negedge clk);rst_n=1;command(8'h1f,4);
  wait(frames>=2);change_cycle=cycle;fields[HMI_FIELD_P4_C65_LISS_MODE_0*32+:32]=1;command(8'h41,0);
  wait(mode_echo>=1);wait(frames>=4);
  wait(dut.native_draw && dut.op==8'h66 && dut.pos>20);command(8'h1f,2);
  wait(restores>=1);repeat(CLK_HZ/50)@(negedge clk);
  if(dut.liss_sending)$fatal(1,"stale XY continues after page exit");
  command(8'h1f,3);wait(sweeps>=3);wait(n==0);
  command(8'h1f,4);wait(frames>=5);
  wait(dut.native_draw && dut.op==8'h66 && dut.pos>20 && dut.pos<dut.total-10);
  command(8'h1f,3);wait(restores3>=1);wait(sweeps>=6);
  wait(n==0);$fclose(fd);$fclose(td);
  $display("PASS native XY128/127 unique segments/1 clear per frame/562 bytes/rate limit/control fairness/page-exit restore; spectrum32 sweeps=%0d",sweeps);$finish;
 end
 initial begin repeat(CLK_HZ*2)@(negedge clk);$fatal(1,"watchdog frames=%0d restores=%0d sweeps=%0d state=%0d page=%0d",frames,restores,sweeps,dut.state,page);end
endmodule
