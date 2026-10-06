# All Working outline

A ready-made plan for a 10 to 15 minute talk about this core. Each slide names the diagram to use (all are in `docs/images/`, and you can paste an SVG straight into PowerPoint or Google Slides, or open it in a browser and take a screenshot).

| # | Slide title | What to say | Image |
|---|---|---|---|
| 1 | **Title** | Project name, your name, one sentence: "A single-cycle 32-bit RISC-V CPU core in Verilog that does add, subtract, multiply and divide." | - |
| 2 | **Goal** | Build a small CPU from scratch to learn how a processor works, and make it do all basic arithmetic. | - |
| 3 | **What is RISC-V?** | An open, free instruction set. Simple, clean, used in education and industry. We implement RV32I plus the M extension. | - |
| 4 | **From idea to chip** | Eight stages. This project covers the first four. The rest are the next steps. | `design-flow.svg` |
| 5 | **Architecture** | The blocks: PC, instruction memory, decoder, registers, ALU, data memory, next-PC logic. Follow one instruction through. | `datapath.svg` |
| 6 | **One clock cycle** | Fetch, decode, execute, memory, write-back, all in one cycle. Why it is simple and why it is slow. | `cycle-flow.svg` |
| 7 | **Instruction formats** | Every instruction is 32 bits. The decoder cuts out the fields: opcode, registers, immediate. | `instruction-formats.svg` |
| 8 | **The ALU** | The calculator. Add, subtract, multiply, divide, remainder, logic, shifts, compares. Mention divide-by-zero handling. | `alu-ops.svg` |
| 9 | **Registers and memory** | 32 registers, `x0` is always zero. Separate instruction and data memory. | `register-file.svg`, `modules.svg` |
| 10 | **Demo: the test program** | Walk through the 12 instructions and the results (26, 14, 120, 3, 2...). | `program-trace.svg` |
| 11 | **Simulation results** | Show the terminal output (`ALL TESTS PASSED`) and a GTKWave screenshot with the PC and registers changing. *Take these screenshots yourself after running it.* | your screenshots |
| 12 | **Limitations and next steps** | Word-only memory, no interrupts, slow single-cycle divide. Next: byte loads and stores, multi-cycle divider, pipeline, run on an FPGA. | - |
| 13 | **Questions** | See the list below. | - |

## Questions you may be asked, and short answers

**Why single cycle?**
It is the simplest design to build and explain. Each instruction does everything in one clock, so there are no pipeline hazards. The cost is a slower clock.

**Why is it slow?**
The clock must be long enough for the slowest instruction. Multiply and especially divide take a long time to compute, and they set the clock speed for every instruction.

**What does the control unit do?**
It reads the opcode and sets signals such as `reg_we`, `mem_we`, `alu_op` and `wb_sel` that tell the other blocks what to do for this instruction.

**Why is register x0 always zero?**
The RISC-V specification requires it. It gives programs a free constant zero, which makes many instructions simpler (for example, `addi x1, x0, 20` loads the number 20).

**What happens if you divide by zero?**
The RISC-V rules say the result is all ones (-1) and the remainder is the original number. The core follows that, so it never crashes.

**How does a branch work?**
A comparator checks the two registers. If the condition is true, the next PC is `PC + immediate`. Otherwise it is `PC + 4`.

**What is the difference between simulation and a real chip?**
Simulation runs the Verilog on a computer to check behaviour. A real chip needs synthesis, place and route and sign-off. The next realistic step is an FPGA board.

**How would you make it faster?**
Use a pipeline (several instructions in flight at once) and a multi-cycle divider.

**How did you test it?**
A self-checking testbench runs a test program and compares each register against the expected value, printing PASS or FAIL.

**What is missing?**
Byte and halfword memory access, interrupts, system instructions and CSRs.
