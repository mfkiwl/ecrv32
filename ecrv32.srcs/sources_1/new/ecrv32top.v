`default_nettype none
`timescale 1ns / 1ps

module ecrv32top(
	// System reset key
	input wire reset,

	// Input clocks
	input wire CLK100MHZ,
	input wire CLK12MHZ,

	// VGA pins
	output reg [3:0] VGA_R,
	output reg [3:0] VGA_G,
	output reg [3:0] VGA_B,
	output wire VGA_HS_O,
	output wire VGA_VS_O,
	
	// LEDs
	output wire [3:0] led,

	// UART pins
	output wire uart_rxd_out,
	input wire uart_txd_in/*,

	// DDR3 pins
	inout [15:0] ddr3_dq,
	inout [1:0] ddr3_dqs_n,
	inout [1:0] ddr3_dqs_p,
	output [13:0] ddr3_addr,
	output [2:0] ddr3_ba,
	output ddr3_ras_n,
	output ddr3_cas_n,
	output ddr3_we_n,
	output ddr3_reset_n,
	output [0:0] ddr3_ck_p,
	output [0:0] ddr3_ck_n,
	output [0:0] ddr3_cke,
	output [0:0] ddr3_cs_n,
	output [1:0] ddr3_dm,
	output [0:0] ddr3_odt*/ );

// Wires and registers
wire cpuclock, videoclock, uartbase, clockAlocked, clockBlocked;
wire [31:0] memaddress;
wire [31:0] writeword;
wire [31:0] mem_data;
wire [3:0] mem_writeena;
wire chipselect;
wire [31:0] vramdataout;
wire [1:0] videobyteselect;
wire indisplayarea;
wire uartsend;
wire uartbyteavailable;
wire [7:0] uartbyte;
wire [7:0] uartbytein;
wire uarttxbusy;
reg [7:0] fifoin;
reg fifowe;
wire fifore;
wire [7:0] fifoout;
wire fifofull;
wire fifoempty;
wire fifovalid;
wire [10:0] fifodatacount;
wire instructionfault;
wire executing;
wire fillingcache;
reg [3:0] videoR;
reg [3:0] videoG;
reg [3:0] videoB;
wire [9:0] pixelX;
wire [9:0] pixelY;
wire [13:0] videoreadaddress;
wire [5:0] cacheaddress;
wire cacherow;

reg [31:0] scanlinecache [0:63];

// Clocks
CoreClockGen SystemClock(
	.cpuclock(cpuclock),
	.resetn(~reset),
	.locked(clockAlocked),
	.clk_in1(CLK100MHZ) );

PeripheralClockGen PeripheralClock(
	.videoclock(videoclock),
	.uartbase(uartbase),
	.resetn(~reset),
	.locked(clockBlocked),
	.clk_in1(CLK12MHZ) );

wire clocklocked = clockAlocked & clockBlocked;

// System Memory
SysMemGen SysMem(
	.addra(memaddress[15:2]),
	.clka(cpuclock),
	.dina(writeword),
	.douta(mem_data),
	.ena((~reset) & clocklocked),
	.wea(chipselect==1'b0 ? mem_writeena : 4'b0000) );

// Video Memory
VRAMGen VideoMem(
	.addra(memaddress[15:2]),
	.clka(cpuclock),
	.dina(writeword),
	.ena((~reset) & clocklocked),
	.wea(chipselect==1'b1 ? mem_writeena : 4'b0000),
	.addrb(videoreadaddress),
	.clkb(videoclock),
	.doutb(vramdataout) );
	
// CPU Core
cputoplevel riscvcore(
	.reset((reset) | (~clocklocked)),
	.clock(cpuclock),
	.memaddress(memaddress),
	.writeword(writeword),
	.mem_data(mem_data),
	.mem_writeena(mem_writeena),
	.chipselect(chipselect),
	.uartsend(uartsend),
	.uartbyte(uartbyte),
	.uarttxbusy(uarttxbusy),
    .fifore(fifore),
    .fifoout(fifoout),
    .fifovalid(fifovalid),
    .fifodatacount(fifodatacount) );
    
