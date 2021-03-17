# ecrv32
A simple RISC-V implementation (model: rv32imc)

Current version, when synthesized/implemented, runs at 100Mhz on an Arty S7-25 FPGA board at 3 clocks per instructions on average.

# Prerequisites

Hardware / Software:
- Vivado 2020.2
- Digilent Arty S7-25 FGPA board (or pin/part compatible) board
- Digilent microSD PMOD connected to slot A (optional)
- Digilent VGA output PMOD connected to slots B&C (optional)
- The riscv-tool utility from https://github.com/ecilasun/riscvtool to be able to upload your own executables over USB UART
- Visual Studio Code to develop your own ELF executables (based on samples from riscvtool project)

# Features
- SD Card reading
- VGA video output at 256x192x8bpp resolution (60Hz)
- RISC-V with base integer, mul/div/rem and compressed instruction support
- 32x16bits instruction cache
- No data cache
- Memory mapped peripheral access (UART/SDCard)
- 3 clocks per instruction on average
- Not pipelined

NOTE: Documentation is in progress, more detail will follow briefly.
