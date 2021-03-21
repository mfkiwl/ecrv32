`default_nettype none
`timescale 1ns / 1ps

`include "cpuops.vh"
`include "aluops.vh"

module cputoplevel(
	input wire reset,
	input wire clock,
	output reg[31:0] memaddress,
	output reg [31:0] writeword,
	input wire [31:0] mem_data,
	output reg [3:0] mem_writeena,
	output reg chipselect,
	output reg uartsend,
	output reg [7:0] uartbyte,
	input wire uarttxbusy,
	output reg fifore,
    input wire [7:0] fifoout,
    input wire fifovalid,
    input wire [10:0] fifodatacount,
    input wire sdtxready,
    output reg spisend,
    output reg [7:0] spioutput,
    input wire spiinputready,
    input wire [7:0] spiinput);

// Instruction cache
reg [26:0] ICACHEADDR = 27'hF;			// Truncated lower bits
reg [15:0] ICACHE[0:17];				// Cached instruction words, indexed using lower bits of IP for 16x16bit word entries plus 2x16bit spare for odd instruction alignment
reg [4:0] ICACHECOUNTER = 5'd0;			// Cache load counter (count 0 to 7, high bit set at 8th 32bit word read)

// CPU States
parameter CPUINIT=0, CPUFETCH=1, CPUCACHEFILLWAIT=2, CPUICACHEFILL=3, CPULOADCOMPLETE=4, CPULOADWAIT=5, 
CPUSTORE=6, CPUEXEC=7, CPURETIREINSTRUCTION=8, CPUUARTREAD=9, CPUSTALL=10;
reg [10:0] cpustate = 11'd1;

// Program counter
reg [31:0] PC = 32'h000FA00;
reg [31:0] nextPC = 32'd0;

// Instruction decomposition
wire [6:0] opcode;
wire [4:0] rs1;
wire [4:0] rs2;
wire [4:0] rd;
wire [2:0] func3;
wire [6:0] func7;

// Register file related wires
reg wren = 1'b0;
reg [31:0] data = 32'd0;
wire [31:0] rval1;
wire [31:0] rval2;
reg fwren = 1'b0;
wire [31:0] frval1;
wire [31:0] frval2;
reg floatmemop = 1'b0;

// ALU/immediate and decoder wires
wire [4:0] aluop;
wire [4:0] faluop;
wire [31:0] aluout;
wire [31:0] faluout;
wire [31:0] imm;
wire selectimmedasrval2;
wire [31:0] fullinstruction;
wire is_compressed;

decoder idecode(
	.clock(clock),
	.reset(reset),
	.instruction(fullinstruction),
	.opcode(opcode),
	.aluop(aluop),
	.faluop(faluop),
	.rs1(rs1),
	.rs2(rs2),
	.rd(rd),
	.func3(func3),
	.func7(func7),
	.imm(imm),
	.selectimmedasrval2(selectimmedasrval2) );

// Integer register file
registerfile regs(
	.reset(reset),
	.clock(clock),
	.rs1(rs1),
	.rs2(rs2),
	.rd(rd),
	.wren(wren),
	.datain(data),
	.rval1(rval1),
	.rval2(rval2) );

// Floating point register file
registerfile floatregs(
	.reset(reset),
	.clock(clock),
	.rs1(rs1),
	.rs2(rs2),
	.rd(rd),
	.wren(fwren),
	.datain(data),
	.rval1(frval1),
	.rval2(frval2) );

