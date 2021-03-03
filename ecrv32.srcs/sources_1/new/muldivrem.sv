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

assign multiplier_result = (func3 == 3'b000) ? result[31:0] : result[63:0];

endmodule

module div_int #(parameter WIDTH=32) (
    input wire logic clk,
    input wire logic reset,
    input wire logic start,          // start signal
    output     logic busy,           // calculation in progress
    output     logic dbz,            // divide by zero flag
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
logic div_state;		// divider state
logic signflip;

always_ff @(posedge clk) begin
	if (reset) begin
		busy <= 1'b0;
		dbz <= 1'b0;
		div_R <= 32'd0;
		div_D <= 32'd0;
		signflip <= 1'b0;
		div_Q <= 32'd0;
		div_state <= 1'b0;
	end else begin
		if (start) begin
			if (y[30:0] == 31'd0) begin // could be zero or minus zero
				busy <= 1'b0;
				dbz <= 1'b1; // Division by zero
				div_R <= 32'd0;
				div_D <= 32'd0;
				signflip <= 1'b0;
				div_Q <= 32'd0;
				div_state <= 1'b0;
			end else begin
				busy <= 1'b1;
				dbz <= 1'b0;
				div_R <= x&32'h80000000 ? ((x^32'hFFFFFFFF) + 32'd1)&32'h7FFFFFFF : x; // abs(x)
				div_D <= y&32'h80000000 ? ((y^32'hFFFFFFFF) + 32'd1)&32'h7FFFFFFF : y; // abs(y)
				signflip <= (x[31]^y[31]);
				div_Q <= 32'd0;
				div_state <= 1'b0;
			end
		end else begin
			case(div_state)
				1'b0: begin
					if((div_R&32'h80000000)) begin // Done dividing when remainder goes negative
						div_state <= 1'b1;
					end else begin
						prev_R <= div_R;
						div_R <= div_R + ((div_D^32'hFFFFFFFF)+1);
						prev_Q <= div_Q;
						div_Q <= div_Q + 32'd1; // Increment quotient
					end
				end
				1'b1: begin
					// Final result has the sign of xor of A and B
					q <= signflip ? ((prev_Q^32'hFFFFFFFF)+32'd1) : prev_Q;
					r <= prev_R;
					busy <= 1'b0;
				end
				default: begin
				end
			endcase
		end
	end
end

endmodule

/*
module div_int #(parameter WIDTH=32) (
    input wire logic clk,
    input wire logic start,          // start signal
    output     logic busy,           // calculation in progress
    output     logic valid,          // quotient and remainder are valid
    output     logic dbz,            // divide by zero flag
    input wire logic [WIDTH-1:0] x,  // dividend
    input wire logic [WIDTH-1:0] y,  // divisor
    output     logic [WIDTH-1:0] q,  // quotient
    output     logic [WIDTH-1:0] r   // remainder
    );

    logic [WIDTH-1:0] y1;            // copy of divisor
    logic [WIDTH-1:0] q1, q1_next;   // intermediate quotient
    logic [WIDTH:0] ac, ac_next;     // accumulator (1 bit wider)
    logic [$clog2(WIDTH)-1:0] i;     // iteration counter
    logic sgnflip;

    always_comb begin
        if (ac >= {1'b0,y1}) begin
            ac_next = ac - y1;
            //ac_next = ac + ((y1^32'hFFFFFFFF)+32'd1);
            {ac_next, q1_next} = {ac_next[WIDTH-1:0], q1, 1'b1};
        end else begin
            {ac_next, q1_next} = {ac, q1} << 1;
        end
    end

    always_ff @(posedge clk) begin
        if (start) begin
            valid <= 0;
            i <= 0;
            sgnflip <= 1'b0;
            if (y == 0) begin  // catch divide by zero
                busy <= 0;
                dbz <= 1;
            end else begin  // initialize values
                busy <= 1;
                dbz <= 0;
                y1 <=  y[31]==1'b1 ? -$signed(y) : y; // y
                {ac, q1} <= {{WIDTH{x[31]}}, x[31]==1'b1 ? -$signed(x) : x, 1'b0}; // {{WIDTH{x[31]}}, x, 1'b0};
                sgnflip <= x[31]^y[31]; // Do we need to flip the sign of the result?
            end
        end else if (busy) begin
            if (i == WIDTH-1) begin  // we're done
                busy <= 0;
                valid <= 1;
                q <= sgnflip ? -$signed(q1_next) : q1_next; // q1_next;
                r <= ac_next[WIDTH:1];  // undo final shift NOTE: sign of the remainder is same as x
            end else begin  // next iteration
                i <= i + 1;
                ac <= ac_next;
                q1 <= q1_next;
            end
        end
    end
endmodule
*/