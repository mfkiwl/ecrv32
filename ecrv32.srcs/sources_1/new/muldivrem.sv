`default_nettype none
`timescale 1ns / 1ps

module multiplier(
	input wire [2:0] func3,
	input wire [31:0] A,
	input wire [31:0] B,
	output wire [31:0] multiplier_result );
	
reg [63:0] result;

always @(*) begin
	case(func3)
		3'b000, 3'b001: result = $signed(A) * $signed(B); // MUL, MULH
		3'b010: result = $signed(A) * B; // MULHSU
		3'b011: result = A * B; // MULHU
		default: result = 64'd0;
	endcase
end

assign multiplier_result = (func3 == 3'b000) ? result[31:0] : result[63:32];

endmodule

module divider(
    input wire logic clk,
    input wire logic reset,
    input wire logic start,          // start signal
    output     logic busy,           // calculation in progress
    output     logic dbz,            // divide by zero flag
    output     logic divdone,
    input wire logic [31:0] x,  // dividend
    input wire logic [31:0] y,  // divisor
    output     logic [31:0] q,  // quotient
    output     logic [31:0] r   // remainder
);

logic [31:0] div_R;		// copy of divident
logic [31:0] prev_Q;	// to roll back one when done
logic [31:0] prev_R;
logic [31:0] div_D;		// copy of divisor
logic [31:0] div_Q;		// quotient
logic [1:0] div_state;	// divider state
logic signflip;			// dividend/divisor resulting sign
logic divsigned;		// dividend's sign

always_ff @(posedge clk) begin
	if (reset) begin
		divdone <= 1'b0;
		busy <= 1'b0;
		dbz <= 1'b0;
		div_R <= 32'd0;
		div_D <= 32'd0;
		signflip <= 1'b0;
		divsigned <= 1'b0;
		div_Q <= 32'd0;
		div_state <= 2'b00;
	end else begin
		if (start) begin
			if (y[30:0] == 31'd0) begin // could be zero or minus zero
				busy <= 1'b0;
				dbz <= 1'b1; // Division by zero
				div_R <= 32'd0;
				div_D <= 32'd0;
				signflip <= 1'b0;
				divsigned <= 1'b0;
				div_Q <= 32'd0;
				div_state <= 2'b00;
				divdone <= 1'b1;
			end else begin
				busy <= 1'b1;
				dbz <= 1'b0;
				div_R <= x[31] ? ((x^32'hFFFFFFFF) + 32'd1)&32'h7FFFFFFF : x; // abs(x)
				div_D <= y[31] ? ((y^32'hFFFFFFFF) + 32'd1)&32'h7FFFFFFF : y; // abs(y)
				signflip <= (x[31]^y[31]);
				divsigned <= x[31];
				div_Q <= 32'd0;
				div_state <= 2'b01;
				divdone <= 1'b0;
			end
		end else begin
			case(div_state)
				2'b00: begin
					divdone <= 1'b0;
				end
				2'b01: begin
					if(div_R[31]) begin // Done dividing when remainder goes negative
						div_state <= 2'b10;
					end else begin
						prev_R <= div_R;
						prev_Q <= div_Q;
						div_R <= div_R + ((div_D^32'hFFFFFFFF)+32'd1); // same as div_R = div_R - div_D
						div_Q <= div_Q + 32'd1; // Increment quotient
					end
					divdone <= 1'b0;
				end
				2'b10: begin
					// Final result has the sign of xor of A and B
					q <= signflip ? ((prev_Q^32'hFFFFFFFF)+32'd1) : prev_Q;
					r <= divsigned ? ((prev_R^32'hFFFFFFFF)+32'd1) : prev_R;
					busy <= 1'b0;
					div_state <= 2'b00;
					divdone <= 1'b1;
				end
				2'b11: begin
					divdone <= 1'b0;
				end
			endcase
		end
	end
end

endmodule
