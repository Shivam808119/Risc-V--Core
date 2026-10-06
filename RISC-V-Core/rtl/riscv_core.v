// =====================================================================
//  Single-cycle RISC-V core: RV32I (word loads/stores) + M extension
//  Supports: add, sub, mul, div, rem (and all their variants),
//            logic, shifts, compare, branches, jumps, lw/sw, lui/auipc
//  Files: this file holds all modules. Top module = riscv_core
// =====================================================================

// ---------------------------------------------------------------------
// ALU: all basic arithmetic (add, sub, mul, div, rem) + logic + shifts
// ---------------------------------------------------------------------
module alu (
    input  [31:0] a,
    input  [31:0] b,
    input  [4:0]  op,
    output reg [31:0] y
);
    localparam ADD    = 5'd0,  SUB    = 5'd1,  SLL   = 5'd2,  SLT   = 5'd3,
               SLTU   = 5'd4,  XOR_   = 5'd5,  SRL   = 5'd6,  SRA   = 5'd7,
               OR_    = 5'd8,  AND_   = 5'd9,  MUL   = 5'd10, MULH  = 5'd11,
               MULHSU = 5'd12, MULHU  = 5'd13, DIV   = 5'd14, DIVU  = 5'd15,
               REM    = 5'd16, REMU   = 5'd17;

    // Multiplier products (full 64-bit results)
    wire signed [63:0] p_ss = $signed(a) * $signed(b);
    wire signed [32:0] a33  = {a[31], a};
    wire signed [32:0] b33u = {1'b0, b};
    wire signed [65:0] p_su = a33 * b33u;
    wire        [63:0] p_uu = a * b;

    wire signed [31:0] sa = a;
    wire signed [31:0] sb = b;

    always @(*) begin
        case (op)
            ADD:    y = a + b;
            SUB:    y = a - b;
            SLL:    y = a << b[4:0];
            SLT:    y = (sa < sb) ? 32'd1 : 32'd0;
            SLTU:   y = (a < b)   ? 32'd1 : 32'd0;
            XOR_:   y = a ^ b;
            SRL:    y = a >> b[4:0];
            SRA:    y = sa >>> b[4:0];
            OR_:    y = a | b;
            AND_:   y = a & b;
            MUL:    y = p_uu[31:0];
            MULH:   y = p_ss[63:32];
            MULHSU: y = p_su[63:32];
            MULHU:  y = p_uu[63:32];
            // Division follows the RISC-V spec for corner cases:
            //   x / 0 = all ones, x % 0 = x, INT_MIN / -1 = INT_MIN, INT_MIN % -1 = 0
            DIV:    y = (b == 32'd0) ? 32'hFFFFFFFF :
                        (a == 32'h80000000 && b == 32'hFFFFFFFF) ? a :
                        (sa / sb);
            DIVU:   y = (b == 32'd0) ? 32'hFFFFFFFF : (a / b);
            REM:    y = (b == 32'd0) ? a :
                        (a == 32'h80000000 && b == 32'hFFFFFFFF) ? 32'd0 :
                        (sa % sb);
            REMU:   y = (b == 32'd0) ? a : (a % b);
            default: y = 32'd0;
        endcase
    end
endmodule

// ---------------------------------------------------------------------
// Register file: 32 x 32-bit, two read ports, one write port, x0 = 0
// ---------------------------------------------------------------------
module regfile (
    input         clk,
    input         we,
    input  [4:0]  ra1,
    input  [4:0]  ra2,
    input  [4:0]  wa,
    input  [31:0] wd,
    output [31:0] rd1,
    output [31:0] rd2
);
    reg [31:0] regs [0:31];
    integer i;
    initial for (i = 0; i < 32; i = i + 1) regs[i] = 32'd0;

    assign rd1 = (ra1 == 5'd0) ? 32'd0 : regs[ra1];
    assign rd2 = (ra2 == 5'd0) ? 32'd0 : regs[ra2];

    always @(posedge clk)
        if (we && wa != 5'd0) regs[wa] <= wd;
endmodule

// ---------------------------------------------------------------------
// Instruction memory (read-only, loaded from program.hex)
// ---------------------------------------------------------------------
module imem (
    input  [31:0] addr,
    output [31:0] instr
);
    reg [31:0] mem [0:255];
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) mem[i] = 32'h00000013; // NOP (addi x0,x0,0)
        $readmemh("program.hex", mem);
    end
    assign instr = mem[addr[9:2]];
endmodule

// ---------------------------------------------------------------------
// Data memory (word access, synchronous write, combinational read)
// ---------------------------------------------------------------------
module dmem (
    input         clk,
    input         we,
    input  [31:0] addr,
    input  [31:0] wd,
    output [31:0] rd
);
    reg [31:0] mem [0:255];
    integer i;
    initial for (i = 0; i < 256; i = i + 1) mem[i] = 32'd0;

    assign rd = mem[addr[9:2]];
    always @(posedge clk) if (we) mem[addr[9:2]] <= wd;
endmodule

// ---------------------------------------------------------------------
// Top-level core: PC, decode, control, datapath
// ---------------------------------------------------------------------
module riscv_core (
    input clk,
    input reset
);
    // opcodes
    localparam OP_R     = 7'b0110011,
               OP_I     = 7'b0010011,
               OP_LOAD  = 7'b0000011,
               OP_STORE = 7'b0100011,
               OP_BR    = 7'b1100011,
               OP_JAL   = 7'b1101111,
               OP_JALR  = 7'b1100111,
               OP_LUI   = 7'b0110111,
               OP_AUIPC = 7'b0010111;

    // ---- Fetch ----
    reg  [31:0] pc;
    wire [31:0] instr;
    imem u_imem (.addr(pc), .instr(instr));

    // ---- Decode ----
    wire [6:0] opcode = instr[6:0];
    wire [4:0] rd     = instr[11:7];
    wire [2:0] funct3 = instr[14:12];
    wire [4:0] rs1    = instr[19:15];
    wire [4:0] rs2    = instr[24:20];
    wire [6:0] funct7 = instr[31:25];

    // Immediate generation
    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    // ---- Control signals ----
    reg        reg_we, mem_we, use_imm, is_branch, is_jal, is_jalr;
    reg  [1:0] wb_sel;      // 0=ALU, 1=load data, 2=PC+4, 3=imm/auipc value
    reg  [4:0] alu_op;
    reg  [31:0] imm;

    always @(*) begin
        reg_we = 0; mem_we = 0; use_imm = 0; is_branch = 0;
        is_jal = 0; is_jalr = 0; wb_sel = 2'd0; alu_op = 5'd0; imm = imm_i;

        case (opcode)
            OP_R: begin
                reg_we = 1;
                if (funct7 == 7'b0000001)
                    alu_op = 5'd10 + {2'b00, funct3};          // M extension
                else case (funct3)
                    3'b000: alu_op = funct7[5] ? 5'd1 : 5'd0;  // SUB / ADD
                    3'b001: alu_op = 5'd2;                     // SLL
                    3'b010: alu_op = 5'd3;                     // SLT
                    3'b011: alu_op = 5'd4;                     // SLTU
                    3'b100: alu_op = 5'd5;                     // XOR
                    3'b101: alu_op = funct7[5] ? 5'd7 : 5'd6;  // SRA / SRL
                    3'b110: alu_op = 5'd8;                     // OR
                    3'b111: alu_op = 5'd9;                     // AND
                endcase
            end
            OP_I: begin
                reg_we = 1; use_imm = 1; imm = imm_i;
                case (funct3)
                    3'b000: alu_op = 5'd0;                     // ADDI
                    3'b001: alu_op = 5'd2;                     // SLLI
                    3'b010: alu_op = 5'd3;                     // SLTI
                    3'b011: alu_op = 5'd4;                     // SLTIU
                    3'b100: alu_op = 5'd5;                     // XORI
                    3'b101: alu_op = funct7[5] ? 5'd7 : 5'd6;  // SRAI / SRLI
                    3'b110: alu_op = 5'd8;                     // ORI
                    3'b111: alu_op = 5'd9;                     // ANDI
                endcase
            end
            OP_LOAD:  begin reg_we = 1; use_imm = 1; imm = imm_i; wb_sel = 2'd1; end
            OP_STORE: begin mem_we = 1; use_imm = 1; imm = imm_s; end
            OP_BR:    begin is_branch = 1; imm = imm_b; end
            OP_JAL:   begin reg_we = 1; is_jal = 1;  imm = imm_j; wb_sel = 2'd2; end
            OP_JALR:  begin reg_we = 1; is_jalr = 1; use_imm = 1; imm = imm_i; wb_sel = 2'd2; end
            OP_LUI:   begin reg_we = 1; imm = imm_u; wb_sel = 2'd3; end
            OP_AUIPC: begin reg_we = 1; imm = imm_u; wb_sel = 2'd3; end
            default: ;
        endcase
    end

    // ---- Register file ----
    wire [31:0] rd1, rd2;
    reg  [31:0] wb_data;
    regfile u_rf (
        .clk(clk), .we(reg_we),
        .ra1(rs1), .ra2(rs2), .wa(rd), .wd(wb_data),
        .rd1(rd1), .rd2(rd2)
    );

    // ---- Execute ----
    wire [31:0] alu_b = use_imm ? imm : rd2;
    wire [31:0] alu_y;
    alu u_alu (.a(rd1), .b(alu_b), .op(alu_op), .y(alu_y));

    // Branch comparison
    wire signed [31:0] s1 = rd1;
    wire signed [31:0] s2 = rd2;
    reg take_branch;
    always @(*) begin
        case (funct3)
            3'b000: take_branch = (rd1 == rd2);   // BEQ
            3'b001: take_branch = (rd1 != rd2);   // BNE
            3'b100: take_branch = (s1 <  s2);     // BLT
            3'b101: take_branch = (s1 >= s2);     // BGE
            3'b110: take_branch = (rd1 <  rd2);   // BLTU
            3'b111: take_branch = (rd1 >= rd2);   // BGEU
            default: take_branch = 1'b0;
        endcase
    end

    // ---- Memory ----
    wire [31:0] load_data;
    dmem u_dmem (.clk(clk), .we(mem_we), .addr(alu_y), .wd(rd2), .rd(load_data));

    // ---- Write-back ----
    always @(*) begin
        case (wb_sel)
            2'd0: wb_data = alu_y;
            2'd1: wb_data = load_data;
            2'd2: wb_data = pc + 32'd4;
            2'd3: wb_data = (opcode == OP_AUIPC) ? (pc + imm) : imm;
        endcase
    end

    // ---- Next PC ----
    wire [31:0] pc_plus4 = pc + 32'd4;
    wire [31:0] next_pc =
        is_jalr                    ? ((rd1 + imm) & 32'hFFFFFFFE) :
        is_jal                     ? (pc + imm) :
        (is_branch && take_branch) ? (pc + imm) :
                                     pc_plus4;

    always @(posedge clk or posedge reset)
        if (reset) pc <= 32'd0;
        else       pc <= next_pc;
endmodule
