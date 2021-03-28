`default_nettype none
`timescale 1ns / 1ps

module video(
    input wire clk,
    input wire reset,
    output wire vga_h_sync,
    output wire vga_v_sync,
    output wire inDisplayArea,
    output wire [13:0] videoreadaddress,
    output wire [5:0] cacheaddress,
    output wire cacherow,
    output wire [1:0] videobyteselect );

	reg [9:0] CounterX=0;
    reg [9:0] CounterY=0;
    reg vga_HS=0, vga_VS=0;

    wire CounterXmaxed = (CounterX == 800); // 16 + 48 + 96 + 640
    wire CounterYmaxed = (CounterY == 525); // 10 + 2 + 33 + 480

    always @(posedge clk)
    begin
		if (reset) begin
			CounterX <= 0;
		end else begin
		if (CounterXmaxed)
			CounterX <= 0;
		else
			CounterX <= CounterX + 10'd1;
		end
	end

    always @(posedge clk)
    begin
		if (reset) begin
			CounterY <= 0;
		end else begin
		  if (CounterXmaxed)
		  begin
			if(CounterYmaxed)
			  CounterY <= 0;
			else
			  CounterY <= CounterY + 10'd1;
		  end
		end
	end

    always @(posedge clk)
    begin
		if (reset) begin
			vga_HS <= 0;
			vga_VS <= 0;
		end else begin
			vga_HS <= (CounterX > (640 + 16) && (CounterX < (640 + 16 + 96)));	// active for 96 clocks
			vga_VS <= (CounterY > (480 + 10) && (CounterY < (480 + 10 + 2)));	// active for 2 clocks
		end
	end
	
    assign vga_h_sync = ~vga_HS;
    assign vga_v_sync = ~vga_VS;
    assign inDisplayArea = (CounterX >= 64) && (CounterY >= 48) && (CounterX < 576) && (CounterY < 432);	// 512x384 window centered inside 640x480 image

    wire [9:0] pixelX;
    wire [9:0] pixelY;
	assign pixelX = (CounterX-10'd64);
	assign pixelY = (CounterY-10'd48);

    assign videoreadaddress = {pixelY[8:1], CounterX[5:0]}; // counterx%64   //{pixelY[8:1], pixelX[8:1]} : 16'h0000;
	// NOTE: We don't do a >=64 here because we need to kick the buffer reads one clock ahead
    assign cacheaddress = (CounterX > 64) ? pixelX[8:3] : (CounterX[5:0]-6'd1); // When outside, cacheaddress steps rapidly, in view it steps at 1/4th the rate of pixels
    assign cacherow = CounterX > 64 ? 1'b0 : 1'b1; // Scanline cache enabled when we're in left window
    assign videobyteselect = CounterX[2:1];

endmodule
