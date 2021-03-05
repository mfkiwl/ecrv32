`default_nettype none
`timescale 1ns / 1ps

module registerfile(
	input wire reset,			// Internal state resets when high
	input wire clock,			// Writes are clocked, reads are not
	input wire [4:0] rs1,		// Source register 1
	input wire [4:0] rs2,		// Source register 2
	input wire [4:0] rd,			// Destination register
	input wire wren,				// Write enable bit for writing to register rd 
	input wire [31:0] datain,	// Data to write to register rd
	output wire [31:0] rval1,	// Register values for rs1 and rs2
	output wire [31:0] rval2 );

reg [31:0] registers[0:31]; 

always @(posedge clock) begin
	if (reset) begin
		registers[0]  <= 32'h00000000; // zero (hardwired to zero)
		registers[1]  <= 32'h00000000; // ra (return address)
		registers[2]  <= 32'h0000FFF0; // sp (stack pointer, bottom of SYSRAM-16, spec says align to 16 bytes, rest is 16 bytes of unused/stash memory)
		registers[3]  <= 32'h00000BF0; // gp (global pointer)
		registers[4]  <= 32'h00000000; // tp (thread pointer)
		registers[5]  <= 32'h00000000; // t0 (temporary/alternate link register)
		registers[6]  <= 32'h00000000; // t1 (temporaries)
		registers[7]  <= 32'h00000000; // t2
		registers[8]  <= 32'h00000000; // s0/fp (saved register/frame pointer)
		registers[9]  <= 32'h00000000; // s1 (saved register)
		registers[10] <= 32'h00000000; // a0 (function arguments/return values)
		registers[11] <= 32'h00000000; // a1
		registers[12] <= 32'h00000000; // a2 (function arguments)
		registers[13] <= 32'h00000000; // a3
		registers[14] <= 32'h00000000; // a4
		registers[15] <= 32'h00000000; // a5
		registers[16] <= 32'h00000000; // a6
		registers[17] <= 32'h00000000; // a7
		registers[18] <= 32'h00000000; // s2
		registers[19] <= 32'h00000000; // s3
		registers[20] <= 32'h00000000; // s4
		registers[21] <= 32'h00000000; // s5
		registers[22] <= 32'h00000000; // s6
		registers[23] <= 32'h00000000; // s7
		registers[24] <= 32'h00000000; // s8
		registers[25] <= 32'h00000000; // s9
		registers[26] <= 32'h00000000; // s10
		registers[27] <= 32'h00000000; // s11
		registers[28] <= 32'h00000000; // t3
		registers[29] <= 32'h00000000; // t4
		registers[30] <= 32'h00000000; // t5
		registers[31] <= 32'h00000000; // t6
	end else begin
		if (wren && rd != 5'd0)
			registers[rd] <= datain;
	end
end

assign rval1 = registers[rs1];
assign rval2 = registers[rs2];

endmodule
