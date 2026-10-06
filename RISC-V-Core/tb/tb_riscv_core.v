`timescale 1ns/1ps
// Self-checking testbench for riscv_core.
// Program (program.hex):
//   x1 = 20; x2 = 6
//   x3 = x1 + x2        -> 26
//   x4 = x1 - x2        -> 14
//   x5 = x1 * x2        -> 120
//   x6 = x1 / x2        -> 3
//   x7 = x1 % x2        -> 2
//   sw x3 -> mem[0]; lw x8 <- mem[0]  -> 26
//   x9 = x8 + x7        -> 28
//   x10 = x1 / 0        -> -1 (RISC-V rule for divide by zero)
module tb_riscv_core;
    reg clk = 0;
    reg reset = 1;
    integer errors = 0;

    riscv_core dut (.clk(clk), .reset(reset));

    always #5 clk = ~clk;   // 100 MHz

    task check(input [4:0] r, input [31:0] expected);
        begin
            if (dut.u_rf.regs[r] !== expected) begin
                $display("FAIL: x%0d = %0d, expected %0d", r, $signed(dut.u_rf.regs[r]), $signed(expected));
                errors = errors + 1;
            end else
                $display("PASS: x%0d = %0d", r, $signed(dut.u_rf.regs[r]));
        end
    endtask

    initial begin
        $dumpfile("core.vcd");
        $dumpvars(0, tb_riscv_core);
        #12 reset = 0;
        #200;                       // plenty of cycles for 11 instructions
        check(1,  32'd20);
        check(2,  32'd6);
        check(3,  32'd26);
        check(4,  32'd14);
        check(5,  32'd120);
        check(6,  32'd3);
        check(7,  32'd2);
        check(8,  32'd26);
        check(9,  32'd28);
        check(10, 32'hFFFFFFFF);
        if (errors == 0) $display("\nALL TESTS PASSED");
        else             $display("\n%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule
