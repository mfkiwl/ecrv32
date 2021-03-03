`default_nettype none
`timescale 1ns / 1ps

// RV32C
// Quadrant 0
`define CADDI4SPN	5'b00000 // RES, nzuimm=0 +
//`define CFLD		5'b00100 // 32/64
//`define CLQ			5'b00100 // 128
`define CLW			5'b01000 // 32? +
//`define CFLW		5'b01100 // 32
//`define CLD			5'b01100 // 64/128 
//`define CFSD		5'b10100 // 32/64
//`define CSQ			5'b10100 // 128
`define CSW			5'b11000 // 32? +
//`define CFSW		5'b11100 // 32 
//`define CSD			5'b11100 // 61/128
// Quadrant 1									 [12] [11:10] [6:5]
`define CNOP		5'b00001 // HINT, nzimm!=0 +
`define CADDI		5'b00001 // HINT, nzimm=0 +
`define CJAL		5'b00101 // 32 +
//`define CADDIW		5'b00101 // 64/128
`define CLI			5'b01001 //+
`define CADDI16SP	5'b01101 //+
`define CLUI		5'b01101 //+
`define CSRLI		5'b10001 //+                      00      
`define CSRAI		5'b10001 //+                      01      
`define CANDI		5'b10001 //+                      10      
`define CSUB		5'b10001 //+                  0   11      00
`define CXOR		5'b10001 //+                  0   11      01
`define COR			5'b10001 //+                  0   11      10
`define CAND		5'b10001 //+                  0   11      11
//`define CSUBW		5'b10001 //-                  1   11      00
//`define CADDW		5'b10001 //-                  1   11      01
`define CJ			5'b10101 //+
`define CBEQZ		5'b11001 //+
`define CBNEZ		5'b11101 //+
// Quadrant 2
`define CSLLI		5'b00010 //+
//`define CFLDSP		5'b00110
//`define CLQSP		5'b00110
`define CLWSP		5'b01010 //+
//`define CFLWSP		5'b01110
//`define CLDSP		5'b01110
`define CJR			5'b10010 //+
`define CMV			5'b10010 //+
`define CEBREAK		5'b10010 //+
`define CJALR		5'b10010 //+
`define CADD		5'b10010 //+
//`define CFSDSP		5'b10110
//`define CSQSP		5'b10110
`define CSWSP		5'b11010 //+
//`define CFSWSP		5'b11110
//`define CSDSP		5'b11110

module InstructionDecompression(
    input wire [15:0] instr_lowword,
    input wire [15:0] instr_highword,
    output reg is_compressed,
    output reg [31:0] fullinstr
);

