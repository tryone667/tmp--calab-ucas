// ============================================================================
// 5-stage pipeline CPU (IF -> ID -> EX -> MEM -> WB) with a single shared
// AXI4 master port (exp15/16: soc_axi).  Same pipeline / instruction set /
// exception / CSR behaviour as the verified exp14 core; only the memory
// interface is changed:
//  - the pipeline drives "virtual" SRAM-style handshakes (inst_sram_*,
//    data_sram_*), translated at the bottom of this file into single-beat
//    AXI4 transactions (len = 0, INCR burst)
//  - instruction fetch: serialized single-outstanding reads; completed words
//    queue (depth 1) into the IF stage; redirects flush the queue and discard
//    an in-flight response when it finally arrives
//  - data access: the memory instruction stays in EX until the transaction
//    completes (read data captured in EX, carried through MEM), so older
//    memory ops always finish before younger ones issue
//  - EX data requests are arbitrated ahead of IF fetches and only one AXI
//    transaction is in flight at a time
// ============================================================================
module mycpu_top(
    input  wire        aclk,
    input  wire        aresetn,      // low active
    // AXI master read address channel
    output wire [ 3:0] arid,
    output wire [31:0] araddr,
    output wire [ 7:0] arlen,
    output wire [ 2:0] arsize,
    output wire [ 1:0] arburst,
    output wire [ 1:0] arlock,
    output wire [ 3:0] arcache,
    output wire [ 2:0] arprot,
    output wire        arvalid,
    input  wire        arready,
    // AXI master read data channel
    input  wire [ 3:0] rid,
    input  wire [31:0] rdata,
    input  wire [ 1:0] rresp,
    input  wire        rlast,
    input  wire        rvalid,
    output wire        rready,
    // AXI master write address channel
    output wire [ 3:0] awid,
    output wire [31:0] awaddr,
    output wire [ 7:0] awlen,
    output wire [ 2:0] awsize,
    output wire [ 1:0] awburst,
    output wire [ 1:0] awlock,
    output wire [ 3:0] awcache,
    output wire [ 2:0] awprot,
    output wire        awvalid,
    input  wire        awready,
    // AXI master write data channel
    output wire [ 3:0] wid,
    output wire [31:0] wdata,
    output wire [ 3:0] wstrb,
    output wire        wlast,
    output wire        wvalid,
    input  wire        wready,
    // AXI master write response channel
    input  wire [ 3:0] bid,
    input  wire [ 1:0] bresp,
    input  wire        bvalid,
    output wire        bready,
    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

// clock/reset names kept for the (unchanged) exp14 core body
wire clk = aclk;
wire resetn = aresetn;

// virtual SRAM-style interfaces between the pipeline and the AXI adapters
// (the core body is bit-for-bit the exp14 logic; adapters below translate)
wire        inst_sram_req;
wire        inst_sram_wr;
wire [ 1:0] inst_sram_size;
wire [ 3:0] inst_sram_wstrb;
wire [31:0] inst_sram_addr;
wire [31:0] inst_sram_wdata;
wire        inst_sram_addr_ok;
wire        inst_sram_data_ok;
wire [31:0] inst_sram_rdata;

wire        data_sram_req;
wire        data_sram_wr;
wire [ 1:0] data_sram_size;
wire [ 3:0] data_sram_wstrb;
wire [31:0] data_sram_addr;
wire [31:0] data_sram_wdata;
wire        data_sram_addr_ok;
wire        data_sram_data_ok;
wire [31:0] data_sram_rdata;

reg reset;
always @(posedge clk) reset <= ~resetn;

// ============ instruction fetch engine (SRAM handshake, in order) ===========
// One request may be outstanding at a time.  A completed word is parked in
// the (depth-1) if_req queue until the IF stage can accept it; npc holds the
// address of the next word to fetch.  Redirects flush IF + queue; an already
// accepted request cannot be cancelled, so its late response is discarded.
reg         if_fetch_busy;     // request accepted, awaiting data_ok
reg         if_fetch_discard;  // accepted request is on a flushed path
reg  [31:0] if_fetch_pc;       // pc of the accepted request
reg         if_req_valid;      // completed word waiting to enter IF
reg  [31:0] if_req_pc;
reg  [31:0] if_req_inst;
reg  [31:0] npc;

reg         if_valid;
reg  [31:0] if_pc;
reg  [31:0] if_inst;

wire if_fetch_issue   = !reset && !if_fetch_busy && !if_req_valid && !id_redirect;
wire if_fetch_accept  = if_fetch_issue && inst_sram_addr_ok;
wire if_fetch_dataok  = if_fetch_busy && inst_sram_data_ok;
// a redirect only takes effect when the redirecting instruction actually
// advances out of the IF/ID stage (same gate as excp_commit/ertn_commit)
wire redirect_flush   = id_redirect && id_ready_go && ex_allowin;

wire if_ready_go   = 1'b1;
wire if_allowin    = !if_valid || (if_ready_go && id_allowin);
wire if_word_to_if = if_req_valid && !id_redirect;
wire if_transfer   = if_word_to_if && if_allowin;

assign inst_sram_req    = if_fetch_issue;
assign inst_sram_wr     = 1'b0;
assign inst_sram_size   = 2'b10;
assign inst_sram_wstrb  = 4'b0000;
assign inst_sram_addr   = npc;
assign inst_sram_wdata  = 32'b0;

always @(posedge clk) begin
    if (reset) begin
        if_fetch_busy    <= 1'b0;
        if_fetch_discard <= 1'b0;
        if_fetch_pc      <= 32'h1c000000;
        if_req_valid     <= 1'b0;
        if_req_pc        <= 32'h1c000000;
        if_req_inst      <= 32'b0;
        npc              <= 32'h1c000000;
        if_valid         <= 1'b0;
        if_pc            <= 32'h1c000000;
        if_inst          <= 32'b0;
    end
    else begin
        // request accepted by the slave
        if (if_fetch_accept) begin
            if_fetch_busy    <= 1'b1;
            if_fetch_pc      <= npc;
            if_fetch_discard <= 1'b0;
        end
        // response returned (its queue write may be overridden below by a
        // simultaneous redirect flush, which is the intended behaviour)
        if (if_fetch_dataok) begin
            if_fetch_busy <= 1'b0;
            if (if_fetch_discard) begin
                if_fetch_discard <= 1'b0;
            end
            else begin
                if_req_valid <= 1'b1;
                if_req_pc    <= if_fetch_pc;
                if_req_inst  <= inst_sram_rdata;
            end
        end
        // redirect commits: IF/queue hold only wrong-path instructions
        if (redirect_flush) begin
            if_valid         <= 1'b0;
            if_req_valid     <= 1'b0;
            if_fetch_discard <= if_fetch_busy && !if_fetch_dataok;
            npc              <= redirect_target;
        end
        // IF behaves like a normal pipeline stage: whenever the current
        // instruction is accepted downstream (if_allowin) it leaves IF and
        // is replaced by the completed fetch word or a bubble -- the same
        // word is never re-presented to ID while fetch is still waiting.
        if (if_allowin) begin
            if_valid <= if_word_to_if;
            if (if_word_to_if) begin
                if_pc   <= if_req_pc;
                if_inst <= if_req_inst;
            end
        end
        // completed word consumed by IF; next fetch address = pc + 4
        if (if_transfer) begin
            if_req_valid <= 1'b0;
            npc          <= if_req_pc + 32'h4;
        end
    end
end

// =========================== ID decode (combinational) =======================
wire [ 5:0] op_31_26;
wire [ 3:0] op_25_22;
wire [ 1:0] op_21_20;
wire [ 4:0] op_19_15;
wire [ 4:0] rd;
wire [ 4:0] rj;
wire [ 4:0] rk;
wire [11:0] i12;
wire [19:0] i20;
wire [15:0] i16;
wire [25:0] i26;

wire [63:0] op_31_26_d;
wire [15:0] op_25_22_d;
wire [ 3:0] op_21_20_d;
wire [31:0] op_19_15_d;

wire        inst_add_w;
wire        inst_sub_w;
wire        inst_slt;
wire        inst_sltu;
wire        inst_nor;
wire        inst_and;
wire        inst_or;
wire        inst_xor;
wire        inst_slli_w;
wire        inst_srli_w;
wire        inst_srai_w;
wire        inst_addi_w;
wire        inst_ld_b;
wire        inst_ld_h;
wire        inst_ld_w;
wire        inst_ld_bu;
wire        inst_ld_hu;
wire        inst_st_b;
wire        inst_st_h;
wire        inst_st_w;
wire        inst_jirl;
wire        inst_b;
wire        inst_bl;
wire        inst_beq;
wire        inst_bne;
wire        inst_blt;
wire        inst_bge;
wire        inst_bltu;
wire        inst_bgeu;
wire        inst_lu12i_w;
wire        inst_pcaddu12i;
wire        inst_slti;
wire        inst_sltui;
wire        inst_andi;
wire        inst_ori;
wire        inst_xori;
wire        inst_sll_w;
wire        inst_srl_w;
wire        inst_sra_w;
wire        inst_mul_w;
wire        inst_mulh_w;
wire        inst_mulh_wu;
wire        inst_div_w;
wire        inst_div_wu;
wire        inst_mod_w;
wire        inst_mod_wu;
wire        inst_syscall;
wire        inst_ertn;
wire        inst_csrrd;
wire        inst_csrwr;
wire        inst_csrxchg;
wire        inst_brk;
wire        inst_rdcntl;
wire        inst_rdcnth;

wire        need_ui5;
wire        need_si12;
wire        need_ui12;
wire        need_si16;
wire        need_si20;
wire        need_si26;
wire        src2_is_4;

wire [21:0] alu_op;
wire        src1_is_pc;
wire        src2_is_imm;
wire        res_from_mem;
wire        dst_is_r1;
wire        gr_we;
wire        mem_we;
wire        src_reg_is_rd;
wire [ 4:0] dest;
wire [31:0] imm;
wire [31:0] br_offs;
wire [31:0] jirl_offs;

// load/store type code carried through the pipeline:
// 0 none  1 st.b  2 st.h  3 st.w  4 ld.b  5 ld.h  6 ld.w  7 ld.bu  8 ld.hu
wire [3:0] id_ls_type;

assign op_31_26  = if_inst[31:26];
assign op_25_22  = if_inst[25:22];
assign op_21_20  = if_inst[21:20];
assign op_19_15  = if_inst[19:15];

assign rd   = if_inst[ 4: 0];
assign rj   = if_inst[ 9: 5];
assign rk   = if_inst[14:10];

assign i12  = if_inst[21:10];
assign i20  = if_inst[24: 5];
assign i16  = if_inst[25:10];
assign i26  = {if_inst[ 9: 0], if_inst[25:10]};

decoder_6_64 u_dec0(.in(op_31_26 ), .out(op_31_26_d ));
decoder_4_16 u_dec1(.in(op_25_22 ), .out(op_25_22_d ));
decoder_2_4  u_dec2(.in(op_21_20 ), .out(op_21_20_d ));
decoder_5_32 u_dec3(.in(op_19_15 ), .out(op_19_15_d ));

// 3R ALU (op_31_26=0x00, op_25_22=0x00, op_21_20=01/10)
assign inst_add_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
assign inst_sub_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
assign inst_slt    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
assign inst_sltu   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
assign inst_nor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
assign inst_and    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
assign inst_or     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
assign inst_xor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
assign inst_sll_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0e];
assign inst_srl_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0f];
assign inst_sra_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h10];
assign inst_mul_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h18];
assign inst_mulh_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h19];
assign inst_mulh_wu= op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h1a];
assign inst_div_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h00];
assign inst_mod_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h01];
assign inst_div_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h02];
assign inst_mod_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h03];
assign inst_slli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
assign inst_srli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
assign inst_srai_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
// 2RI12 ALU: op_31_26 = 0x00, subop in op_25_22
assign inst_addi_w = op_31_26_d[6'h00] & op_25_22_d[4'ha];
assign inst_slti   = op_31_26_d[6'h00] & op_25_22_d[4'h8];
assign inst_sltui  = op_31_26_d[6'h00] & op_25_22_d[4'h9];
assign inst_andi   = op_31_26_d[6'h00] & op_25_22_d[4'hd];
assign inst_ori    = op_31_26_d[6'h00] & op_25_22_d[4'he];
assign inst_xori   = op_31_26_d[6'h00] & op_25_22_d[4'hf];
// load/store: op_31_26 = 0x0a, size in op_25_22
assign inst_ld_b   = op_31_26_d[6'h0a] & op_25_22_d[4'h0];
assign inst_ld_h   = op_31_26_d[6'h0a] & op_25_22_d[4'h1];
assign inst_ld_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
assign inst_ld_bu  = op_31_26_d[6'h0a] & op_25_22_d[4'h8];
assign inst_ld_hu  = op_31_26_d[6'h0a] & op_25_22_d[4'h9];
assign inst_st_b   = op_31_26_d[6'h0a] & op_25_22_d[4'h4];
assign inst_st_h   = op_31_26_d[6'h0a] & op_25_22_d[4'h5];
assign inst_st_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
// branches & jumps
assign inst_jirl   = op_31_26_d[6'h13];
assign inst_b      = op_31_26_d[6'h14];
assign inst_bl     = op_31_26_d[6'h15];
assign inst_beq    = op_31_26_d[6'h16];
assign inst_bne    = op_31_26_d[6'h17];
assign inst_blt    = op_31_26_d[6'h18];
assign inst_bge    = op_31_26_d[6'h19];
assign inst_bltu   = op_31_26_d[6'h1a];
assign inst_bgeu   = op_31_26_d[6'h1b];
// 2RI20
assign inst_lu12i_w = op_31_26_d[6'h05] & ~if_inst[25];
assign inst_pcaddu12i = op_31_26_d[6'h07] & ~if_inst[25];
// system / CSR instructions (exp12)
assign inst_syscall  = (if_inst[31:16] == 16'h002b);
assign inst_ertn     = (if_inst == 32'h06483800);
assign inst_csrrd    = (if_inst[31:26] == 6'h01) && (if_inst[ 9: 5] == 5'h00);
assign inst_csrwr    = (if_inst[31:26] == 6'h01) && (if_inst[ 9: 5] == 5'h01);
assign inst_csrxchg  = (if_inst[31:26] == 6'h01) && (|if_inst[9:5])
                     && (if_inst[ 9: 5] != 5'h01) && ~inst_ertn;
// break (exp13): opcode 0x2a, code in bits[15:0] (tests use break 0)
assign inst_brk     = (if_inst[31:16] == 16'h002a);
// rdcntvl.w/rdcntid (rk=0x18): rd <- counter[31:0], rj <- TID
// rdcntvh.w   (rk=0x19): rd <- counter[63:32], rj <- TID
assign inst_rdcntl  = (if_inst[31:15] == 17'h0) && (if_inst[14:10] == 5'b11000);
assign inst_rdcnth  = (if_inst[31:15] == 17'h0) && (if_inst[14:10] == 5'b11001);

assign alu_op[ 0] = inst_add_w | inst_addi_w | inst_ld_b | inst_ld_h | inst_ld_w
                    | inst_ld_bu | inst_ld_hu | inst_st_b | inst_st_h | inst_st_w
                    | inst_jirl | inst_bl | inst_pcaddu12i
                    | inst_csrrd | inst_csrwr | inst_csrxchg
                    | inst_rdcntl | inst_rdcnth;
assign alu_op[ 1] = inst_sub_w;
assign alu_op[ 2] = inst_slt | inst_slti;
assign alu_op[ 3] = inst_sltu | inst_sltui;
assign alu_op[ 4] = inst_and | inst_andi;
assign alu_op[ 5] = inst_nor;
assign alu_op[ 6] = inst_or | inst_ori;
assign alu_op[ 7] = inst_xor | inst_xori;
assign alu_op[ 8] = inst_slli_w;
assign alu_op[ 9] = inst_srli_w;
assign alu_op[10] = inst_srai_w;
assign alu_op[11] = inst_lu12i_w;
assign alu_op[12] = inst_sll_w;
assign alu_op[13] = inst_srl_w;
assign alu_op[14] = inst_sra_w;
assign alu_op[15] = inst_mul_w;
assign alu_op[16] = inst_mulh_w;
assign alu_op[17] = inst_mulh_wu;
assign alu_op[18] = inst_div_w;
assign alu_op[19] = inst_mod_w;
assign alu_op[20] = inst_div_wu;
assign alu_op[21] = inst_mod_wu;

// any instruction the core decodes as valid (used for INE detection)
wire inst_any = |{inst_add_w,  inst_sub_w,  inst_slt,     inst_sltu,
                  inst_nor,     inst_and,    inst_or,      inst_xor,
                  inst_slli_w,  inst_srli_w, inst_srai_w,  inst_addi_w,
                  inst_ld_b,    inst_ld_h,   inst_ld_w,    inst_ld_bu,
                  inst_ld_hu,   inst_st_b,   inst_st_h,    inst_st_w,
                  inst_jirl,    inst_b,      inst_bl,      inst_beq,
                  inst_bne,     inst_blt,    inst_bge,     inst_bltu,
                  inst_bgeu,    inst_lu12i_w,inst_pcaddu12i,
                  inst_slti,    inst_sltui,  inst_andi,    inst_ori,
                  inst_xori,    inst_sll_w,  inst_srl_w,   inst_sra_w,
                  inst_mul_w,   inst_mulh_w, inst_mulh_wu, inst_div_w,
                  inst_div_wu,  inst_mod_w,  inst_mod_wu,  inst_syscall,
                  inst_ertn,    inst_csrrd,  inst_csrwr,   inst_csrxchg,
                  inst_brk,     inst_rdcntl, inst_rdcnth};

assign id_ls_type = inst_st_b  ? 4'd1 :
                    inst_st_h  ? 4'd2 :
                    inst_st_w  ? 4'd3 :
                    inst_ld_b  ? 4'd4 :
                    inst_ld_h  ? 4'd5 :
                    inst_ld_w  ? 4'd6 :
                    inst_ld_bu ? 4'd7 :
                    inst_ld_hu ? 4'd8 : 4'd0;

assign need_ui5   =  inst_slli_w | inst_srli_w | inst_srai_w;
assign need_si12  =  inst_addi_w
                   | inst_slti | inst_sltui
                   | inst_ld_b | inst_ld_h | inst_ld_w
                   | inst_ld_bu | inst_ld_hu
                   | inst_st_b | inst_st_h | inst_st_w;
assign need_ui12  =  inst_andi | inst_ori | inst_xori;
assign need_si16  =  inst_jirl | inst_beq | inst_bne
                   | inst_blt | inst_bge | inst_bltu | inst_bgeu;
assign need_si20  =  inst_lu12i_w | inst_pcaddu12i;
assign need_si26  =  inst_b | inst_bl;
assign src2_is_4  =  inst_jirl | inst_bl;

assign imm = src2_is_4      ? 32'h4                        :
             inst_lu12i_w   ? {i20[19:0], 12'b0}           :
             inst_pcaddu12i ? {{12{i20[19]}}, i20[19:0], 12'b0} :
             need_ui5       ? {27'd0, rk}                  :
             need_ui12      ? {20'd0, i12}                 :
/*need_si12*/                {{20{i12[11]}}, i12[11:0]}    ;

assign br_offs = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                             {{14{i16[15]}}, i16[15:0], 2'b0} ;

assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

assign src_reg_is_rd = inst_beq | inst_bne | inst_blt | inst_bge
                     | inst_bltu | inst_bgeu
                     | inst_st_b | inst_st_h | inst_st_w
                     | inst_csrwr | inst_csrxchg;

assign src1_is_pc    = inst_jirl | inst_bl | inst_pcaddu12i;
wire   src1_is_csr   = inst_csrrd | inst_csrwr | inst_csrxchg;

assign src2_is_imm   = inst_slli_w |
                       inst_srli_w |
                       inst_srai_w |
                       inst_addi_w |
                       inst_slti   |
                       inst_sltui  |
                       inst_andi   |
                       inst_ori    |
                       inst_xori   |
                       inst_ld_b   |
                       inst_ld_h   |
                       inst_ld_w   |
                       inst_ld_bu  |
                       inst_ld_hu  |
                       inst_st_b   |
                       inst_st_h   |
                       inst_st_w   |
                       inst_lu12i_w|
                       inst_pcaddu12i|
                       inst_jirl   |
                       inst_bl     ;

assign res_from_mem  = inst_ld_b | inst_ld_h | inst_ld_w
                     | inst_ld_bu | inst_ld_hu;
assign dst_is_r1     = inst_bl;
assign gr_we         = ~(inst_st_b | inst_st_h | inst_st_w
                       | inst_beq | inst_bne
                       | inst_blt | inst_bge | inst_bltu | inst_bgeu
                       | inst_b | inst_syscall | inst_ertn);
assign mem_we        = inst_st_b | inst_st_h | inst_st_w;
assign dest          = (inst_rdcntl | inst_rdcnth) ? ((rd != 5'b0) ? rd : rj)
                       : dst_is_r1 ? 5'd1 : rd;

// regfile read ports
wire [ 4:0] rf_raddr1;
wire [31:0] rf_rdata1;
wire [ 4:0] rf_raddr2;
wire [31:0] rf_rdata2;
wire        rf_we   ;
wire [ 4:0] rf_waddr;
wire [31:0] rf_wdata;

assign rf_raddr1 = rj;
assign rf_raddr2 = src_reg_is_rd ? rd : rk;

regfile u_regfile(
    .clk    (clk      ),
    .raddr1 (rf_raddr1),
    .rdata1 (rf_rdata1),
    .raddr2 (rf_raddr2),
    .rdata2 (rf_rdata2),
    .we     (rf_we    ),
    .waddr  (rf_waddr ),
    .wdata  (rf_wdata )
    );

// whether the source register is actually used
wire id_uses_rj  = ~(inst_b | inst_bl | inst_lu12i_w | inst_pcaddu12i
                    | inst_syscall | inst_ertn | inst_csrrd | inst_csrwr
                    | inst_rdcntl | inst_rdcnth);
wire id_uses_rkd = inst_add_w | inst_sub_w | inst_slt | inst_sltu
                 | inst_and | inst_or | inst_nor | inst_xor
                 | inst_beq | inst_bne
                 | inst_blt | inst_bge | inst_bltu | inst_bgeu
                 | inst_st_b | inst_st_h | inst_st_w
                 | inst_sll_w | inst_srl_w | inst_sra_w
                 | inst_mul_w | inst_mulh_w | inst_mulh_wu
                 | inst_div_w | inst_div_wu | inst_mod_w | inst_mod_wu
                 | inst_csrwr | inst_csrxchg;

// ---- data forwarding: EX/MEM/WB results to ID ----
wire [31:0] ex_alu_result;   // EX stage result (combinational)
wire [31:0] mem_value;       // MEM stage result
wire [31:0] wb_result;       // WB stage result

wire fwd_ex_to_rj  = ex_valid && ex_gr_we && ~ex_res_from_mem
                   && (ex_dest != 5'b0) && (ex_dest == rj);
wire fwd_ex_to_rkd = ex_valid && ex_gr_we && ~ex_res_from_mem
                   && (ex_dest != 5'b0) && (ex_dest == (src_reg_is_rd ? rd : rk));
wire fwd_mem_to_rj  = mem_valid && mem_gr_we && (mem_dest != 5'b0) && (mem_dest == rj);
wire fwd_mem_to_rkd = mem_valid && mem_gr_we && (mem_dest != 5'b0)
                    && (mem_dest == (src_reg_is_rd ? rd : rk));
wire fwd_wb_to_rj  = wb_valid && wb_gr_we && (wb_dest != 5'b0) && (wb_dest == rj);
wire fwd_wb_to_rkd = wb_valid && wb_gr_we && (wb_dest != 5'b0)
                   && (wb_dest == (src_reg_is_rd ? rd : rk));

wire [31:0] id_rj_value  = fwd_ex_to_rj  ? ex_alu_result :
                           fwd_mem_to_rj ? mem_value     :
                           fwd_wb_to_rj  ? wb_result     :
                                           rf_rdata1     ;
wire [31:0] id_rkd_value = fwd_ex_to_rkd  ? ex_alu_result :
                           fwd_mem_to_rkd ? mem_value     :
                           fwd_wb_to_rkd  ? wb_result     :
                                            rf_rdata2    ;

// ---- branch resolved in ID ----
wire rj_eq_rd    = (id_rj_value == id_rkd_value);
wire rj_lt_rd_s  = $signed(id_rj_value) < $signed(id_rkd_value);
wire rj_lt_rd_u  = (id_rj_value < id_rkd_value);
wire br_taken = (   (inst_beq  && rj_eq_rd)
                 || (inst_bne  && !rj_eq_rd)
                 || (inst_blt  && rj_lt_rd_s)
                 || (inst_bge  && !rj_lt_rd_s)
                 || (inst_bltu && rj_lt_rd_u)
                 || (inst_bgeu && !rj_lt_rd_u)
                 || inst_jirl
                 || inst_bl
                 || inst_b
                ) && if_valid && ~id_stall;
wire [31:0] br_target;
assign br_target = (inst_beq || inst_bne || inst_blt || inst_bge
                 || inst_bltu || inst_bgeu || inst_bl || inst_b) ? (if_pc + br_offs) :
                                                    /*inst_jirl*/ (id_rj_value + jirl_offs);

// ---- data hazard: stall while EX holds a result ID needs ----
//  1) EX load (data not back yet)
//  2) EX div/mod (multi-cycle, result valid only after it leaves EX)
wire ex_alu_is_div = |ex_alu_op[21:18];
wire id_stall = if_valid && ex_valid && ex_gr_we && (ex_dest != 5'b0)
             && (ex_res_from_mem || ex_alu_is_div)
             && ( (id_uses_rj  && (ex_dest == rj))
               || (id_uses_rkd && (ex_dest == (src_reg_is_rd ? rd : rk))) );

wire id_ready_go  = ~id_stall;
wire id_allowin   = !if_valid || (id_ready_go && ex_allowin);
wire id_to_ex_valid = if_valid && id_ready_go;

// ===================== CSR file & exceptions (exp13) ======================
// CSR bit layouts follow the reference (golden) CPU:
//   crmd : [1:0]=PLV [2]=IE [3]=DA [4]=PG [6:5]=DATF [8:7]=DATM
//   prmd : [1:0]=PPLV [2]=PIE
//   estat: [30:22]=EsubCode [21:16]=Ecode [15:13]=0 [12]=IS12 [11]=IS11
//          [10]=0 [9:8]=IS9/IS8 [7:0]=IS7..0, bit31 always 0
//          only IS0/IS1 are writable by software (masked)
//   ectl : [12:0]=LIE
//   era/badv: full 32-bit
//   eentry: stores bits[31:6], readback = {stored[31:6], 6'b0}
//   tid(0x40)/tcfg(0x41)/tval(0x42)/ticlr(0x44, read 0)
reg [31:0] csr_crmd;
reg [31:0] csr_prmd;
reg [31:0] csr_estat;
reg [31:0] csr_era;
reg [31:0] csr_eentry;
reg [31:0] csr_badv;
reg [31:0] csr_ectl;        // [12:0] LIE
reg [31:0] csr_tid;
reg [31:0] csr_tcfg;        // [0]=En [1]=Periodic [31:2]=InitVal
reg [31:0] timer_tval;

wire [13:0] csr_addr    = if_inst[23:10];
wire        inst_csr_wr = inst_csrwr | inst_csrxchg;

wire [31:0] csr_rdata =
    (csr_addr == 14'h0 ) ? csr_crmd                      :
    (csr_addr == 14'h1 ) ? csr_prmd                      :
    (csr_addr == 14'h4 ) ? csr_ectl                      :
    (csr_addr == 14'h5 ) ? csr_estat                     :
    (csr_addr == 14'h6 ) ? csr_era                       :
    (csr_addr == 14'h7 ) ? csr_badv                      :
    (csr_addr == 14'hc ) ? {csr_eentry[31:6], 6'b0}      :
    (csr_addr == 14'h40) ? csr_tid                       :
    (csr_addr == 14'h41) ? csr_tcfg                      :
    (csr_addr == 14'h42) ? timer_tval                    :
                           32'b0                         ;

// ---- exp13 exception sources (ID stage, single in-order commit point) ----
// interrupt mask vector (bit10 reserved, IS10 absent)
wire [12:0] estat_is  = {csr_estat[12], csr_estat[11], 1'b0,
                         csr_estat[9], csr_estat[8], csr_estat[7:0]};
wire        int_pending = csr_crmd[2] && (|(csr_ectl[12:0] & estat_is));

// ALE: unaligned data access (address computed in ID with forwarding)
wire [31:0] id_mem_addr = id_rj_value + imm;
wire        id_ale_cond = (inst_st_w | inst_ld_w)  ? (|id_mem_addr[1:0]) :
                          (inst_st_h | inst_ld_h | inst_ld_hu) ? id_mem_addr[0] :
                          1'b0;

wire excp_int  = if_valid && int_pending && !inst_ertn;
wire excp_adef = if_valid && !excp_int  && (|if_pc[1:0]);
wire excp_ale  = if_valid && !excp_int  && !excp_adef
              && id_ale_cond && !id_stall;
wire excp_sys  = if_valid && !excp_int  && !excp_adef && !excp_ale && inst_syscall;
wire excp_brk  = if_valid && !excp_int  && !excp_adef && !excp_ale && inst_brk;
wire excp_ine  = if_valid && !excp_int  && !excp_adef && !excp_ale && !inst_any;

wire id_excp_req = excp_int | excp_adef | excp_ale | excp_sys | excp_brk | excp_ine;

wire [5:0] excp_ecode = excp_int  ? 6'd0  :   // INT
                        excp_adef ? 6'd8  :   // ADEF
                        excp_ale  ? 6'd9  :   // ALE
                        excp_sys  ? 6'd11 :   // SYS
                        excp_brk  ? 6'd12 :   // BRK
                                     6'd13;   // INE

wire id_ertn_req = if_valid && inst_ertn;
wire id_redirect = br_taken | id_excp_req | id_ertn_req;
wire [31:0] redirect_target = id_excp_req ? {csr_eentry[31:6], 6'b0} :
                              id_ertn_req ? csr_era                  :
                                            br_target                ;

// one-shot commits when the ID instruction actually advances into EX
wire excp_commit = id_excp_req && id_ready_go && ex_allowin;
wire ertn_commit = id_ertn_req && id_ready_go && ex_allowin;
// an exception preempts the CSR write of the abandoned instruction
wire csr_commit  = if_valid && inst_csr_wr && !id_excp_req
                && id_ready_go && ex_allowin;

wire [31:0] csr_mask  = inst_csrwr ? 32'hffffffff : id_rj_value;
wire [31:0] csr_wdata = id_rkd_value;          // GPR[rd]
wire [8:0]  crmd_w    = (csr_crmd[8:0] & ~csr_mask[8:0])
                      | (csr_wdata[8:0] & csr_mask[8:0]);
wire [2:0]  prmd_w    = (csr_prmd[2:0] & ~csr_mask[2:0])
                      | (csr_wdata[2:0] & csr_mask[2:0]);
wire [31:0] era_w     = (csr_era  & ~csr_mask)
                      | (csr_wdata & csr_mask);
wire [25:0] eentry_w  = (csr_eentry[31:6] & ~csr_mask[31:6])
                      | (csr_wdata[31:6] & csr_mask[31:6]);
wire [31:0] badv_w    = (csr_badv & ~csr_mask)
                      | (csr_wdata & csr_mask);
wire [12:0] ectl_w    = ((csr_ectl[12:0] & ~csr_mask[12:0])
                      | (csr_wdata[12:0] & csr_mask[12:0])) & 13'h1bff;  // ECFG bit10 is reserved (R0)
wire [31:0] tid_w     = (csr_tid & ~csr_mask)
                      | (csr_wdata & csr_mask);
wire [31:0] tcfg_w    = (csr_tcfg & ~csr_mask)
                      | (csr_wdata & csr_mask);
// estat software writes only touch IS0/IS1 (masked)
wire        new_is0   = csr_mask[0] ? csr_wdata[0] : csr_estat[0];
wire        new_is1   = csr_mask[1] ? csr_wdata[1] : csr_estat[1];

// ---- timer (tcfg En/Periodic/InitVal -> TimeVal countdown -> IS11) ----
wire        tcfg_en     = csr_tcfg[0];
wire        tcfg_period = csr_tcfg[1];
wire [29:0] tcfg_init   = csr_tcfg[31:2];
wire [31:0] tval_reload = {tcfg_init, 2'b0};
wire [31:0] tval_next   = tcfg_en ? (timer_tval != 32'd0 ? timer_tval - 32'd1 :
                          (tcfg_period ? tval_reload : timer_tval)) : timer_tval;
wire        is11_no_wr  = tcfg_en
                        ? ((timer_tval != 32'd0)
                           ? ((timer_tval == 32'd1) || csr_estat[11])
                           : csr_estat[11])
                        : csr_estat[11];
wire        tcfg_commit  = csr_commit && (csr_addr == 14'h41);
wire        ticlr_commit = csr_commit && (csr_addr == 14'h44);
wire        next_en      = tcfg_w[0];
wire [29:0] next_init    = tcfg_w[31:2];
wire        is11_on_wr   = next_en ? ((next_init == 30'd0) ? 1'b1 : is11_no_wr)
                                   : is11_no_wr;
wire [31:0] tval_on_wr   = next_en ? {next_init, 2'b0} : tval_next;

// ---- 64-bit free-running counter for rdcntvl.w / rdcntvh.w ----
reg [63:0] tcnt;
always @(posedge clk) begin
    if (reset) tcnt <= 64'b0;
    else       tcnt <= tcnt + 64'd1;
end

always @(posedge clk) begin
    if (reset) begin
        csr_crmd   <= 32'h00000008;   // DA=1, PLV=0(kernel), IE=0
        csr_prmd   <= 32'h0;
        csr_estat  <= 32'h0;
        csr_era    <= 32'h0;
        csr_eentry <= 32'h0;
        csr_badv   <= 32'h0;
        csr_ectl   <= 32'h0;
        csr_tid    <= 32'h0;
        csr_tcfg   <= 32'h0;
        timer_tval <= 32'h0;
    end
    else begin
        // CSR register write (csrwr / csrxchg), committed in ID
        if (csr_commit) begin
            case (csr_addr)
                14'h0:  csr_crmd   <= {23'b0, crmd_w[8:0]};
                14'h1:  csr_prmd   <= {29'b0, prmd_w[2:0]};
                14'h4:  csr_ectl   <= {19'b0, ectl_w};
                14'h6:  csr_era    <= era_w;
                14'h7:  csr_badv   <= badv_w;
                14'hc:  csr_eentry <= {eentry_w[25:0], 6'b0};
                14'h40: csr_tid    <= tid_w;
                14'h41: csr_tcfg   <= tcfg_w;
                default: ;
            endcase
        end
        // estat IS0/IS1 software write
        if (csr_commit && (csr_addr == 14'h5)) begin
            csr_estat[1] <= new_is1;
            csr_estat[0] <= new_is0;
        end
        // Ecode/EsubCode only change on exception entry
        if (excp_commit) begin
            csr_estat[31:16] <= {9'h0, excp_ecode};
        end
        // IS11: ticlr clear > tcfg write > free-running timer
        if (ticlr_commit && csr_wdata[0] && csr_mask[0]) begin
            csr_estat[11] <= 1'b0;
        end
        else if (tcfg_commit) begin
            csr_estat[11] <= is11_on_wr;
        end
        else begin
            csr_estat[11] <= is11_no_wr;
        end
        // TimeVal update (tcfg write reloads; otherwise countdown)
        if (tcfg_commit) begin
            timer_tval <= tval_on_wr;
        end
        else begin
            timer_tval <= tval_next;
        end
        // exception entry: PRMD<-CRMD, CRMD.IE/PLV<-0, ERA<-PC, Ecode, Badv
        if (excp_commit) begin
            csr_prmd   <= {29'b0, csr_crmd[2:0]};
            csr_crmd   <= {23'b0, csr_crmd[8:3], 3'b0};
            csr_era    <= if_pc;
            if (excp_ale)        csr_badv <= id_mem_addr;
            else if (excp_adef)  csr_badv <= if_pc;
        end
        // exception return
        if (ertn_commit) begin
            csr_crmd   <= {23'b0, csr_crmd[8:3], csr_prmd[2:0]};
        end
    end
end

// =============================== EX stage ================================
reg         ex_valid;
reg  [31:0] ex_pc;
reg  [21:0] ex_alu_op;
reg  [31:0] ex_alu_src1;
reg  [31:0] ex_alu_src2;
reg  [31:0] ex_rkd_value;   // store data
reg         ex_gr_we;
reg  [3:0]  ex_ls_type;     // load/store type
reg         ex_res_from_mem;
reg  [ 4:0] ex_dest;

// ---- multi-cycle divider state (div/mod instructions) ----
reg         ex_div_busy;
reg         ex_div_unsigned;
reg         ex_div_mod;
reg         ex_div_q_neg;
reg         ex_div_r_neg;
reg  [63:0] ex_div_acc;
reg  [31:0] ex_div_babs;
reg  [ 4:0] ex_div_step;
reg  [31:0] ex_div_q;
reg  [31:0] ex_div_r;

wire id_is_divmod = inst_div_w | inst_mod_w | inst_div_wu | inst_mod_wu;
wire ex_accept_div = id_to_ex_valid && ex_allowin && id_is_divmod;

wire [31:0] div_rem_n = {ex_div_acc[62:32], ex_div_acc[31]};
wire [31:0] div_q_n   = {ex_div_acc[30: 0], 1'b0};
wire        div_ge    = (ex_div_babs != 32'd0) && (div_rem_n >= ex_div_babs);
wire [63:0] div_acc_n = div_ge ? {div_rem_n - ex_div_babs, div_q_n | 32'd1}
                               : {div_rem_n, div_q_n};

always @(posedge clk) begin
    if (reset) begin
        ex_div_busy     <= 1'b0;
        ex_div_unsigned <= 1'b0;
        ex_div_mod      <= 1'b0;
        ex_div_q_neg    <= 1'b0;
        ex_div_r_neg    <= 1'b0;
        ex_div_acc      <= 64'b0;
        ex_div_babs     <= 32'b0;
        ex_div_step     <= 5'd0;
        ex_div_q        <= 32'b0;
        ex_div_r        <= 32'b0;
    end
    else if (ex_accept_div) begin
        ex_div_busy     <= 1'b1;
        ex_div_step     <= 5'd0;
        ex_div_unsigned <= inst_div_wu | inst_mod_wu;
        ex_div_mod      <= inst_mod_w | inst_mod_wu;
        ex_div_q_neg    <= inst_div_w && (id_rj_value[31] ^ id_rkd_value[31]);
        ex_div_r_neg    <= inst_mod_w && id_rj_value[31];
        if (inst_div_wu || inst_mod_wu) begin
            ex_div_acc  <= {32'd0, id_rj_value};
            ex_div_babs <= id_rkd_value;
        end
        else begin
            ex_div_acc  <= {32'd0, id_rj_value[31] ? (~id_rj_value + 32'd1) : id_rj_value};
            ex_div_babs <= id_rkd_value[31] ? (~id_rkd_value + 32'd1) : id_rkd_value;
        end
    end
    else if (ex_div_busy) begin
        if (ex_div_step == 5'd31) begin
            ex_div_busy <= 1'b0;
            if (ex_div_unsigned) begin
                ex_div_q <= div_acc_n[31: 0];
                ex_div_r <= div_acc_n[63:32];
            end
            else begin
                ex_div_q <= ex_div_q_neg ? (~div_acc_n[31: 0] + 32'd1)
                                         : div_acc_n[31: 0];
                ex_div_r <= ex_div_r_neg ? (~div_acc_n[63:32] + 32'd1)
                                         : div_acc_n[63:32];
            end
        end
        else begin
            ex_div_step <= ex_div_step + 1'b1;
            ex_div_acc  <= div_acc_n;
        end
    end
end

// ---- data memory transaction controller (SRAM handshake) ----
// A memory instruction stays in EX until its transaction finishes:
//   data_st[0] : request phase (req asserted, waiting for addr_ok)
//   data_st[1] : data phase (waiting for data_ok)
// data_done marks a completed access and lets the instruction leave EX.
// Read data is captured in EX (ex_rd_word) and carried through MEM, so the
// MEM stage never has to wait for the bus.
reg        data_st;
reg        data_done;
reg [31:0] ex_rd_word;

wire data_mem_op   = ex_valid && (ex_ls_type != 4'd0);
wire data_is_load  = (ex_ls_type >= 4'd4) && (ex_ls_type <= 4'd8);
wire data_is_wr    = (ex_ls_type >= 4'd1) && (ex_ls_type <= 4'd3);
wire data_issue    = data_mem_op && !data_done;
wire data_accept   = data_issue && (data_st == 1'b0) && data_sram_addr_ok;
wire data_finish   = (data_st == 1'b1) && data_sram_data_ok;

assign data_sram_req   = data_issue && !data_st;
assign data_sram_wr    = data_is_wr;
assign data_sram_size  = ((ex_ls_type == 4'd1) || (ex_ls_type == 4'd4) ||
                          (ex_ls_type == 4'd7)) ? 2'd0 :
                         ((ex_ls_type == 4'd2) || (ex_ls_type == 4'd5) ||
                          (ex_ls_type == 4'd8)) ? 2'd1 : 2'd2;
// memory access address: a dedicated adder, NOT ex_alu_result, so the
// 32x32 multiplier/divider cones stay off the BRAM address path
wire [31:0] mem_addr_n = ex_alu_src1 + ex_alu_src2;
assign data_sram_wstrb = (ex_ls_type == 4'd1) ? (4'b0001 << mem_addr_n[1:0]) :
                         (ex_ls_type == 4'd2) ? (4'b0011 << {mem_addr_n[1], 1'b0}) :
                         (ex_ls_type == 4'd3) ? 4'b1111 : 4'b0000;
assign data_sram_addr  = mem_addr_n;
assign data_sram_wdata = (ex_ls_type == 4'd1) ? {4{ex_rkd_value[7:0]}} :
                         (ex_ls_type == 4'd2) ? {2{ex_rkd_value[15:0]}} :
                                                ex_rkd_value;

always @(posedge clk) begin
    if (reset) begin
        data_st    <= 1'b0;
        data_done  <= 1'b0;
        ex_rd_word <= 32'b0;
    end
    else begin
        // address accepted -> wait for the response
        if (data_accept) data_st <= 1'b1;
        // response returned: capture load data and release EX
        if (data_finish) begin
            data_st   <= 1'b0;
            data_done <= 1'b1;
            if (data_is_load) ex_rd_word <= data_sram_rdata;
        end
        // the instruction leaves EX (data_done cannot be set for a
        // non-memory instruction, so this only fires for the same access)
        if (ex_to_mem_valid && mem_allowin) data_done <= 1'b0;
    end
end

wire ex_ready_go  = ~ex_div_busy && ~(data_mem_op && ~data_done);
wire ex_allowin   = !ex_valid || (ex_ready_go && mem_allowin);
wire ex_to_mem_valid = ex_valid && ex_ready_go;

always @(posedge clk) begin
    if (reset) begin
        ex_valid <= 1'b0;
    end
    else if (ex_allowin) begin
        ex_valid <= id_to_ex_valid && !id_excp_req;  // exp13: flush excp instr
    end
end

always @(posedge clk) begin
    if (reset) begin
        ex_pc <= 32'b0;
        ex_alu_op <= 22'b0;
        ex_alu_src1 <= 32'b0;
        ex_alu_src2 <= 32'b0;
        ex_rkd_value <= 32'b0;
        ex_gr_we <= 1'b0;
        ex_ls_type <= 4'd0;
        ex_res_from_mem <= 1'b0;
        ex_dest <= 5'b0;
    end
    else if (id_to_ex_valid && ex_allowin && !id_excp_req) begin
        ex_pc <= if_pc;
        ex_alu_op <= alu_op;
        // rdcntl/rdcnth: rd != 0 -> counter slice; rd == 0 (rdcntid) -> TID
        ex_alu_src1 <= inst_rdcntl ? ((rd != 5'b0) ? tcnt[31: 0] : csr_tid) :
                       inst_rdcnth ? ((rd != 5'b0) ? tcnt[63:32] : csr_tid) :
                       src1_is_pc  ? if_pc :
                       src1_is_csr ? csr_rdata : id_rj_value;
        ex_alu_src2 <= (inst_rdcntl | inst_rdcnth) ? 32'b0 :
                       src2_is_imm ? imm :
                       src1_is_csr ? 32'b0 : id_rkd_value;
        ex_rkd_value <= id_rkd_value;
        ex_gr_we <= gr_we;
        ex_ls_type <= id_ls_type;
        ex_res_from_mem <= res_from_mem;
        ex_dest <= dest;
    end
end

wire [31:0] ex_alu_result_raw;
alu u_alu(
    .alu_op     (ex_alu_op    ),
    .alu_src1   (ex_alu_src1  ),
    .alu_src2   (ex_alu_src2  ),
    .alu_result (ex_alu_result_raw)
    );

// div/mod result is produced by the multi-cycle divider in EX
assign ex_alu_result = ex_alu_is_div ? (ex_div_mod ? ex_div_r : ex_div_q)
                                     : ex_alu_result_raw;

// =============================== MEM stage ===============================
reg         mem_valid;
reg  [31:0] mem_pc;
reg  [31:0] mem_alu_result;
reg         mem_gr_we;
reg  [3:0]  mem_ls_type;
reg         mem_res_from_mem;
reg  [ 4:0] mem_dest;
reg  [31:0] mem_rd_word;

wire mem_ready_go = 1'b1;
wire mem_allowin  = !mem_valid || (mem_ready_go && wb_allowin);
wire mem_to_wb_valid = mem_valid && mem_ready_go;

always @(posedge clk) begin
    if (reset) begin
        mem_valid <= 1'b0;
    end
    else if (mem_allowin) begin
        mem_valid <= ex_to_mem_valid;
    end
end

always @(posedge clk) begin
    if (reset) begin
        mem_pc <= 32'b0;
        mem_alu_result <= 32'b0;
        mem_gr_we <= 1'b0;
        mem_ls_type <= 4'd0;
        mem_res_from_mem <= 1'b0;
        mem_dest <= 5'b0;
    end
    else if (ex_to_mem_valid && mem_allowin) begin
        mem_pc <= ex_pc;
        mem_alu_result <= ex_alu_result;
        mem_gr_we <= ex_gr_we;
        mem_ls_type <= ex_ls_type;
        mem_res_from_mem <= ex_res_from_mem;
        mem_dest <= ex_dest;
        mem_rd_word <= (ex_ls_type >= 4'd4) ? ex_rd_word : mem_rd_word;
    end
end

// load data selection (data word was captured in EX when data_ok returned)
wire [31:0] mem_byte_shifted = mem_rd_word >> {mem_alu_result[1:0], 3'b0};
wire [31:0] mem_half_val = mem_alu_result[1] ? mem_rd_word[31:16]
                                             : mem_rd_word[15:0];
wire [31:0] mem_load_val =
    (mem_ls_type == 4'd6) ? mem_rd_word :
    (mem_ls_type == 4'd5) ? {{16{mem_half_val[15]}}, mem_half_val[15:0]} :
    (mem_ls_type == 4'd8) ? {16'd0, mem_half_val[15:0]} :
    (mem_ls_type == 4'd4) ? {{24{mem_byte_shifted[7]}}, mem_byte_shifted[7:0]} :
    (mem_ls_type == 4'd7) ? {24'd0, mem_byte_shifted[7:0]} :
                             32'b0;

assign mem_value = mem_res_from_mem ? mem_load_val : mem_alu_result;

// =============================== WB stage ================================
reg         wb_valid;
reg  [31:0] wb_pc;
reg         wb_gr_we;
reg  [ 4:0] wb_dest;
reg  [31:0] wb_value;

wire wb_ready_go = 1'b1;
wire wb_allowin  = !wb_valid || (wb_ready_go && 1'b1);

always @(posedge clk) begin
    if (reset) begin
        wb_valid <= 1'b0;
    end
    else if (wb_allowin) begin
        wb_valid <= mem_to_wb_valid;
    end
end

always @(posedge clk) begin
    if (reset) begin
        wb_pc <= 32'b0;
        wb_gr_we <= 1'b0;
        wb_dest <= 5'b0;
        wb_value <= 32'b0;
    end
    else if (mem_to_wb_valid && wb_allowin) begin
        wb_pc <= mem_pc;
        wb_gr_we <= mem_gr_we;
        wb_dest <= mem_dest;
        wb_value <= mem_value;
    end
end

// regfile write port
assign rf_we    = wb_gr_we && wb_valid;
assign rf_waddr = wb_dest;
assign rf_wdata = wb_value;

assign wb_result = wb_value;

// debug info (WB stage)
assign debug_wb_pc       = wb_pc;
assign debug_wb_rf_we    = {4{rf_we}};
assign debug_wb_rf_wnum  = wb_dest;
assign debug_wb_rf_wdata = wb_value;


// ============================================================================
// AXI master adapters (exp15/16, single shared AXI port)
// ----------------------------------------------------------------------------
// The core above drives and samples the virtual SRAM handshakes; these
// adapters translate them into AXI4 single-beat transactions:
//   IF fetch / EX load : AR handshake -> addr_ok, R handshake -> data_ok
//   EX store           : AW handshake -> addr_ok, B handshake -> data_ok
//                        (W data is presented until WREADY)
// EX data requests win the bus over IF fetches.  A fetch request whose AR is
// still pending when a redirect commits cannot be cancelled on the bus; its
// late response is swallowed (rd_discard) instead of being offered to the IF
// engine, which simply re-issues from the redirect target.
// ============================================================================
wire if_fetch_want = if_fetch_issue;
wire data_want     = data_mem_op && !data_done && !data_st;
wire data_want_ld  = data_want && data_is_load;
wire data_want_wr  = data_want && data_is_wr;

// ---------------- read channel (IF fetches + EX loads share it) ------------
reg  [1:0]  rd_st;        // 0 idle, 1 AR pending, 2 waiting for the R beat
reg         rd_is_if;     // current read is an IF fetch
reg         rd_discard;   // IF fetch flushed while its AR was pending
reg  [31:0] rd_addr;      // address latched when the read started

wire rd_idle   = (rd_st == 2'd0);
wire rd_ar_ok  = (rd_st == 2'd1);
wire rd_r_wait = (rd_st == 2'd2);

wire if_ar_start   = rd_idle && (wr_st == 2'd0) && if_fetch_want && !data_want;
wire data_ar_start = rd_idle && (wr_st == 2'd0) && data_want_ld;

always @(posedge clk) begin
    if (reset) begin
        rd_st      <= 2'd0;
        rd_is_if   <= 1'b0;
        rd_discard <= 1'b0;
        rd_addr    <= 32'b0;
    end
    else begin
        // start: drive ARVALID with the latched transaction address
        if (if_ar_start || data_ar_start) begin
            rd_st      <= 2'd1;
            rd_is_if   <= if_ar_start;
            rd_discard <= 1'b0;
            rd_addr    <= if_ar_start ? inst_sram_addr : data_sram_addr;
        end
        // AR accepted -> wait for the single-beat R response
        if (rd_ar_ok && arready) rd_st <= 2'd2;
        // R response retired
        if (rd_r_wait && rvalid && rlast) rd_st <= 2'd0;
        // a redirect that commits while the IF fetch AR is still pending
        // cannot cancel the bus request: swallow its late response
        if (redirect_flush && rd_ar_ok && rd_is_if) rd_discard <= 1'b1;
    end
end

// ---------------- write channel (EX stores) --------------------------------
reg  [1:0]  wr_st;        // 0 idle, 1 AW/W phase, 2 waiting for the B beat
reg         aw_done;      // AWREADY seen for the current write
reg         w_done;       // WREADY seen for the current write
reg  [31:0] wr_addr;
reg  [31:0] wr_data;
reg  [ 3:0] wr_strb;
reg  [ 2:0] wr_size;

wire wr_aw_ok  = (wr_st == 2'd1) && !aw_done;
wire wr_w_ok   = (wr_st == 2'd1) && !w_done;
wire wr_b_wait = (wr_st == 2'd2);

wire wr_start  = (wr_st == 2'd0) && rd_idle && data_want_wr;

always @(posedge clk) begin
    if (reset) begin
        wr_st   <= 2'd0;
        aw_done <= 1'b0;
        w_done  <= 1'b0;
        wr_addr <= 32'b0;
        wr_data <= 32'b0;
        wr_strb <= 4'b0;
        wr_size <= 3'b0;
    end
    else begin
        case (wr_st)
        2'd0: if (wr_start) begin
                  wr_st   <= 2'd1;
                  aw_done <= 1'b0;
                  w_done  <= 1'b0;
                  wr_addr <= data_sram_addr;
                  wr_data <= data_sram_wdata;
                  wr_strb <= data_sram_wstrb;
                  wr_size <= {1'b0, data_sram_size};
              end
        2'd1: begin
                  // AW and W are independent: accept whichever comes first
                  if (wr_aw_ok && awready) aw_done <= 1'b1;
                  if (wr_w_ok  && wready ) w_done  <= 1'b1;
                  if ((aw_done || (wr_aw_ok && awready)) &&
                      (w_done  || (wr_w_ok  && wready ))) wr_st <= 2'd2;
              end
        2'd2: if (bvalid) wr_st <= 2'd0;   // BREADY is held high here
        endcase
    end
end

// ---------------- AXI master output drive -----------------------------------
assign arid    = 4'd0;
assign araddr  = rd_addr;
assign arlen   = 8'd0;
assign arsize  = rd_is_if ? 3'b010 : {1'b0, data_sram_size};
assign arburst = 2'b01;    // INCR
assign arlock  = 2'b00;
assign arcache = 4'b0000;
assign arprot  = 3'b000;
assign arvalid = rd_ar_ok;
assign rready  = rd_r_wait;

assign awid    = 4'd0;
assign awaddr  = wr_addr;
assign awlen   = 8'd0;
assign awsize  = wr_size;
assign awburst = 2'b01;    // INCR
assign awlock  = 2'b00;
assign awcache = 4'b0000;
assign awprot  = 3'b000;
assign awvalid = wr_aw_ok;

assign wid     = 4'd0;
assign wdata   = wr_data;
assign wstrb   = wr_strb;
assign wlast   = wr_w_ok;
assign wvalid  = wr_w_ok;

assign bready  = wr_b_wait;

// ---------------- virtual handshake back to the pipeline --------------------
assign inst_sram_addr_ok = rd_ar_ok && arready && rd_is_if && !rd_discard;
assign inst_sram_data_ok = rd_r_wait && rvalid && rlast && rd_is_if
                         && !rd_discard;
assign inst_sram_rdata   = rdata;
assign data_sram_addr_ok = (rd_ar_ok && arready && !rd_is_if) ||
                           (wr_aw_ok && awready);
assign data_sram_data_ok = (rd_r_wait && rvalid && rlast && !rd_is_if) ||
                           (wr_b_wait && bvalid);
assign data_sram_rdata   = rdata;
endmodule
