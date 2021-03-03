# ecrv32
A simple RISC-V implementation (model: rv32imc)

Current version, when synthesized/implemented, runs at 100Mhz on an Arty S7-25 FPGA board at 3 clocks per instructions on average.

# Prerequisites

Hardware / Software:
- Vivado 2020.2
- Digilent Arty S7-25 FGPA board (or pin/part compatible) board
- Digilent VGA output PMOD connected to the center two PMOD port (optional)
- The riscv-tool utility from https://github.com/ecilasun/riscvtool to be able to upload your own executables (uses the USB UART, no extra cables required)

NOTE: Documentation is in progress, a lot more detail will follow briefly.
