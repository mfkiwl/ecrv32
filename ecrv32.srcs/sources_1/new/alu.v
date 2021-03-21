`default_nettype none
`timescale 1ns / 1ps

`include "aluops.vh"

module ALU(
	input wire clock,
	input wire reset,
	input wire divstart,
	input wire fdivstart,
	output reg [31:0] aluout,
	output reg [31:0] faluout,
	input wire [2:0] func3,
	input wire [31:0] val1,
	input wire [31:0] val2,
	input wire [31:0] fval1,
	input wire [31:0] fval2,
	input wire [4:0] aluop,
	input wire [4:0] faluop,
	output wire alustall );

// Integer multiplication unit
wire [31:0] multiplier_result;
multiplier themul(.func3(func3), .A(val1), .B(val2), .multiplier_result(multiplier_result));

// Integer division unit
wire [31:0] quotient;
wire [31:0] remainder;
wire divbusy;
wire divdone;
wire divbyzero;
divider thediv (
	.reset(reset),
	.clk(clock),
	.start(divstart),	// start signal
	.busy(divbusy),		// calculation in progress
	.divdone(divdone),	// division complete
	.dbz(divbyzero),	// divide by zero flag
	.x(val1),			// dividend
	.y(val2),			// divisor
	.q(quotient),		// quotient
	.r(remainder)		// remainder
);

// NOTE: Floating point modules are from https://github.com/cnrv/CNRV-FPU

// Floating point control and status register (exceptions and rounding control)
reg [31:0] fcsr;

// Float outputs
wire [31:0] Fout;
wire [7:0] addTailZeroCount;
wire [7:0] mulTailZeroCount;
wire [7:0] zAddExp;
wire [7:0] zMulExp;
wire [5:0] zAddStatus;
wire [5:0] zMulStatus;
wire [26:0] zAddSig;
wire [26:0] zMulSig;
wire zAddSign;
wire zMulSign;
wire idiv_done;
wire fdivdone;
wire fdivready;
wire [31:0] fdivfast;
wire [2:0] rnd_o;

// FP adder
R5FP_add  #(8,23) float_adder (
    .a(fval1), .b(fval2),
    .zExp(zAddExp),
	.tailZeroCnt(addTailZeroCount),
	.zStatus(zAddStatus),
	.zSig(zAddSig),
	.zSign(zAddSign) );

// FP multiplier
R5FP_mul  #(8,23) float_multiplier (
    .a(fval1), .b(fval2),
    .zExp(zMulExp),
	.tailZeroCnt(mulTailZeroCount),
	.zStatus(zMulStatus),
	.zSig(zMulSig),
	.zSign(zMulSign) );
	
// FP divider
R5FP_div #(23,8) float_divider (
		.a_i(fval1), .b_i(fval2),
		.rnd_i(3'b000),  // TODO: Rounding mode should come from float control register (fcsr)
		.strobe_i(fdivstart), // Strobe once to kick division
		.xExp_o(),
		.tailZeroCnt_o(),
		.xSig_o(),
		.xMidStatus_o(),
		.xStatus_fast_o(),
		.x_fast_o(fdivfast),
		.x_use_fast(),
		.rnd_o(rnd_o),

		.idiv_N(), 
		.idiv_D(), 
		.idiv_strobe(), 
		.idiv_Quo(), // quotient
		.idiv_Rem(), // remainder
		.idiv_done(1'b0),
		.idiv_ready(1'b1),

		.done_o(fdivdone), .ready_o(fdivready),
		.clk(clock), .reset(reset) );

// Combined FADD output
wire [31:0] FADDResult = {zAddSign, zAddExp, zAddSig[24:2]}; // Expected: 2.5f (32'h40200000)
wire [31:0] FMULResult = {zMulSign, zMulExp, zMulSig[24:2]}; // Expected: 1.0f (32'h3f800000)
wire [31:0] FDIVResult = fdivfast; // Expected 4.0f (32'h40800000)

// Float ALU
always @(*) begin

    if (reset) begin

        fcsr = 32'd0;
        faluout = 32'd0;

    end else begin

        case (faluop)
            // M
            `ALU_FADD:  begin faluout = FADDResult; end
            `ALU_FMUL:  begin faluout = FMULResult; end
            `ALU_FDIV:  begin if (fdivready) faluout = FDIVResult; end

            // None
            default:   begin faluout = 0; end
        endcase

    end

end

// Integet ALU
always @(*) begin

    if (reset) begin

        aluout = 32'd0;

    end else begin

        case (aluop)
            // I
            `ALU_ADD:  begin aluout = val1 + val2; end
            `ALU_SUB:  begin aluout = val1 + (~val2 + 32'd1); end
            `ALU_SLL:  begin aluout = val1 << val2[4:0]; end
            `ALU_SLT:  begin aluout = $signed(val1) < $signed(val2) ? 32'd1 : 32'd0; end
            `ALU_SLTU: begin aluout = val1 < val2 ? 32'd1 : 32'd0; end
            `ALU_XOR:  begin aluout = val1 ^ val2; end
            `ALU_SRL:  begin aluout = val1 >> val2[4:0]; end
            `ALU_SRA:  begin aluout = $signed(val1) >>> val2[4:0]; end
            `ALU_OR:   begin aluout = val1 | val2; end
            `ALU_AND:  begin aluout = val1 & val2; end
    
            // M
            `ALU_MUL:  begin aluout = multiplier_result; end
            `ALU_DIV:  begin if(divdone) aluout = quotient; end
            `ALU_REM:  begin if(divdone) aluout = remainder; end
    
            // BRANCH ALU
            `ALU_EQ:   begin aluout = val1 == val2 ? 32'd1 : 32'd0; end
            `ALU_NE:   begin aluout = val1 != val2 ? 32'd1 : 32'd0; end
            `ALU_L:    begin aluout = $signed(val1) < $signed(val2) ? 32'd1 : 32'd0; end
            `ALU_GE:   begin aluout = $signed(val1) >= $signed(val2) ? 32'd1 : 32'd0; end
            `ALU_LU:   begin aluout = val1 < val2 ? 32'd1 : 32'd0; end
            `ALU_GEU:  begin aluout = val1 >= val2 ? 32'd1 : 32'd0; end
    
            // None
            default:   begin aluout = 0; end
        endcase

    end

end

// If this is set to high, the CPU will stall until it's cleared
// Use this to wait for any long ALU operation to complete
assign alustall = ~reset & ((divstart | divbusy) | (fdivstart | ~fdivready));

endmodule
