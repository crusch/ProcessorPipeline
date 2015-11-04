
`timescale 1ps/1ps

//
// This is an inefficient implementation.
//   make it run correctly in less cycles, fastest implementation wins
//

module main();

    initial begin
        $dumpfile("cpu.vcd");
        $dumpvars(0);
    end

    //Clock
    wire clk;
    clock c0(clk);

    counter ctr(wb2_isHalt,clk, wb_isValid, );     //more ports?

    // PC
    reg [15:0]pc = 16'h0000;

    //Fetch 1
    //Time: t0
    reg f1_valid = 1;
    reg f1_jumpTaken = 0; 
    wire [15:0]f1_pc = d_isStall ? f2_pc : pc;                      //for debug only
    mem i0(clk,f1_pc,d_memOut,x1_loadAddr,wb_loadVal, wb2_memWriteEnable, wb2_memWriteAddr, wb2_writeVal);
    
    /**************************
    **Branch predictor buffer**
    **************************/
    reg [15:0]f1_predictionBuffer[4095:0];
    reg [1:0]f1_predictionHistory[4095:0];

    reg [15:0]k;
    initial begin
        for(k = 0; k < 4096; k = k + 1)
        begin
           f1_predictionBuffer[k] = 0; 
           f1_predictionHistory[k] = 0; 
        end
    end

    /*Need code to update prediction history, to get prediction history, 
    to read from prediction buffer, to write to prediction buffer*/
    
    //pretty sure these are all fine
    wire [7:0]f1_thisPcBufferAddress = f1_pc % 4096;
    wire [1:0]f1_thisPcHistory = f1_predictionHistory[f1_thisPcBufferAddress];
    wire [15:0]f1_thisPcBufferEntry = f1_predictionBuffer[f1_thisPcBufferAddress];
    wire f1_thisPcPrediction = f1_thisPcBufferEntry[f1_thisPcHistory];
    wire [15:0]f1_thisPcDest = f1_thisPcBufferEntry[15:4];

    /*************************
    ****FETCH 2 - TIME: t1***
    *************************/
    reg f2_valid = 0;
    reg [15:0]f2_pc = 0;
    reg f2_jumpTaken;

    //Decode
    //Time: t2
    reg d_valid = 0;
    reg [15:0]d_pc = 0;
    reg d_jumpTaken = 0;

    wire [15:0]d_memOut;                
    wire [15:0]wb_loadVal; 


    /*************************
    *******STALL CODE*********
    *************************/
    reg [15:0]d_prevInst = 0;
    wire [3:0]d_prevDest = d_prevInst[3:0];
    wire [3:0]d_prevOpcode = d_prevInst[15:12];
    wire d_prevWasWrite = (d_prevOpcode == 0) || (d_prevOpcode == 1) || (d_prevOpcode == 4) || (d_prevOpcode == 5);
    wire d_prevDestA = d_prevDest == d_aReg;
    wire d_prevDestB = d_prevDest == d_bReg;
    wire d_isStall = ((d_opcode == 5) && r_valid && (d_prevDestA || d_prevDestB) && d_prevWasWrite) && d_valid;

    /*************************
    *******INSTR DECODE*******
    *************************/
    wire [15:0]d_instruction = d_wasStall ? r_instruction : d_memOut;
    wire [3:0]d_opcode = d_instruction[15:12];
    wire [3:0]d_aReg = d_instruction[11:8];
    wire [3:0]d_bReg = d_instruction[7:4];
    wire [3:0]d_tReg = d_instruction[3:0];
    wire [15:0]d_jjj = d_instruction[11:0]; // zero-extended, jmp only (pc <= j)
    wire [15:0]d_ii = d_instruction[11:4]; // zero-extended, mov (write i to reg t), ld (write mem[i] to reg t) only
    wire [7:0]d_s = d_instruction[7:0];
    reg d_wasStall = 0;
    reg d_regReadEnable = 1; 

    // registers
    regs rf(clk,
        d_regReadEnable, d_aReg, x1_regOut0,
        d_regReadEnable, d_bReg, x1_regOut1, 
        wb_regWriteEnable, wb_tReg, wb_writeVal); 

    //Regs (r)
    //Time: t3
    //We are waiting for regs values.
    reg [15:0]r_pc = 0;
    reg r_valid = 0;
    reg r_jumpTaken = 0; 
    reg [15:0]r_instruction = 0;
    reg [3:0]r_opcode = 0;
    reg [3:0]r_aReg = 0;
    reg [3:0]r_bReg = 0;
    reg [3:0]r_tReg = 0;
    reg [15:0]r_jjj = 0;
    reg [15:0]r_ii = 0;    
    reg [7:0]r_s = 0;

    //Execute 1 (x1)
    //Time: t4
    reg x1_valid = 0;
    reg [15:0]x1_pc = 0;
    reg x1_jumpTaken = 0;
    wire [15:0]x1_regOut0;
    wire [15:0]x1_regOut1;

    reg [3:0]x1_aReg = 0;
    reg [3:0]x1_bReg = 0;
    wire [15:0]x1_aVal = x1_x1AHazard ? wb_writeVal : 
                         x1_rAHazard ? wb_prevWriteVal :
                         x1_dAHazard ? wb_2prevWriteVal :  x1_regOut0;      
    wire [15:0]x1_bVal = x1_x1BHazard ? wb_writeVal : 
                         x1_rBHazard ? wb_prevWriteVal :
                         x1_dBHazard ? wb_2prevWriteVal :  x1_regOut1;
    /*******************
    **R and x1 hazards**
    *******************/
    wire x1_dAHazard = wb_2prevRegWriteEnable &&
                       (wb_2prevValid) &&
                       (wb_2prevTReg == x1_aReg) &&
                       ((x1_opcode == 1) || (x1_opcode == 5) || (x1_opcode == 6) || (x1_opcode == 7));
    wire x1_dBHazard = wb_2prevRegWriteEnable &&
                       wb_2prevValid &&
                       (wb_2prevTReg == x1_bReg) &&
                       ((x1_opcode == 1) || (x1_opcode == 5) || (x1_opcode == 6));

    wire x1_rAHazard = wb_prevRegWriteEnable && 
                       (wb_prevValid) && 
                       (wb_prevTReg == x1_aReg) && 
                       ((x1_opcode == 1) || (x1_opcode == 5) || (x1_opcode == 6) || (x1_opcode == 7));
    wire x1_rBHazard = wb_prevRegWriteEnable && 
                       wb_prevValid && 
                       (wb_prevTReg == x1_bReg) && 
                       ((x1_opcode == 1) || (x1_opcode == 5) || (x1_opcode == 6));
    wire x1_x1AHazard = wb_regWriteEnable &&
                        wb_valid && (wb_tReg == x1_aReg) &&
                        ((x1_opcode == 1) || (x1_opcode == 5) || (x1_opcode == 6) || (x1_opcode == 7));
    wire x1_x1BHazard = wb_regWriteEnable &&
                        wb_valid && (wb_tReg == x1_bReg) &&
                        ((x1_opcode == 1) || (x1_opcode == 5) || (x1_opcode == 6));



    reg  [3:0]x1_tReg = 0;       //r_tReg passed to next cycle
    reg  [15:0]x1_ii = 0;
    reg  [15:0]x1_jjj = 0;
    reg  [7:0]x1_s = 0;
    reg  [3:0]x1_opcode = 0;     //d1_opcode passed to next cycle
    wire [15:0]x1_loadAddr = (x1_opcode == 4) ? x1_ii : 
                             (x1_opcode == 5) ? (x1_aVal + x1_bVal) : 0;	


    //Execute 2
    //Time: t5
    //We are waiting for load values (or wasting time if not load...)
    reg [15:0]x2_pc = 0;
    reg x2_valid = 0;
    reg x2_jumpTaken = 0; 
    reg [3:0]x2_opcode = 0;
    reg [3:0]x2_aReg = 0;
    reg [3:0]x2_bReg = 0;
    reg [15:0] x2_aVal = 0;
    reg [15:0] x2_bVal = 0;
    wire x2_aHazard = wb_regWriteEnable && 
                      (wb_tReg == x2_aReg) && 
                      ((x2_opcode == 1) || (x2_opcode == 6) || (x2_opcode == 7));
    wire x2_bHazard =  wb_regWriteEnable &&
                      (wb_tReg == x2_bReg) &&
                      ((x2_opcode == 1) || (x2_opcode == 6));


    wire x2_ldHazard = (wb_isStore) && (wb_s == x2_ii);

    reg [3:0] x2_tReg = 0;
    reg [15:0]x2_ii = 0;
    reg [15:0]x2_jjj = 0;
    reg [7:0]x2_s = 0;

    //Writeback 1
    //Time t6
    reg [15:0]wb_pc = 0;
    reg wb_valid = 0;
    reg wb_jumpTaken = 0; 
//    wire wb_isHalt = (wb_opcode == 3) && wb_valid && (!wb_jumpTakenShouldntHave);
    wire wb_isHalt = (wb_opcode == 3) && wb_valid;
//    wire wb_regWriteEnable = wb_isWrite && wb_valid && (!wb_jumpTakenShouldntHave);
    wire wb_regWriteEnable = wb_isWrite && wb_valid;
    reg [15:0]wb_aVal = 0;
    reg [15:0]wb_bVal = 0;
    reg [15:0]wb_ii = 0;
    reg [15:0]wb_jjj = 0;
    reg [7:0]wb_s = 0;
    reg [3:0]wb_opcode = 0;
    wire wb_isWrite = (wb_opcode == 0) || (wb_opcode == 1) || (wb_opcode == 4) || (wb_opcode == 5);

    reg [3:0]wb_tReg = 0;
    reg wb_x2WasLdHazard = 0;
    wire [15:0]wb_writeVal = wb_opcode == 0 ? wb_ii :
                             wb_opcode == 1 ? (wb_aVal + wb_bVal) :
                             (wb_opcode == 4 && wb_x2WasLdHazard) ? wb2_writeVal : 
                             wb_opcode == 4 ? wb_loadVal :
                             wb_opcode == 5 ? wb_loadVal : 
                             wb_opcode == 7 ? wb_aVal : 0;

    reg wb_prevRegWriteEnable = 0;
    reg [15:0]wb_prevWriteVal = 0;
    reg [3:0]wb_prevTReg = 0;
    reg wb_prevValid = 0;    
    reg wb_2prevRegWriteEnable = 0;
    reg [15:0]wb_2prevWriteVal = 0;
    reg [3:0]wb_2prevTReg = 0;
    reg wb_2prevValid = 0;

    /*****************************************************
    *************Branch prediction/recovery code**********
    *****************************************************/
    wire wb_isJmp = wb_opcode == 2;
    wire wb_isJeq = wb_opcode == 6; 
    wire wb_jmpActual = wb_valid && wb_isJmp;                           //these will be changed when i implement cache
    wire wb_jeqActual = wb_valid && (wb_aVal == wb_bVal) && wb_isJeq; 



    /*****************************************************
    ****St instruction hazards (self modifying code)******
    *****************************************************/
    wire wb_isStore = (wb_opcode == 7) && wb_valid;
    wire wb_f1PcHazard = (wb_s == f1_pc) && wb_isStore && f1_valid;
    wire wb_f2PcHazard = (wb_s == f2_pc) && wb_isStore && f2_valid;
    wire wb_dPcHazard = (wb_s == d_pc) && wb_isStore && d_valid;
    wire wb_rPcHazard = (wb_s == r_pc) && wb_isStore && r_valid;
    wire wb_x1PcHazard = (wb_s == x1_pc) && wb_isStore && x1_valid;
    wire wb_x2PcHazard = (wb_s == x2_pc) && wb_isStore && x2_valid;
    wire wb_storeHazard = wb_f1PcHazard || wb_f2PcHazard || wb_dPcHazard
                          || wb_rPcHazard || wb_x1PcHazard || wb_x2PcHazard;


    wire [1:0]wb_thisPcHistory = f1_predictionHistory[wb_pc % 4096];
    wire [15:0]wb_thisPcBufferEntry = f1_predictionBuffer[wb_pc % 4096];
    wire [1:0]wb_thisPcHistoryUpdate = (wb_thisPcHistory[0] << 1) | (wb_jmpActual | wb_jeqActual);
    wire [7:0]wb_pcBufferAddress = wb_pc % 4096;
    wire wb_jumpTakenShouldntHave = wb_jumpTaken && wb_valid && !wb_jmpActual;
    wire wb_jmpDestinationMismatch = wb_jumpTakenShouldHave && (wb_jjj != x2_pc) && wb_valid;
    wire wb_jeqDestinationMismatch = wb_jeqTakenShouldHave && ((wb_pc + wb_tReg) != x2_pc) && wb_valid;
    wire wb_jumpTakenShouldHave = wb_jmpActual && wb_isJmp && wb_jumpTaken;
    wire wb_jeqTakenShouldHave = wb_jeqActual && wb_isJeq && wb_jumpTaken;

    wire wb_jumpNotTakenShouldHave = (wb_isJmp) && wb_jmpActual && (!wb_jumpTaken) && wb_valid;
    wire wb_jeqNotTakenShouldHave = (wb_isJeq) && wb_jeqActual && (!wb_jumpTaken) && wb_valid;
    wire wb_storePcUpdate = (wb_opcode == 7) && wb_valid && wb_storeHazard;





    //Writeback 2
    //Time t7
    //for str instruction only
    reg wb2_valid  = 0;
    wire wb2_memWriteEnable = (wb2_opcode == 7) && wb2_valid;
    reg [3:0]wb2_opcode = 0;
    reg [7:0]wb2_s = 0;
    reg [15:0]wb2_writeVal = 0; 
    wire [15:0]wb2_memWriteAddr = wb2_s;
    reg wb2_isHalt = 0;

    always @(posedge clk) begin
        wb_prevRegWriteEnable <= wb_regWriteEnable;
        wb_prevWriteVal <= wb_writeVal;
        wb_prevTReg <= wb_tReg;
        wb_prevValid <= wb_valid;
        wb_2prevRegWriteEnable <= wb_prevRegWriteEnable;
        wb_2prevWriteVal <= wb_prevWriteVal;
        wb_2prevTReg <= wb_prevTReg;
        wb_2prevValid <= wb_prevValid;

        wb2_isHalt <= wb_isHalt;

    d_wasStall <= d_isStall;
    r_instruction <= d_instruction;

    ////////Branch prediction code//////////////
             f1_jumpTaken <= 0; 
             f2_jumpTaken <= f1_thisPcPrediction ? 1 : f1_jumpTaken;
//             f2_jumpTaken <= f1_jumpTaken;
             d_jumpTaken <= f2_jumpTaken;
             r_jumpTaken <= d_jumpTaken;
             x1_jumpTaken <= r_jumpTaken;
             x2_jumpTaken <= x1_jumpTaken;
             wb_jumpTaken <= x2_jumpTaken; 



    ///////Pass PC along pipeline/////
            f2_pc <= d_isStall ? f2_pc : f1_pc;
            d_pc <= d_isStall ? d_pc : f2_pc;
            r_pc <= d_pc;
            x1_pc <= r_pc;
            x2_pc <= x1_pc;
            wb_pc <= x2_pc;
   ///////Pass ii, jjj, opcode along pipleline/////
            r_ii <= d_ii;
            x1_ii <= r_ii;
            x2_ii <= x1_ii;
            wb_ii <= x2_ii;
            r_jjj <= d_jjj;
            x1_jjj <= r_jjj;
            x2_jjj <= x1_jjj;
            wb_jjj <= x2_jjj;
            r_s <= d_s;
            x1_s <= r_s;
            x2_s <= x1_s;
            wb_s <= x2_s;
            wb2_s <= wb_s;
            r_opcode <= d_opcode;
            x1_opcode <= r_opcode;
            x2_opcode <= x1_opcode;
            wb_opcode <= x2_opcode;
            wb2_opcode <= wb_opcode;
            wb2_writeVal <= wb_writeVal;

   ///////Pass aVal, bVal, tReg along pipeline////////
            x2_aVal <= x1_aVal;
            x2_bVal <= x1_bVal;
            wb_aVal <= x2_aHazard ? wb_writeVal : x2_aVal;
            wb_bVal <= x2_bHazard ? wb_writeVal : x2_bVal;
            r_tReg <= d_tReg;
            x1_tReg <= r_tReg;
            x2_tReg <= x1_tReg;
            wb_tReg <= x2_tReg;
            r_aReg <= d_aReg;
            r_bReg <= d_bReg;
            x1_aReg <= r_aReg;
            x1_bReg <= r_bReg;
            x2_aReg <= x1_aReg;
            x2_bReg <= x1_bReg;
            
            wb_x2WasLdHazard <= x2_ldHazard;
            d_prevInst <= d_instruction;


             ///////////PC UPDATE/////////////

             if(wb_jumpNotTakenShouldHave)
                  pc <= wb_jjj;
             else if(wb_jumpTakenShouldntHave)
                  pc <= wb_pc + 1;
             else if(wb_jeqNotTakenShouldHave)
                  pc <= wb_pc + wb_tReg;
             else if(wb_jmpDestinationMismatch)
                  pc <= wb_jjj;
             else if(wb_jeqDestinationMismatch)
                  pc <= wb_tReg + wb_pc;
             else if(wb_storePcUpdate)
                  pc <= wb_s;
             else if(f1_thisPcPrediction)
                  pc <= f1_thisPcDest; //problem! what about pcs that are congruent but aren't jumps? then this tries to make prediction
             else if(d_isStall)
                  pc <= pc;
             else
                  pc <= pc + 1; 

             ///////////VALID BITS UPDATE//////////////
             if(!wb_valid) begin
                      f1_valid <= 1;
                      f2_valid <= f1_valid;
                      d_valid <= f2_valid;
                      r_valid <= d_isStall ? 0 : d_valid;
                      x1_valid <= r_valid;
                      x2_valid <= x1_valid;
                      wb_valid <= x2_valid;
                      wb2_valid <= wb_valid;
             end
             else if(wb_jmpDestinationMismatch || wb_jeqDestinationMismatch) begin
                       f1_valid <= 1;
                       f2_valid <= 0;
                       d_valid <= 0;
                       r_valid <= 0;
                       x1_valid <= 0;
                       x2_valid <= 0;
                       wb_valid <= 0;
                       wb2_valid <= wb_valid;
             end
             else if(wb_jumpTakenShouldntHave) begin
                       f1_valid <= 1;
                       f2_valid <= 0;
                       d_valid <= 0;
                       r_valid <= 0;
                       x1_valid <= 0;
                       x2_valid <= 0;
                       wb_valid <= 0;
                       wb2_valid <= wb_valid;
             end
             else if(wb_opcode == 2) begin
                //Actual and taken don't match
                if(wb_jumpNotTakenShouldHave) begin
                       f1_valid <= 1;
                       f2_valid <= 0;
                       d_valid <= 0;
                       r_valid <= 0;
                       x1_valid <= 0;
                       x2_valid <= 0;
                       wb_valid <= 0;
                       wb2_valid <= wb_valid;
                end
                else begin
                  f1_valid <= 1;
                  f2_valid <= f1_valid;
                  d_valid <= f2_valid;
                  r_valid <= d_isStall ? 0 : d_valid;
                  x1_valid <= r_valid;
                  x2_valid <= x1_valid;
                  wb_valid <= x2_valid;
                  wb2_valid <= wb_valid;
                end
             end
             else if(wb_opcode == 6) begin
                if(wb_jeqNotTakenShouldHave) begin
                       f1_valid <= 1;
                       f2_valid <= 0;
                       d_valid <= 0;
                       r_valid <= 0;
                       x1_valid <= 0;
                       x2_valid <= 0;
                       wb_valid <= 0;
                       wb2_valid <= wb_valid;
               end
                else begin
                  f1_valid <= 1;
                  f2_valid <= f1_valid;
                  d_valid <= f2_valid;
                  r_valid <= d_isStall ? 0 : d_valid;
                  x1_valid <= r_valid;
                  x2_valid <= x1_valid;
                  wb_valid <= x2_valid;
                  wb2_valid <= wb_valid;
                end
             end
             else if(wb_opcode == 7) begin
             
             end
             else begin
                  f1_valid <= 1;
                  f2_valid <= f1_valid;
                  d_valid <= f2_valid;
                  r_valid <= d_isStall ? 0 : d_valid;
                  x1_valid <= r_valid;
                  x2_valid <= x1_valid;
                  wb_valid <= x2_valid;
                  wb2_valid <= wb_valid;
             end
 

            if(wb_valid) begin
               if(wb_jumpTaken || wb_isJmp || wb_isJeq) begin
                      f1_predictionHistory[wb_pcBufferAddress] <= wb_thisPcHistoryUpdate;
                       f1_predictionBuffer[wb_pcBufferAddress][wb_thisPcHistory] <= wb_jmpActual;
                       f1_predictionBuffer[wb_pcBufferAddress][15:4] <= wb_jmpActual ? wb_jjj :
                                                                        wb_jeqActual ? wb_pc + wb_tReg
                                                                : f1_predictionBuffer[wb_pcBufferAddress][15:4];

               end

            case (wb_opcode)
                4'h0 : begin // mov

                end

                4'h1 : begin // add

                end

                4'h2 : begin // jmp
                   
                end 

                4'h3 : begin // halt
                end

                4'h4 : begin // ld
                end

                4'h5 : begin // ldr
                end

                4'h6 : begin //jeq
                end
                4'h7 : begin //str
                    if(wb_x2PcHazard) begin
                        wb_valid <= 0;
                        x2_valid <= 0;
                        x1_valid <= 0;
                        r_valid <= 0;
                        d_valid <= 0;
                        f2_valid <= 0;
                        wb2_valid <= wb_valid;
                    end
                    else if (wb_x1PcHazard) begin
                        x2_valid <= 0;
                        x1_valid <= 0;
                        r_valid <= 0;
                        d_valid <= 0;
                        f2_valid <= 0;
                        wb2_valid <= wb_valid;

                    end 
                    else if (wb_rPcHazard) begin
                        x1_valid <= 0;
                        r_valid <= 0;
                        d_valid <= 0;
                        f2_valid <= 0;
                        wb2_valid <= wb_valid;

                    end
                    else if (wb_dPcHazard) begin
                        r_valid <= 0;
                        d_valid <= 0;
                        f2_valid <= 0;
                        wb2_valid <= wb_valid;
                    end
                    else if (wb_f2PcHazard) begin
                        d_valid <= 0;
                        f2_valid <= 0;
                        wb2_valid <= wb_valid;

                    end
                    else if (wb_f1PcHazard) begin
                        f2_valid <= 0;
                        wb2_valid <= wb_valid;
                    end                    
                      
                    else begin
                    
                      f1_valid <= 1;
                      f2_valid <= f1_valid;
                      d_valid <= f2_valid;
                      r_valid <= d_isStall ? 0 : d_valid;
                      x1_valid <= r_valid;
                      x2_valid <= x1_valid;
                      wb_valid <= x2_valid;
                      wb2_valid <= wb_valid;

                    end
                end
                default: begin
                    $display("invalid opcode in exec %d",wb_opcode);
                    $finish;
                end
            endcase
            end

    end

endmodule