always @ (*) begin
  if (instr_lowword[1:0] == 2'b11) begin

	// Already decompressed
	is_compressed = 1'b0;

	fullinstr = {instr_highword, instr_lowword};

	end else begin

		// Needs decompression
		is_compressed = 1'b1;
	
		case ({instr_lowword[15:13], instr_lowword[1:0]})
			`CADDI4SPN: begin
				if (instr_lowword[12:2] != 11'h0 && instr_lowword[12:5] != 8'h0)
				fullinstr = { 2'b00, instr_lowword[10:7], instr_lowword[12:11], instr_lowword[5], instr_lowword[6], 2'b00, 5'd2, 3'b000, 2'b01, instr_lowword[4:2], 7'b0010011 };
			end
			
			`CLW: begin
				fullinstr = { 5'b00000, instr_lowword[5], instr_lowword[12:10], instr_lowword[6], 2'b00, 2'b01, instr_lowword[9:7], 3'b010, 2'b01, instr_lowword[4:2], 7'b0000011 };
			end
			
			`CSW: begin
				fullinstr = { 5'b00000, instr_lowword[5], instr_lowword[12], 2'b01, instr_lowword[4:2], 2'b01, instr_lowword[9:7], 3'b010, instr_lowword[11:10], instr_lowword[6], 2'b00, 7'b0100011 };
			end
			
			`CNOP: begin
				if (instr_lowword[12:2] == 11'h0)
					fullinstr = { 25'h0, 7'b0010011 };
				else if (instr_lowword[12] != 1'b0 || instr_lowword[6:2] != 5'h0) // CADDI
					fullinstr = { {7{instr_lowword[12]}}, instr_lowword[6:2], instr_lowword[11:7], 3'b000, instr_lowword[11:7], 7'b0010011 };
			end
			
			`CJAL: begin
				fullinstr = { instr_lowword[12], instr_lowword[8], instr_lowword[10:9], instr_lowword[6], instr_lowword[7], instr_lowword[2], instr_lowword[11], instr_lowword[5:3], instr_lowword[12], {8{instr_lowword[12]}}, 5'd1, 7'b1101111 };
			end
			
			`CLI: begin
				if (instr_lowword[11:7] != 5'd0)
					fullinstr = { {7{instr_lowword[12]}}, instr_lowword[6:2], 5'd0, 3'b000, instr_lowword[11:7], 7'b0010011 };
			end
			
			`CADDI16SP: begin
				if ((instr_lowword[12] != 1'b0 || instr_lowword[6:2] != 5'h0) && instr_lowword[11:7] != 5'd0) begin
					if (instr_lowword[11:7] == 5'd2)
						fullinstr = { {3{instr_lowword[12]}}, instr_lowword[4], instr_lowword[3], instr_lowword[5], instr_lowword[2], instr_lowword[6], 4'b0000, 5'd2, 3'b000, 5'd2, 7'b0010011 };
					else // CLUI
						fullinstr = { {15{instr_lowword[12]}}, instr_lowword[6:2], instr_lowword[11:7], 7'b0110111 };
				end
			end
			
			`CSRLI: begin
				if (instr_lowword[12:10] == 3'b011 && instr_lowword[6:5] == 2'b00) // CSUB
					fullinstr = { 7'b0100000, 2'b01, instr_lowword[4:2], 2'b01, instr_lowword[9:7], 3'b000, 2'b01, instr_lowword[9:7], 7'b0110011 };
				else if (instr_lowword[12:10] == 3'b011 && instr_lowword[6:5] == 2'b01) // CXOR
					fullinstr = { 7'b0000000, 2'b01, instr_lowword[4:2], 2'b01, instr_lowword[9:7], 3'b100, 2'b01, instr_lowword[9:7], 7'b0110011 };
				else if (instr_lowword[12:10] == 3'b011 && instr_lowword[6:5] == 2'b10) // COR
					fullinstr = { 7'b0000000, 2'b01, instr_lowword[4:2], 2'b01, instr_lowword[9:7], 3'b110, 2'b01, instr_lowword[9:7], 7'b0110011 };
				else if (instr_lowword[12:10] == 3'b011 && instr_lowword[6:5] == 2'b11) // CAND
					fullinstr = { 7'b0000000, 2'b01, instr_lowword[4:2], 2'b01, instr_lowword[9:7], 3'b111, 2'b01, instr_lowword[9:7], 7'b0110011 };
				else if (instr_lowword[11:10] == 2'b10) // CANDI
					fullinstr = { {7{instr_lowword[12]}}, instr_lowword[6:2], 2'b01, instr_lowword[9:7], 3'b111, 2'b01, instr_lowword[9:7], 7'b0010011 };
				else if (instr_lowword[12] == 1'b0 && instr_lowword[6:2] == 5'h0)
					fullinstr = 32'h0; // UNDEF
				else if (instr_lowword[11:10] == 2'b00) // CSRLI
					fullinstr = { 7'b0000000, instr_lowword[6:2], 2'b01, instr_lowword[9:7], 3'b101, 2'b01, instr_lowword[9:7], 7'b0010011 };
				else if (instr_lowword[11:10] == 2'b01) // CSRAI
					fullinstr = { 7'b0100000, instr_lowword[6:2], 2'b01, instr_lowword[9:7], 3'b101, 2'b01, instr_lowword[9:7], 7'b0010011 };
			end
			
			`CJ: begin
				fullinstr = { instr_lowword[12], instr_lowword[8], instr_lowword[10:9], instr_lowword[6], instr_lowword[7], instr_lowword[2], instr_lowword[11], instr_lowword[5:3], instr_lowword[12], {8{instr_lowword[12]}}, 5'd0, 7'b1101111 };
			end
			
			`CBEQZ: begin
				fullinstr = { {4{instr_lowword[12]}}, instr_lowword[6], instr_lowword[5], instr_lowword[2], 5'd0, 2'b01, instr_lowword[9:7], 3'b000, instr_lowword[11], instr_lowword[10], instr_lowword[4], instr_lowword[3], instr_lowword[12], 7'b1100011 };
			end
			
			`CBNEZ: begin
				fullinstr = { {4{instr_lowword[12]}}, instr_lowword[6], instr_lowword[5], instr_lowword[2], 5'd0, 2'b01, instr_lowword[9:7], 3'b001, instr_lowword[11], instr_lowword[10], instr_lowword[4], instr_lowword[3], instr_lowword[12], 7'b1100011 };
			end
			
			`CSLLI: begin
				if (instr_lowword[11:7] != 5'd0)
					fullinstr = { 7'b0000000, instr_lowword[6:2], instr_lowword[11:7], 3'b001, instr_lowword[11:7], 7'b0010011 };
			end
			
			`CLWSP: begin
				if (instr_lowword[11:7] != 5'h0)
					fullinstr = { 4'b0000, instr_lowword[3:2], instr_lowword[12], instr_lowword[6:4], 2'b0, 5'd2, 3'b010, instr_lowword[11:7], 7'b0000011 };
			end
			
			`CSWSP: begin
				fullinstr = { 4'b0000, instr_lowword[8:7], instr_lowword[12], instr_lowword[6:2], 5'd2, 3'b010, instr_lowword[11:9], 2'b00, 7'b0100011 };
			end
			
			`CJR: begin
				if (instr_lowword[6:2] == 5'd0) begin
					if (instr_lowword[11:7] == 5'h0) begin
						if (instr_lowword[12] == 1'b1) // CEBREAK
							fullinstr = { 11'h0, 1'b1, 13'h0, 7'b1110011 };
					end else if (instr_lowword[12])
						fullinstr = { 12'h0, instr_lowword[11:7], 3'b000, 5'd1, 7'b1100111 }; // CJALR
				else
					fullinstr = { 12'h0, instr_lowword[11:7], 3'b000, 5'd0, 7'b1100111 }; // CJR
				end else if (instr_lowword[11:7] != 5'h0) begin
					if (instr_lowword[12] == 1'b0) // CMV
						fullinstr = { 7'b0000000, instr_lowword[6:2], 5'd0, 3'b000, instr_lowword[11:7], 7'b0110011 };
					else // CADD
						fullinstr = { 7'b0000000, instr_lowword[6:2], instr_lowword[11:7], 3'b000, instr_lowword[11:7], 7'b0110011 };
				end
			end
			
			default: begin
				fullinstr = 32'd0; // UNDEF
			end
	
		endcase

	end
end

endmodule
