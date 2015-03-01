`timescale 1ps/1ps

//
// This is an inefficient implementation.
//   make it run correctly in less cycles, fastest implementation wins
//

//
// States:
//

// Fetch
`define F0 0
`define F1 1
`define F2 2

// decode
`define D0 3

// load
`define L0 4
`define L1 5
`define L2 6

// write-back
`define WB 7

// regs
`define R0 8
`define R1 9

// execute
`define EXEC 10

// halt
`define HALT 15

module main();

    initial begin
        $dumpfile("cpu.vcd");
        $dumpvars(1,main);
    end

    // clock
    wire clk;
    clock c0(clk);

    counter ctr((state == `HALT),clk,(state == `F1),cycle);

    reg [3:0]state = `F0;

    // PC
    reg [15:0]pc = 16'h0000;

    // fetch 
    wire [15:0]memOut;
    wire [15:0]memIn = (state == `F0) ? pc :
                       (state == `L0) ? res :
                       16'hxxxx;


    mem i0(clk,
       // read port #0
       memIn,memOut,

       // read port #1
       ,,

       // write port
       (state == `EXEC) & (opcode == 7),
       {8'h0, inst[7:0]},
       va
    );

    reg [15:0]inst;

    // decode
    wire [3:0]opcode = inst[15:12];
    wire [3:0]ra = inst[11:8];
    wire [3:0]rb = inst[7:4];
    wire [3:0]rt = inst[3:0];
    wire [15:0]jjj = inst[11:0]; // zero-extended
    wire [15:0]ii = inst[11:4]; // zero-extended

    wire [15:0]va;
    wire [15:0]vb;

    reg [15:0]res; // what to write in the register file

    // registers
    regs rf(clk,
        (state == `R0), ra, va,
        (state == `R0), rb, vb, 
        (state == `WB), rt, res);

    always @(posedge clk) begin
        case(state)
        `F0: begin
            state <= `F1;
        end
        `F1: begin
            state <= `F2;
        end
        `F2: begin
            state <= `D0;
            inst <= memOut;
        end
        `D0: begin
            case(opcode)
            4'h0 : begin // mov
                res <= ii;
                state <= `WB;
            end
            4'h1 : begin // add
                state <= `R0;
            end
            4'h2 : begin // jmp
                pc <= jjj;
                state <= `F0;
            end
            4'h3 : begin // halt
                state <= `HALT;
            end
            4'h4 : begin // ld
                res <= ii;
                state <= `L0;
            end
            4'h5 : begin // ldr
                state <= `R0;
            end
            4'h6 : begin // jeq
                state <= `R0;
            end
            4'h7 : begin // st
                state <= `R0;
            end
            default: begin
                $display("unknown inst %x @ %x",inst,pc);
                pc <= pc + 1;
                state <= `F0;
            end
            endcase        
        end
        `WB: begin
            pc <= pc + 1;
            state <= `F0;
        end
        `L0: begin
            state <= `L1;
        end
        `L1: begin
            state <= `L2;
        end
        `L2: begin
            res <= memOut;
            state <= `WB;
        end
        `R0: begin
            state <= `R1;
        end
        `R1: begin
            state <= `EXEC;
        end
        `EXEC : begin
            case (opcode)
                4'h1 : begin // add
                    res <= va + vb;
                    state <= `WB;
                end
                4'h5 : begin // ldr
                    res <= va + vb;
                    state <= `L0;
                end
                4'h6 : begin // jeq
                    pc <= pc + ((va == vb) ? inst[3:0] : 1);
                    state <= `F0;
                end
                4'h7 : begin // st
                    pc <= pc + 1;
                    state <= `F0;
                end
               
                default: begin
                    $display("invalid opcode in exec %d",opcode);
                    $finish;
                end
            endcase
        end
        `HALT: begin
        end
        default: begin
            $display("unknown state %d",state);
            $finish;
        end
        endcase
    end

endmodule
