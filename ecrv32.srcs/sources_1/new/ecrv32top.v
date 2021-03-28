`default_nettype none
`timescale 1ns / 1ps

module ecrv32top(
	// System reset key
	input wire reset,

	// Input clocks
	input wire CLK100MHZ,
	input wire CLK12MHZ,

	// VGA pins
	output wire [3:0] VGA_R,
	output wire [3:0] VGA_G,
	output wire [3:0] VGA_B,
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
wire [31:0] vramdataout;
wire indisplayarea;
wire uartsend;
wire uartbyteavailable;
wire [7:0] uartbyte;
wire [7:0] uartbytein;
wire uarttxbusy;
reg [7:0] fifoin = 8'h00;
reg [7:0] datatotransmit = 8'h00;
reg fifowe = 1'b0;
reg transmitbyte = 1'b0;
wire fifore;
reg outfifore = 1'b0;
reg txstate = 1'b0;
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

// Reset wires
wire reset_p = reset | (~clocklocked);
wire reset_n = ~reset & clocklocked;

// System Memory
SysMemGen SysMem(
	.addra(memaddress[15:2]),
	.clka(cpuclock),
	.dina(writeword),
	.douta(mem_data),
	.ena(reset_n),
	.wea(memaddress[31]==1'b0 ? mem_writeena : 4'b0000) );


// CPU Core
wire sddatavalid;
wire sdtxready;
wire sdtxdatavalid;
wire [7:0] sdtxdata;
wire [7:0] sdrcvdata;
cputoplevel riscvcore(
	.reset(reset_p),
	.clock(cpuclock),
	.memaddress(memaddress),
	.writeword(writeword),
	.mem_data(mem_data),
	.mem_writeena(mem_writeena),
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
	.TxD_data(datatotransmit),
	.TxD(uart_rxd_out),
	.TxD_busy(uarttxbusy) );

// UART - Output FIFO
UARTFifoGen UART_out_fifo(
    .rst(reset_p),
    .full(outfifofull),
    .din(uartbyte), // data from CPU
    .wr_en(uartsend), // CPU controls write, high for one clock
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
    .rst(reset_p),
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

// Trigger a FIFO read when the FIFO is not empty and UART is not busy
always @(posedge(uartbase)) begin
	if (txstate == 1'b0) begin // IDLE_STATE
		if (~uarttxbusy & (transmitbyte == 1'b0)) begin // Safe to attempt send, UART not busy or triggered
			if (~outfifoempty) begin // Something in FIFO? Trigger read and go to transmit 
				outfifore <= 1'b1;			
				txstate <= 1'b1;
			end else begin
				outfifore <= 1'b0;
				txstate <= 1'b0; // Stay in idle state
			end
		end else begin // Transmit hardware busy or we kicked a transmit (should end next clock)
			outfifore <= 1'b0;
			txstate <= 1'b0; // Stay in idle state
		end
		transmitbyte <= 1'b0;
	end else begin // TRANSMIT_STATE
		outfifore <= 1'b0; // Stop read request
		if (outfifovalid) begin // Kick send and go to idle
			datatotransmit <= outfifoout;
			transmitbyte <= 1'b1;
			txstate <= 1'b0;
		end else begin
			txstate <= 1'b1; // Stay in transmit state and wait for valid fifo data
		end
	end
end

// Push incoming data to FIFO every time a byte arrives
always @(posedge(uartbase)) begin
	if (uartbyteavailable) begin
		fifowe <= 1'b1;
		fifoin <= uartbytein;
	end else begin
		fifowe <= 1'b0;
	end
end

// Video registers and wires
wire [1:0] videobyteselect;
wire [13:0] videoreadaddress;
wire [5:0] cacheaddress;
wire cacherow;
reg [7:0] videooutbyte;
reg [31:0] scanlinecache [0:64]; // Extra dword at the end for when we're outside view

// Video Memory
VRAMGen VideoMem(
	.addra(memaddress[15:2]),
	.clka(cpuclock),
	.dina(writeword),
	.ena(reset_n),
	.wea(memaddress[31]==1'b1 ? mem_writeena : 4'b0000),
	.addrb(videoreadaddress),
	.clkb(videoclock),
	.doutb(vramdataout) );

// VGA output generator
video vgaout(
	.clk(videoclock),
	.reset(reset_p),
	.vga_h_sync(VGA_HS_O),
	.vga_v_sync(VGA_VS_O),
	.inDisplayArea(indisplayarea),
	.videoreadaddress(videoreadaddress),
    .cacheaddress(cacheaddress),
    .cacherow(cacherow),
	.videobyteselect(videobyteselect));

always @(posedge(videoclock)) begin
	if (cacherow) begin
		scanlinecache[cacheaddress] <= vramdataout;
	end else begin
		case (videobyteselect)
			2'b00: begin
				videooutbyte <= indisplayarea ? scanlinecache[cacheaddress][7:0] : 8'd0;
			end
			2'b01: begin
				videooutbyte <= indisplayarea ? scanlinecache[cacheaddress][15:8] : 8'd0;
			end
			2'b10: begin
				videooutbyte <= indisplayarea ? scanlinecache[cacheaddress][23:16] : 8'd0;
			end
			2'b11: begin
				videooutbyte <= indisplayarea ? scanlinecache[cacheaddress][31:24] : 8'd0;
			end
		endcase
	end
end

assign VGA_B = indisplayarea ? {1'b0, videooutbyte[7:6], 1'b0} : 4'b0;
assign VGA_R = indisplayarea ? {1'b0, videooutbyte[5:3]} : 4'b0;
assign VGA_G = indisplayarea ? {1'b0, videooutbyte[2:0]} : 4'b0;

// SD Card controller
SPI_Master_With_Single_CS SDCardController (
	// Control/Data Signals
	.i_Rst_L(reset_n),					// FPGA Reset
	.i_Clk(cpuclock),					// FPGA Clock @140Mhz, but this has only been properly tested with 100Mhz so far
   
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

// SoC status LEDs
assign led = {1'b0, 1'b0, 1'b0, cd};

endmodule
