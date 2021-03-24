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
	input wire uart_txd_in,
	
	// SD Card PMOD on port A
	output wire cs_n, // CS/CD/DAT3
	output wire mosi, // MOSI/CMD/DI
	input wire miso, // MISO/DAT0/DO
	output wire sck, // SCLK/CK
	//inout wire [1:0] dat, // DAT1&DAT2
	input wire cd // CD

	/*
	// DDR3 pins
	, inout [15:0] ddr3_dq,
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
wire cpuclock, videoclock, uartbase, sdcardclock, clockAlocked, clockBlocked;
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
reg [7:0] outfifoin = 8'h00;
wire uarttxbusy;
reg [7:0] fifoin = 8'h00;
reg fifowe = 1'b0;
reg outfifowe = 1'b0;
reg transmitbyte = 1'b0;
wire fifore;
reg outfifore = 1'b0;
wire [7:0] fifoout;
wire [7:0] outfifoout;
wire fifofull;
wire outfifofull;
wire fifoempty;
wire outfifoempty;
wire fifovalid;
wire outfifovalid;
wire [10:0] fifodatacount;
wire [10:0] outfifodatacount;
wire instructionfault;
wire executing;
wire fillingcache;
reg [3:0] videoR = 1'b0;
reg [3:0] videoG = 1'b0;
reg [3:0] videoB = 1'b0;
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
	.sdcardclock(sdcardclock),
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
wire sddatavalid;
wire sdtxready;
wire sdtxdatavalid;
wire [7:0] sdtxdata;
wire [7:0] sdrcvdata;
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
    .fifore(fifore),
    .fifoout(fifoout),
    .fifovalid(fifovalid),
    .fifodatacount(fifodatacount),
	.sdtxready(sdtxready),
    .spisend(sdtxdatavalid),
    .spioutput(sdtxdata),
    .spiinputready(sddatavalid),
    .spiinput(sdrcvdata) );
    
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
	.clk(uartbase),
	.TxD_start(transmitbyte),
	.TxD_data(outfifoout),
	.TxD(uart_rxd_out),
	.TxD_busy(uarttxbusy) );

// UART - Output FIFO
UARTFifoGen UART_out_fifo(
    .rst((reset) | (~clocklocked)),
    .full(outfifofull),
    .din(outfifoin), // data from CPU
    .wr_en(outfifowe), // CPU controls write
    .empty(outfifoempty),
    .dout(outfifoout), // to transmitter
    .rd_en(outfifore), // transmitter can send
    .wr_clk(cpuclock),
    .rd_clk(uartbase), // transmitter runs slower
    .valid(outfifovalid),
    .wr_rst_busy(),
    .rd_rst_busy(),
    .rd_data_count(outfifodatacount) );

// UART - Receiver
async_receiver UART_receive(
	.clk(uartbase),
	.RxD(uart_txd_in),
	.RxD_data_ready(uartbyteavailable),
	.RxD_data(uartbytein),
	.RxD_idle(),
	.RxD_endofpacket() );

// UART - Input FIFO
UARTFifoGen UART_in_fifo(
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
    
always @(posedge(cpuclock)) begin
	if (uartsend) begin // Push data to send
		outfifowe <= 1'b1;
		outfifoin <= uartbyte;
	end else begin
		outfifowe <= 1'b0;
	end
end

// Output bytes from the FIFO
always @(posedge(uartbase)) begin
	if (uarttxbusy | outfifoempty) begin
		outfifore <= 1'b0;
		transmitbyte <= 1'b0;
	end else begin
		outfifore <= 1'b1;
		transmitbyte <= 1'b1;
	end
end
	
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

// SDCARD
SPI_Master_With_Single_CS SDCardController (
	// Control/Data Signals
	.i_Rst_L((~reset) & (clocklocked)),	// FPGA Reset
	.i_Clk(cpuclock),					// FPGA Clock @100Mhz
   
	// TX (MOSI) Signals
	.i_TX_Count(2'b10),					// Bytes per CS low
	.i_TX_Byte(sdtxdata),				// Byte to transmit on MOSI
	.i_TX_DV(sdtxdatavalid),			// Data Valid Pulse with i_TX_Byte
	.o_TX_Ready(sdtxready),				// Transmit Ready for next byte

	// RX (MISO) Signals
	.o_RX_DV(sddatavalid),				// Data Valid pulse (1 clock cycle)
	.o_RX_Byte(sdrcvdata),				// Byte received on MISO
	.o_RX_Count(),						// Receive count - unused

	// SPI Interface
	.o_SPI_Clk(sck),
	.i_SPI_MISO(miso),
	.o_SPI_MOSI(mosi),
	.o_SPI_CS_n(cs_n) );

//assign dat[0] = 1'b1;
//assign dat[1] = 1'b1;

// SoC status LEDs
assign led = {reset, sddatavalid, sdtxready, cd};

endmodule