/*ddr3ctl externalmemory(
  // Inouts
  inout [15:0]       ddr3_dq,
  inout [1:0]        ddr3_dqs_n,
  inout [1:0]        ddr3_dqs_p,
  // Outputs
  output [13:0]     ddr3_addr,
  output [2:0]        ddr3_ba,
  output            ddr3_ras_n,
  output            ddr3_cas_n,
  output            ddr3_we_n,
  output            ddr3_reset_n,
  output [0:0]       ddr3_ck_p,
  output [0:0]       ddr3_ck_n,
  output [0:0]       ddr3_cke,
  output [0:0]        ddr3_cs_n,
  output [1:0]     ddr3_dm,
  output [0:0]       ddr3_odt,
  // Inputs
  // Single-ended system clock
  input         sys_clk_i,
  // Single-ended iodelayctrl clk (reference clock)
  input             clk_ref_i,
  // user interface signals
  input [27:0]       app_addr,
  input [2:0]       app_cmd,
  input             app_en,
  input [127:0]        app_wdf_data,
  input             app_wdf_end,
  input [15:0]        app_wdf_mask,
  input             app_wdf_wren,
  output [127:0]       app_rd_data,
  output            app_rd_data_end,
  output            app_rd_data_valid,
  output            app_rdy,
  output            app_wdf_rdy,
  input         app_sr_req,
  input         app_ref_req,
  input         app_zq_req,
  output            app_sr_active,
  output            app_ref_ack,
  output            app_zq_ack,
  output            ui_clk,
  output            ui_clk_sync_rst,
  output            init_calib_complete,
  output [11:0]                                device_temp,
  input			sys_rst
  );*/

// UART (uses same clock as CPU to avoid crossing clock domains)

// UART - Transmitter
async_transmitter UART_transmit(
	.clk(cpuclock),
	.TxD_start(uartsend),
	.TxD_data(uartbyte),
	.TxD(uart_rxd_out),
	.TxD_busy(uarttxbusy) );

// UART - Receiver
async_receiver UART_receive(
	.clk(uartbase),
	.RxD(uart_txd_in),
	.RxD_data_ready(uartbyteavailable),
	.RxD_data(uartbytein),
	.RxD_idle(),
	.RxD_endofpacket() );

// UART - Input FIFO
UARTFifoGen UART_fifo(
    .rst((reset) | (~clocklocked)),
    .full(fifofull),
    .din(fifoin),
    .wr_en(fifowe),
    .empty(fifoempty),
    .dout(fifoout),
    .rd_en(fifore),
    .wr_clk(uartbase),
    .rd_clk(cpuclock),
    .valid(fifovalid),
    .wr_rst_busy(),
    .rd_rst_busy(),
    .rd_data_count(fifodatacount) );
	
always @(posedge(uartbase)) begin
	// Push incoming data to fifo every time one byte arrives
	if (uartbyteavailable) begin
		fifowe <= 1'b1;
		fifoin <= uartbytein;
	end else begin
		fifowe <= 1'b0;
	end
end

// VGA clock generator
video vgaout(
	.clk(videoclock),
	.reset((reset) | (~clocklocked)),
	.vga_h_sync(VGA_HS_O),
	.vga_v_sync(VGA_VS_O),
	.inDisplayArea(indisplayarea),
	.pixelX(pixelX),
	.pixelY(pixelY),
	.videoreadaddress(videoreadaddress),
    .cacheaddress(cacheaddress),
    .cacherow(cacherow),
	.videobyteselect(videobyteselect));

// Scanline cache to scan-out conversion
always @(posedge(videoclock)) begin
	if (cacherow) begin
		scanlinecache[cacheaddress] <= vramdataout;
	end else begin
		case (videobyteselect)
			2'b00: begin
				VGA_B <= indisplayarea ? {1'b0,scanlinecache[cacheaddress][7:6],1'b0} : 4'b0;
				VGA_R <= indisplayarea ? {1'b0,scanlinecache[cacheaddress][5:3]} : 4'b0;
				VGA_G <= indisplayarea ? {1'b0,scanlinecache[cacheaddress][2:0]} : 4'b0;
			end
			2'b01: begin
				VGA_B <= indisplayarea ? {1'b0,scanlinecache[cacheaddress][15:14],1'b0} : 4'b0;
				VGA_R <= indisplayarea ? {1'b0,scanlinecache[cacheaddress][13:11]} : 4'b0;
				VGA_G <= indisplayarea ? {1'b0,scanlinecache[cacheaddress][10:8]} : 4'b0;
			end
			2'b10: begin
				VGA_B <= indisplayarea ? {1'b0,scanlinecache[cacheaddress][23:22],1'b0} : 4'b0;
				VGA_R <= indisplayarea ? {1'b0,scanlinecache[cacheaddress][21:19]} : 4'b0;
				VGA_G <= indisplayarea ? {1'b0,scanlinecache[cacheaddress][18:16]} : 4'b0;
			end
			2'b11: begin
				VGA_B <= indisplayarea ? {1'b0,scanlinecache[cacheaddress][31:30],1'b0} : 4'b0;
				VGA_R <= indisplayarea ? {1'b0,scanlinecache[cacheaddress][29:27]} : 4'b0;
				VGA_G <= indisplayarea ? {1'b0,scanlinecache[cacheaddress][26:24]} : 4'b0;
			end
		endcase
	end
end

assign led = {reset, 1'b0, 1'b0, 1'b0};

endmodule