// Selectors / precalcs / instruction decompressor related
wire [31:0] rval2selector = selectimmedasrval2 ? imm : rval2;
wire [31:0] incrementedpc = is_compressed ? PC + 32'd2 : PC + 32'd4;
wire [31:0] incrementedbyimmpc = PC + imm;
wire [31:0] rval1plusimm = rval1 + imm;
// If we've missed the cache, produce NOOP during cache fill to avoid strange ALU/regfile/decoder behavior
wire icachenotmissed = PC[31:5] == ICACHEADDR;
wire [15:0] instrhi = icachenotmissed ? ICACHE[{1'b0,PC[4:1]}+5'd1] : 16'h0000;
wire [15:0] instrlo = icachenotmissed ? ICACHE[{1'b0,PC[4:1]}] : {25'd0,`ADDI};
instructiondecompressor rv32cdecompress(.instr_lowword(instrlo), .instr_highword(instrhi), .is_compressed(is_compressed), .fullinstr(fullinstruction));

// ALU
wire alustall;
wire divstart = (cpustate[CPUFETCH]==1'b1 && icachenotmissed) && (aluop==`ALU_DIV || aluop==`ALU_REM); // High only during FETCH when cache is not missed
wire fdivstart = (cpustate[CPUFETCH]==1'b1 && icachenotmissed) && (faluop==`ALU_FDIV); // High only during FETCH when cache is not missed
ALU aluunit(
	.reset(reset),
	.clock(clock),
	.divstart(divstart),
	.fdivstart(fdivstart),
	.aluout(aluout),
	.faluout(faluout),
	.func3(func3),
	.fval1(frval1),
	.fval2(frval2),
	.val1(rval1),
	.val2(rval2selector), // Either source register 2 or immediate
	.aluop(aluop),
	.faluop(faluop),
	.alustall(alustall) );
	
// The CPU: central state machine
always @(posedge clock) begin
	if (reset) begin

		cpustate <= 11'd1;

	end else begin

		cpustate <= 11'd0;

		case (1'b1) // synthesis parallel_case full_case

			cpustate[CPUINIT] : begin

                // Program counter
				PC <= 32'h000FA00; // Point at reset vector by default (bootloader placed here by default)
				nextPC <= 32'd0;

                // Internal block memory access
				memaddress <= 32'd0;
				mem_writeena <= 4'b0000;
				writeword <= 32'd0;
				chipselect <= 1'b0;
				floatmemop <= 1'b0;
				data <= 32'd0;

                // Integer register control
				wren <= 1'b0;
                // Float register control
				fwren <= 1'b0;

                // UART/SPI
				uartsend <= 1'b0;
				uartbyte <= 8'd0;
				fifore <= 1'b0;
    			spisend <= 1'b0;
    			spioutput <= 8'd0;
    			
    			// Instruction cache
				ICACHEADDR <= 27'hF; 			// Invalid cache address
				ICACHECOUNTER <= 6'd0;
				
				// NOTE: Not clearing instruction cache for now
				//ICACHE[ 0] <= 16'h0000;	// 0x00  -> 0x0
				//ICACHE[ 1] <= 16'h0000;	// 0x02  -> 0x1
				//ICACHE[ 2] <= 16'h0000;	// 0x04  -> 0x2
				//ICACHE[ 3] <= 16'h0000;	// 0x06  -> 0x3
				//ICACHE[ 4] <= 16'h0000;	// 0x08  -> 0x4
				//ICACHE[ 5] <= 16'h0000;	// 0x0A  -> 0x5
				//ICACHE[ 6] <= 16'h0000;	// 0x0C  -> 0x6
				//ICACHE[ 7] <= 16'h0000;	// 0x0E  -> 0x7
				//ICACHE[ 8] <= 16'h0000;	// 0x10  -> 0x8
				//ICACHE[ 9] <= 16'h0000;	// 0x12  -> 0x9
				//ICACHE[10] <= 16'h0000;	// 0x14  -> 0xA
				//ICACHE[11] <= 16'h0000;	// 0x16  -> 0xB
				//ICACHE[12] <= 16'h0000;	// 0x18  -> 0xC
				//ICACHE[13] <= 16'h0000;	// 0x1A  -> 0xD
				//ICACHE[14] <= 16'h0000;	// 0x1C  -> 0xE
				//ICACHE[15] <= 16'h0000;	// 0x1E  -> 0xF
				// TODO: Spare for misaligned instructions
				//ICACHE[16] <= 16'h0000;
				//ICACHE[17] <= 16'h0000;

				cpustate[CPUFETCH] <= 1'b1;
			end
			
			cpustate[CPUFETCH] : begin
				if (icachenotmissed) begin // Still in instruction cache?
					if (alustall) begin
						cpustate[CPUSTALL] <= 1'b1;
					end else begin
						// Use the (raw or decompressed) instruction from the current cache address
						case(opcode)
							`OPCODE_AUPC: begin
								wren <= 1'b1;
								data <= incrementedbyimmpc;
								nextPC <= incrementedpc;
								cpustate[CPURETIREINSTRUCTION] <= 1'b1;
							end
							`OPCODE_LUI: begin
								wren <= 1'b1;
								data <= imm;
								nextPC <= incrementedpc;
								cpustate[CPURETIREINSTRUCTION] <= 1'b1;
							end
							`OPCODE_JAL: begin
								wren <= 1'b1;
								data <= incrementedpc;
								nextPC <= incrementedbyimmpc;
								cpustate[CPURETIREINSTRUCTION] <= 1'b1;
							end
							default: begin
								cpustate[CPUEXEC] <= 1'b1;
							end
						endcase
					end
				end else begin
					memaddress <= {PC[31:5], 5'b00000}; // Set load address to top of the cache page
					chipselect <= 1'b0;
					ICACHECOUNTER <= 5'd0;
					cpustate[CPUCACHEFILLWAIT] <= 1'b1; // Jump to read delay stages (block RAM has 1 cycle latency for read)
				end
			end
			
			cpustate[CPUSTALL]: begin
				if (~alustall) begin
					cpustate[CPUEXEC] <= 1'b1;
				end else begin
					cpustate[CPUSTALL] <= 1'b1;
				end
			end

			cpustate[CPUCACHEFILLWAIT]: begin
				// Step address by 4 bytes for next read
				memaddress <= memaddress + 32'd4;
				// Loop around
				cpustate[CPUICACHEFILL] <= 1'b1;
			end

			// This will loop until the instruction cache is full, reading 1 32bit word at a time and writing it into two 16bit locations
			// The 16bit split makes it easy for cases where there might be compressed instructions
			// NOTE: Perhaps needs 2x16bit padding to cope with odd number of 16bit words covering full+compressed instruction sequences
			// so that we don't get cut halfway when accessing a 32bit instruction  
			cpustate[CPUICACHEFILL]: begin
				if (ICACHECOUNTER == 5'd10) begin // Done filling the cache (0 to 8 inclusive for [0:17] entries) - NOTE: need to spin an extra clock to finish last read
					// Remember the new page address
					ICACHEADDR <= PC[31:5];
					// When done, loop back to FETCH so it can populate the instr
					cpustate[CPUFETCH] <= 1'b1;
				end else begin
					// Load previous item to cache
					ICACHE[{ICACHECOUNTER[3:0],1'b0}] <= mem_data[15:0]; // Store entry at ICACHECOUNTER*2+0 and ICACHECOUNTER*2+1
					ICACHE[{ICACHECOUNTER[3:0],1'b1}] <= mem_data[31:16];
					// Point at next slot to write
					ICACHECOUNTER <= ICACHECOUNTER + 5'd1;
					// Step address by 4 bytes for next read
					memaddress <= memaddress + 32'd4;
					// Loop around
					cpustate[CPUICACHEFILL] <= 1'b1; // CPUCACHEFILLWAIT?
				end
			end
			
			cpustate[CPUEXEC] : begin
			    floatmemop <= 1'b0;
				case (opcode)
					`OPCODE_OP, `OPCODE_OP_IMM: begin
						wren <= 1'b1;
						data <= aluout;
						nextPC <= incrementedpc;
						cpustate[CPURETIREINSTRUCTION] <= 1'b1;
					end
					`OPCODE_LOAD: begin
						memaddress <= rval1plusimm;
						chipselect <= 1'b0;
						nextPC <= incrementedpc;
						cpustate[CPULOADWAIT] <= 1'b1;
					end
					`OPCODE_FLOAT_LD: begin
						memaddress <= rval1plusimm;
						chipselect <= 1'b0;
						nextPC <= incrementedpc;
						floatmemop <= 1'b1;
						cpustate[CPULOADWAIT] <= 1'b1;
					end
					`OPCODE_STORE: begin
						data <= rval2;
						memaddress <= rval1plusimm;
						nextPC <= incrementedpc;
						cpustate[CPUSTORE] <= 1'b1;
					end
					`OPCODE_FLOAT_ST: begin
						data <= frval2;
						memaddress <= rval1plusimm;
						floatmemop <= 1'b1;
						nextPC <= incrementedpc;
						cpustate[CPUSTORE] <= 1'b1;
					end
					`OPCODE_JALR: begin
						wren <= 1'b1;
						data <= incrementedpc;
						nextPC <= rval1plusimm;
						cpustate[CPURETIREINSTRUCTION] <= 1'b1;
					end
					`OPCODE_BRANCH: begin
						nextPC <= aluout[0] ? incrementedbyimmpc : incrementedpc;
						cpustate[CPURETIREINSTRUCTION] <= 1'b1;
					end
					`OPCODE_FLOAT_OP: begin
						fwren <= 1'b1;
						data <= faluout;
						nextPC <= incrementedpc;
						cpustate[CPURETIREINSTRUCTION] <= 1'b1;
                    end
					default: begin
						// These are illegal / unhandled or non-op instructions, jump back to reset vector
						nextPC <= 32'h000FA00;
						cpustate[CPUFETCH] <= 1'b1;
					end
				endcase
			end
			
			cpustate[CPULOADWAIT]: begin
				case (memaddress[31:28])
					4'b0011: begin // 0x30000000: SPI IN
						if (spiinputready) begin
							wren <= 1'b1;
							data <= {21'd0, spiinput};
							cpustate[CPURETIREINSTRUCTION] <= 1'b1;
						end else begin
							cpustate[CPULOADWAIT] <= 1'b1;
						end
					end
					4'b0110: begin // 0x60000000: UART OUT - STATUS:Receive counter
						wren <= 1'b1;
						data <= {21'd0, fifodatacount};
						cpustate[CPURETIREINSTRUCTION] <= 1'b1;
					end
					4'b0101: begin // 0x50000000: UART IN
						fifore <= 1'b1; // Switch to read from UART FIFO
						cpustate[CPUUARTREAD] <= 1'b1;
					end
					default: begin  
						// 0x80000000 or other address combinations
						// stay in wait state for memory reads to complete
						cpustate[CPULOADCOMPLETE] <= 1'b1;
					end
				endcase
			end

			cpustate[CPUUARTREAD]: begin
				// Wait until data is in 'valid' state
				if (fifovalid) begin
					fifore <= 1'b0;
					wren <= 1'b1;
					data <= {24'd0, fifoout};
					cpustate[CPURETIREINSTRUCTION] <= 1'b1;
				end else begin
					cpustate[CPUUARTREAD] <= 1'b1; // Loop for one more clock
				end
			end

			cpustate[CPULOADCOMPLETE]: begin
				if (floatmemop == 1'b1) begin
                    data <= mem_data[31:0];
                    fwren <= 1'b1;
				end else begin
                    case (func3) // lb:000 lh:001 lw:010 lbu:100 lhu:101
                        3'b000: begin
                            // Byte alignment based on {address[1:0]} with sign extension
                            case (memaddress[1:0]) // synthesis full_case
                                2'b11: begin data <= {{24{mem_data[31]}},mem_data[31:24]}; end
                                2'b10: begin data <= {{24{mem_data[23]}},mem_data[23:16]}; end
                                2'b01: begin data <= {{24{mem_data[15]}},mem_data[15:8]}; end
                                2'b00: begin data <= {{24{mem_data[7]}},mem_data[7:0]}; end
                            endcase
                        end
                        3'b001: begin
                            // short alignment based on {address[1],1'b0} with sign extension
                            case (memaddress[1]) // synthesis full_case
                                1'b1: begin data <= {{16{mem_data[31]}},mem_data[31:16]}; end
                                1'b0: begin data <= {{16{mem_data[15]}},mem_data[15:0]}; end
                            endcase
                        end
                        3'b010: begin
                            // Already aligned on read, regular DWORD read
                            data <= mem_data[31:0];
                        end
                        3'b100: begin
                            // Byte alignment based on {address[1:0]} with zero extension
                            case (memaddress[1:0]) // synthesis full_case
                                2'b11: begin data <= {24'd0, mem_data[31:24]}; end
                                2'b10: begin data <= {24'd0, mem_data[23:16]}; end
                                2'b01: begin data <= {24'd0, mem_data[15:8]}; end
                                2'b00: begin data <= {24'd0, mem_data[7:0]}; end
                            endcase
                        end
                        3'b101: begin
                            // short alignment based on {address[1],1'b0} with zero extension
                            case (memaddress[1]) // synthesis full_case
                                1'b1: begin data <= {16'd0,mem_data[31:16]}; end
                                1'b0: begin data <= {16'd0,mem_data[15:0]}; end
                            endcase
                        end
                        default: begin
                            // undefined mem op, TODO: Do we throw an exception, or just ignore it? Check specs.
                        end
                    endcase
                    wren <= 1'b1;
                end

				cpustate[CPURETIREINSTRUCTION] <= 1'b1;
			end
			
			cpustate[CPUSTORE]: begin
			    if (floatmemop == 1'b1) begin
                    cpustate[CPURETIREINSTRUCTION] <= 1'b1;
                    chipselect <= memaddress[31];
                    mem_writeena <= 4'b1111;
                    writeword <= data;
                end else begin
                    if (memaddress[31:28] == 4'b0100) begin // 0x40000000: UART OUT
                        if (~uarttxbusy) begin
                            uartbyte <= rval2[7:0]; // Always send lower byte only
                            uartsend <= 1'b1;
                            cpustate[CPURETIREINSTRUCTION] <= 1'b1;
                        end else begin
                            cpustate[CPUSTORE] <= 1'b1; // Loop for one more clock
                        end
                    end else if (memaddress[31:28] == 4'b0010) begin // 0x20000000: SPI OUT
                        if (sdtxready) begin
                            spioutput <= rval2[7:0]; // Always send lower byte only
                            spisend <= 1'b1;
                            cpustate[CPURETIREINSTRUCTION] <= 1'b1;
                        end else begin
                            cpustate[CPUSTORE] <= 1'b1; // Loop for one more clock until we can write
                        end
                    end else begin
                        cpustate[CPURETIREINSTRUCTION] <= 1'b1;
                        chipselect <= memaddress[31]; // 0x80000000: VRAM OUTPUT, other addresses are SYSRAM addresses
                        case (func3)
                            // Byte
                            3'b000: begin
                                case (memaddress[1:0]) // synthesis full_case
                                    2'b11: begin mem_writeena <= 4'b1000; writeword <= {data[7:0], 24'd0}; end
                                    2'b10: begin mem_writeena <= 4'b0100; writeword <= {8'd0, data[7:0], 16'd0}; end
                                    2'b01: begin mem_writeena <= 4'b0010; writeword <= {16'd0, data[7:0], 8'd0}; end
                                    2'b00: begin mem_writeena <= 4'b0001; writeword <= {24'd0, data[7:0]}; end
                                endcase
                            end
                            // Short
                            3'b001: begin
                                case (memaddress[1]) // synthesis full_case
                                    1'b1: begin mem_writeena <= 4'b1100; writeword <= {data[15:0], 16'd0}; end
                                    1'b0: begin mem_writeena <= 4'b0011; writeword <= {16'd0, data[15:0]}; end
                                endcase
                            end
                            // Word
                            default: begin
                                mem_writeena <= 4'b1111; writeword <= data;
                            end
                        endcase
                    end
				end
			end

			cpustate[CPURETIREINSTRUCTION]: begin
				wren <= 1'b0;
				fwren <= 1'b0;
				mem_writeena <= 4'b0000;
				PC <= {nextPC[31:1],1'b0}; // Truncate to 16bit addresses to align to instructions
				uartsend <= 1'b0;
				spisend <= 1'b0;
				cpustate[CPUFETCH] <= 1'b1;
			end

			default : begin
				cpustate[CPUSTALL] <= 1'b1;
			end
		endcase
	end
end

endmodule
