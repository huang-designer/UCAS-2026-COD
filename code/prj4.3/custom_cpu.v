`timescale 10ns / 1ns

module custom_cpu(
	input         clk,
	input         rst,

	output [31:0] PC,
	output        Inst_Req_Valid,
	input         Inst_Req_Ready,

	input  [31:0] Instruction,
	input         Inst_Valid,
	output        Inst_Ready,

	output [31:0] Address,
	output        MemWrite,
	output [31:0] Write_data,
	output [ 3:0] Write_strb,
	output        MemRead,
	input         Mem_Req_Ready,

	input  [31:0] Read_data,
	input         Read_data_Valid,
	output        Read_data_Ready,

	input         intr,

	output [31:0] cpu_perf_cnt_0,
	output [31:0] cpu_perf_cnt_1,
	output [31:0] cpu_perf_cnt_2,
	output [31:0] cpu_perf_cnt_3,
	output [31:0] cpu_perf_cnt_4,
	output [31:0] cpu_perf_cnt_5,
	output [31:0] cpu_perf_cnt_6,
	output [31:0] cpu_perf_cnt_7,
	output [31:0] cpu_perf_cnt_8,
	output [31:0] cpu_perf_cnt_9,
	output [31:0] cpu_perf_cnt_10,
	output [31:0] cpu_perf_cnt_11,
	output [31:0] cpu_perf_cnt_12,
	output [31:0] cpu_perf_cnt_13,
	output [31:0] cpu_perf_cnt_14,
	output [31:0] cpu_perf_cnt_15,

	output [69:0] inst_retire
);

	localparam DATA_WIDTH = 32;
	localparam AND_OP  = 3'b000;
	localparam OR_OP   = 3'b001;
	localparam XOR_OP  = 3'b100;
	localparam ADD_OP  = 3'b010;
	localparam SUB_OP  = 3'b110;
	localparam SLT_OP  = 3'b111;
	localparam SLTU_OP = 3'b011;

	localparam R_TYPE   = 5'b01100;
	localparam I_TYPE_C = 5'b00100;
	localparam I_TYPE_L = 5'b00000;
	localparam JALR_OP  = 5'b11001;
	localparam S_TYPE   = 5'b01000;
	localparam B_TYPE   = 5'b11000;
	localparam LUI_OP   = 5'b01101;
	localparam AUIPC_OP = 5'b00101;
	localparam JAL_OP   = 5'b11011;

	localparam IF_TO_ID_WIDTH      = 64;
	localparam PREDICTION_WIDTH    = 33;
	localparam ID_TO_EX_WIDTH      = 255;
	localparam EX_ID_BYPATH_WIDTH  = 39;
	localparam MEM_ID_BYPATH_WIDTH = 39;
	localparam WB_ID_BYPATH_WIDTH  = 38;
	localparam EX_TO_MEM_WIDTH     = 182;
	localparam MEM_TO_WB_WIDTH     = 70;

	localparam BP_INIT    = 5'b00001;
	localparam BP_S_TAKE  = 5'b00010;
	localparam BP_W_TAKE  = 5'b00100;
	localparam BP_W_NTAKE = 5'b01000;
	localparam BP_S_NTAKE = 5'b10000;

	localparam IF_INIT     = 5'b00001;
	localparam IF_REQ      = 5'b00010;
	localparam IF_WAIT     = 5'b00100;
	localparam IF_SEND     = 5'b01000;
	localparam IF_ADVANCE  = 5'b10000;

	localparam MEM_INIT      = 5'b00001;
	localparam MEM_SL_BEFORE = 5'b00010;
	localparam MEM_SL        = 5'b00100;
	localparam MEM_RDW       = 5'b01000;
	localparam MEM_SL_DONE   = 5'b10000;

	wire unused_intr = intr;

	reg [31:0] cycle_cnt;
	reg [31:0] inst_cnt;
	reg [31:0] mem_cnt;

	always @(posedge clk) begin
		if (rst) begin
			cycle_cnt <= 32'd0;
		end else begin
			cycle_cnt <= cycle_cnt + 32'd1;
		end
	end

	assign cpu_perf_cnt_0 = cycle_cnt;

	reg [31:0] pc_reg;
	reg [31:0] instruction_reg;
	reg [4:0]  if_state;
	reg [4:0]  if_next_state;

	reg [IF_TO_ID_WIDTH-1:0] if_to_id_reg;
	reg                      id_work;
	reg [ID_TO_EX_WIDTH-1:0] id_to_ex_reg;
	reg                      ex_work;
	reg [EX_TO_MEM_WIDTH-1:0] ex_to_mem_reg;
	reg                      mem_work;
	reg [4:0]                mem_state;
	reg [4:0]                mem_next_state;
	reg [31:0]               read_data_current;
	reg [MEM_TO_WB_WIDTH-1:0] mem_to_wb_reg;
	reg                       wb_work;

	reg [4:0] predictor_state;

	wire [31:0] if_pc = if_to_id_reg[63:32];
	wire [31:0] if_inst = if_to_id_reg[31:0];

	wire [4:0] opcode = if_inst[6:2];
	wire [4:0] rd = if_inst[11:7];
	wire [4:0] rs1 = if_inst[19:15];
	wire [4:0] rs2 = if_inst[24:20];
	wire [4:0] shamt = if_inst[24:20];
	wire [2:0] func = if_inst[14:12];
	wire [3:0] func_r = {if_inst[30], func};
	wire [6:0] func7 = if_inst[31:25];

	wire [31:0] u_imm = {if_inst[31:12], 12'b0};
	wire [31:0] i_imm = {{20{if_inst[31]}}, if_inst[31:20]};
	wire [31:0] s_imm = {{20{if_inst[31]}}, if_inst[31:25], if_inst[11:7]};
	wire [31:0] b_imm = {{20{if_inst[31]}}, if_inst[7], if_inst[30:25], if_inst[11:8], 1'b0};
	wire [31:0] j_imm = {{12{if_inst[31]}}, if_inst[19:12], if_inst[20], if_inst[30:25], if_inst[24:21], 1'b0};

	wire [4:0] rf_waddr_wb;
	wire [31:0] rf_wdata_wb;
	wire rf_wen_wb;
	wire [31:0] rdata1;
	wire [31:0] rdata2;

	wire [38:0] ex_to_id_bypath_data;
	wire [38:0] mem_to_id_bypath_data;
	wire [37:0] wb_to_id_bypath_data;

	wire ex_load = ex_to_id_bypath_data[38];
	wire ex_write = ex_to_id_bypath_data[37];
	wire [4:0] ex_waddr_bypass = ex_to_id_bypath_data[36:32];
	wire [31:0] ex_data_bypass = ex_to_id_bypath_data[31:0];

	wire mem_load_bypass = mem_to_id_bypath_data[38];
	wire mem_write_bypass = mem_to_id_bypath_data[37];
	wire [4:0] mem_waddr_bypass = mem_to_id_bypath_data[36:32];
	wire [31:0] mem_data_bypass = mem_to_id_bypath_data[31:0];

	wire wb_wen_bypass = wb_to_id_bypath_data[37];
	wire [4:0] wb_waddr_bypass = wb_to_id_bypath_data[36:32];
	wire [31:0] wb_data_bypass = wb_to_id_bypath_data[31:0];

	reg_file Registers(
		.clk    (clk),
		.waddr  (rf_waddr_wb),
		.raddr1 (rs1),
		.raddr2 (rs2),
		.wen    (rf_wen_wb),
		.wdata  (rf_wdata_wb),
		.rdata1 (rdata1),
		.rdata2 (rdata2)
	);

	wire ex_related = ex_write && ((rs1 == ex_waddr_bypass) || (rs2 == ex_waddr_bypass));
	wire mem_related = mem_write_bypass && ((rs1 == mem_waddr_bypass) || (rs2 == mem_waddr_bypass));
	wire id_block = (ex_related && ex_load) || (mem_related && mem_load_bypass);

	wire [31:0] rdata1_true =
		(rs1 == 5'b0) ? 32'b0 :
		(ex_write && (rs1 == ex_waddr_bypass)) ? ex_data_bypass :
		(mem_write_bypass && (rs1 == mem_waddr_bypass)) ? mem_data_bypass :
		(wb_wen_bypass && (rs1 == wb_waddr_bypass)) ? wb_data_bypass :
		rdata1;

	wire [31:0] rdata2_true =
		(rs2 == 5'b0) ? 32'b0 :
		(ex_write && (rs2 == ex_waddr_bypass)) ? ex_data_bypass :
		(mem_write_bypass && (rs2 == mem_waddr_bypass)) ? mem_data_bypass :
		(wb_wen_bypass && (rs2 == wb_waddr_bypass)) ? wb_data_bypass :
		rdata2;

	wire [2:0] alu_op =
		((opcode == I_TYPE_L) || (opcode == S_TYPE)) ? ADD_OP :
		((opcode == B_TYPE) && (func[2:1] == 2'b00)) ? SUB_OP :
		((opcode == B_TYPE) && (func[2:1] == 2'b10)) ? SLT_OP :
		((opcode == B_TYPE) && (func[2:1] == 2'b11)) ? SLTU_OP :
		((opcode == R_TYPE) && (func_r == 4'b1000)) ? SUB_OP :
		(func == 3'b000) ? ADD_OP :
		(func == 3'b010) ? SLT_OP :
		(func == 3'b011) ? SLTU_OP :
		(func == 3'b100) ? XOR_OP :
		(func == 3'b110) ? OR_OP :
		AND_OP;

	wire [31:0] alu_op_a = rdata1_true;
	wire [31:0] alu_op_b =
		((opcode == I_TYPE_C) || (opcode == I_TYPE_L)) ? i_imm :
		(opcode == S_TYPE) ? s_imm :
		rdata2_true;

	wire [1:0] shift_op =
		(func == 3'b001) ? 2'b00 :
		(func_r == 4'b0101) ? 2'b10 :
		(func_r == 4'b1101) ? 2'b11 :
		2'b01;

	wire [31:0] shift_op_a = rdata1_true;
	wire [4:0] shift_op_b = (opcode == I_TYPE_C) ? shamt : rdata2_true[4:0];

	wire rf_wen_id =
		(opcode == AUIPC_OP || opcode == JAL_OP || opcode == JALR_OP) ? 1'b1 :
		(opcode == I_TYPE_L || opcode == LUI_OP) ? 1'b1 :
		(opcode == I_TYPE_C || opcode == R_TYPE) ? 1'b1 :
		1'b0;

	wire alu_shift_sel = ((opcode == I_TYPE_C || opcode == R_TYPE) && ((func == 3'b101) || (func == 3'b001)));
	wire branch_id = (opcode == B_TYPE);
	wire jump_id = (opcode == JAL_OP || opcode == JALR_OP);
	wire load_id = (opcode == I_TYPE_L);
	wire store_id = (opcode == S_TYPE);
	wire mul_id = (opcode == R_TYPE) && (func7 == 7'b0000001) && (func == 3'b000);

	wire [31:0] jump_r = (rdata1_true + i_imm) & 32'hfffffffe;
	wire [31:0] pc_branch = if_pc + b_imm;
	wire [31:0] pc_jump = (opcode == JAL_OP) ? (if_pc + j_imm) : jump_r;
	wire [31:0] prediction_addr = branch_id ? pc_branch : (jump_id ? pc_jump : 32'b0);
	wire prediction_out = (predictor_state == BP_S_TAKE) || (predictor_state == BP_W_TAKE);
	wire prediction_yes = jump_id || (branch_id && prediction_out);

	wire [32:0] predictor_to_if_data = {prediction_yes, prediction_addr};
	wire [31:0] predictor_addr_to_if = predictor_to_if_data[31:0];
	wire predictor_yes_to_if = predictor_to_if_data[32];

	wire id_done;
	wire id_ready;
	wire if_to_id_valid;
	wire id_to_ex_valid;
	wire ex_ready;
	wire ex_to_mem_valid;
	wire mem_ready;
	wire mem_to_wb_valid;
	wire wb_ready;
	wire prediction_incorrect;
	wire [31:0] pc_correct;

	always @(posedge clk) begin
		if (rst) begin
			predictor_state <= BP_INIT;
		end else if (id_to_ex_valid && branch_id) begin
			case (predictor_state)
				BP_INIT: predictor_state <= BP_S_TAKE;
				BP_S_TAKE: predictor_state <= prediction_incorrect ? BP_W_TAKE : BP_S_TAKE;
				BP_W_TAKE: predictor_state <= prediction_incorrect ? BP_W_NTAKE : BP_S_TAKE;
				BP_W_NTAKE: predictor_state <= prediction_incorrect ? BP_S_NTAKE : BP_W_TAKE;
				BP_S_NTAKE: predictor_state <= prediction_incorrect ? BP_S_NTAKE : BP_W_NTAKE;
				default: predictor_state <= BP_INIT;
			endcase
		end else if (!rst && predictor_state == BP_INIT) begin
			predictor_state <= BP_S_TAKE;
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			if_state <= IF_INIT;
		end else begin
			if_state <= if_next_state;
		end
	end

	always @(*) begin
		case (if_state)
			IF_INIT: if_next_state = IF_REQ;
			IF_REQ: begin
				if (prediction_incorrect) begin
					if_next_state = IF_REQ;
				end else if (Inst_Req_Ready && Inst_Req_Valid) begin
					if_next_state = IF_WAIT;
				end else begin
					if_next_state = IF_REQ;
				end
			end
			IF_WAIT: begin
				if (prediction_incorrect) begin
					if_next_state = IF_REQ;
				end else if (Inst_Ready && Inst_Valid) begin
					if_next_state = IF_SEND;
				end else begin
					if_next_state = IF_WAIT;
				end
			end
			IF_SEND: begin
				if (prediction_incorrect) begin
					if_next_state = IF_REQ;
				end else if (id_ready) begin
					if_next_state = IF_ADVANCE;
				end else begin
					if_next_state = IF_SEND;
				end
			end
			IF_ADVANCE: begin
				if (id_ready) begin
					if_next_state = IF_REQ;
				end else begin
					if_next_state = IF_ADVANCE;
				end
			end
			default: if_next_state = IF_INIT;
		endcase
	end

	assign Inst_Ready = (if_state == IF_WAIT) || (if_state == IF_INIT);
	assign Inst_Req_Valid = (if_state == IF_REQ) && ~prediction_incorrect && ~MemRead;
	assign if_to_id_valid = (if_state == IF_SEND) && ~prediction_incorrect;

	always @(posedge clk) begin
		if (rst) begin
			instruction_reg <= 32'b0;
		end else if (Inst_Ready && Inst_Valid) begin
			instruction_reg <= Instruction;
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			pc_reg <= 32'b0;
		end else if (prediction_incorrect) begin
			pc_reg <= pc_correct;
		end else if ((if_state == IF_ADVANCE) && id_ready) begin
			if (predictor_yes_to_if) begin
				pc_reg <= predictor_addr_to_if;
			end else begin
				pc_reg <= pc_reg + 32'd4;
			end
		end
	end

	assign PC = pc_reg;

	always @(posedge clk) begin
		if (rst) begin
			if_to_id_reg <= {IF_TO_ID_WIDTH{1'b0}};
		end else if (if_to_id_valid && id_ready) begin
			if_to_id_reg <= {PC, instruction_reg};
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			id_work <= 1'b0;
		end else if (prediction_incorrect) begin
			id_work <= 1'b0;
		end else if (id_ready) begin
			id_work <= if_to_id_valid;
		end
	end

	assign id_done = ~id_block && ~prediction_incorrect;
	assign id_ready = ~id_work || (id_done && ex_ready);
	assign id_to_ex_valid = id_done && id_work && ex_ready;

	wire [254:0] id_to_ex_data = {
		mul_id,
		u_imm,
		opcode,
		if_pc,
		prediction_out,
		prediction_addr,
		alu_op,
		alu_op_a,
		alu_op_b,
		shift_op,
		shift_op_a,
		shift_op_b,
		alu_shift_sel,
		jump_id,
		branch_id,
		func,
		load_id,
		store_id,
		rf_wen_id,
		rd,
		rdata2_true
	};

	always @(posedge clk) begin
		if (rst) begin
			id_to_ex_reg <= {ID_TO_EX_WIDTH{1'b0}};
		end else if (id_to_ex_valid && ex_ready) begin
			id_to_ex_reg <= id_to_ex_data;
		end
	end

	wire        ex_mul            = id_to_ex_reg[254];
	wire [31:0] ex_u_imm          = id_to_ex_reg[253:222];
	wire [4:0]  ex_opcode         = id_to_ex_reg[221:217];
	wire [31:0] ex_pc             = id_to_ex_reg[216:185];
	wire        ex_prediction     = id_to_ex_reg[184];
	wire [31:0] ex_prediction_addr= id_to_ex_reg[183:152];
	wire [2:0]  ex_alu_op         = id_to_ex_reg[151:149];
	wire [31:0] ex_alu_a          = id_to_ex_reg[148:117];
	wire [31:0] ex_alu_b          = id_to_ex_reg[116:85];
	wire [1:0]  ex_shift_op       = id_to_ex_reg[84:83];
	wire [31:0] ex_shift_a        = id_to_ex_reg[82:51];
	wire [4:0]  ex_shift_b        = id_to_ex_reg[50:46];
	wire        ex_alu_shift_sel  = id_to_ex_reg[45];
	wire        ex_jump           = id_to_ex_reg[44];
	wire        ex_branch         = id_to_ex_reg[43];
	wire [2:0]  ex_func           = id_to_ex_reg[42:40];
	wire        ex_load_id        = id_to_ex_reg[39];
	wire        ex_store_id       = id_to_ex_reg[38];
	wire        ex_rf_wen         = id_to_ex_reg[37];
	wire [4:0]  ex_rf_waddr       = id_to_ex_reg[36:32];
	wire [31:0] ex_rdata2_true    = id_to_ex_reg[31:0];

	wire alu_overflow_unused;
	wire alu_carry_unused;
	wire alu_zero;
	wire [31:0] alu_result;
	alu ALU(
		.A        (ex_alu_a),
		.B        (ex_alu_b),
		.ALUop    (ex_alu_op),
		.Overflow (alu_overflow_unused),
		.CarryOut (alu_carry_unused),
		.Zero     (alu_zero),
		.Result   (alu_result)
	);

	wire [31:0] shifter_result;
	shifter Shifter(
		.A       (ex_shift_a),
		.B       (ex_shift_b),
		.Shiftop (ex_shift_op),
		.Result  (shifter_result)
	);

	wire ex_branch_check =
		(ex_func == 3'b000) ? alu_zero :
		(ex_func == 3'b001) ? ~alu_zero :
		((ex_func == 3'b100) || (ex_func == 3'b110)) ? ~alu_zero :
		((ex_func == 3'b101) || (ex_func == 3'b111)) ? alu_zero :
		1'b0;

	wire ex_branch_real = ex_branch_check && ex_branch;
	wire [63:0] mul_result = {64{ex_mul}} & (ex_alu_a * ex_alu_b);
	wire [31:0] ex_result =
		((ex_opcode == JAL_OP) || (ex_opcode == JALR_OP)) ? (ex_pc + 32'd4) :
		(ex_opcode == AUIPC_OP) ? (ex_pc + ex_u_imm) :
		(ex_opcode == LUI_OP) ? ex_u_imm :
		ex_mul ? mul_result[31:0] :
		ex_alu_shift_sel ? shifter_result :
		alu_result;

	reg ex_block_cancel;
	always @(posedge clk) begin
		if (rst) begin
			ex_block_cancel <= 1'b1;
		end else if (id_to_ex_valid) begin
			ex_block_cancel <= 1'b0;
		end else begin
			ex_block_cancel <= 1'b1;
		end
	end

	assign prediction_incorrect = (ex_branch_real ^ ex_prediction) && ~ex_block_cancel;
	assign pc_correct = (ex_branch_real || ex_jump) ? ex_prediction_addr : (ex_pc + 32'd4);

	always @(posedge clk) begin
		if (rst) begin
			ex_work <= 1'b0;
		end else if (ex_ready) begin
			ex_work <= id_to_ex_valid;
		end
	end

	assign ex_ready = ~ex_work || mem_ready;
	assign ex_to_mem_valid = ex_work;

	wire [31:0] ex_address_unaligned = ex_result;
	wire [31:0] ex_address = ex_result & 32'hfffffffc;
	wire [1:0] ex_eff = ex_address_unaligned[1:0];
	wire [3:0] ex_write_strb =
		(ex_func == 3'b000) ? ((ex_eff == 2'b00) ? 4'b0001 :
							   (ex_eff == 2'b01) ? 4'b0010 :
							   (ex_eff == 2'b10) ? 4'b0100 :
							   4'b1000) :
		(ex_func == 3'b001) ? ((ex_eff == 2'b00) ? 4'b0011 : 4'b1100) :
		4'b1111;

	wire [7:0] ex_reg_byte_0 = ex_rdata2_true[7:0];
	wire [7:0] ex_reg_byte_1 = ex_rdata2_true[15:8];
	wire [31:0] ex_write_data =
		(ex_func == 3'b000) ? ((ex_eff == 2'b00) ? {{24{1'b0}}, ex_reg_byte_0} :
							   (ex_eff == 2'b01) ? {{16{1'b0}}, ex_reg_byte_0, {8{1'b0}}} :
							   (ex_eff == 2'b10) ? {{8{1'b0}}, ex_reg_byte_0, {16{1'b0}}} :
							   {ex_reg_byte_0, {24{1'b0}}}) :
		(ex_func == 3'b001) ? ((ex_eff == 2'b00) ? {{16{1'b0}}, ex_reg_byte_1, ex_reg_byte_0} :
							   {ex_reg_byte_1, ex_reg_byte_0, {16{1'b0}}}) :
		ex_rdata2_true;

	assign ex_to_id_bypath_data = {
		ex_load_id,
		ex_work && ex_rf_wen,
		ex_rf_waddr,
		ex_result
	};

	wire [181:0] ex_to_mem_data = {
		ex_result,
		ex_func,
		ex_u_imm,
		ex_opcode,
		ex_eff,
		ex_pc,
		ex_address,
		ex_load_id,
		ex_store_id,
		ex_write_strb,
		ex_write_data,
		ex_rf_wen,
		ex_rf_waddr
	};

	always @(posedge clk) begin
		if (rst) begin
			ex_to_mem_reg <= {EX_TO_MEM_WIDTH{1'b0}};
		end else if (mem_ready && ex_to_mem_valid) begin
			ex_to_mem_reg <= ex_to_mem_data;
		end
	end

	wire [31:0] mem_result       = ex_to_mem_reg[181:150];
	wire [2:0]  mem_func         = ex_to_mem_reg[149:147];
	wire [31:0] mem_u_imm        = ex_to_mem_reg[146:115];
	wire [4:0]  mem_opcode       = ex_to_mem_reg[114:110];
	wire [1:0]  mem_eff          = ex_to_mem_reg[109:108];
	wire [31:0] mem_pc           = ex_to_mem_reg[107:76];
	wire [31:0] mem_address_wire = ex_to_mem_reg[75:44];
	wire        mem_load         = ex_to_mem_reg[43];
	wire        mem_store        = ex_to_mem_reg[42];
	wire [3:0]  mem_write_strb_wire = ex_to_mem_reg[41:38];
	wire [31:0] mem_write_data_wire = ex_to_mem_reg[37:6];
	wire        mem_rf_wen_wire  = ex_to_mem_reg[5];
	wire [4:0]  mem_rf_waddr_wire = ex_to_mem_reg[4:0];

	always @(posedge clk) begin
		if (rst) begin
			mem_state <= MEM_INIT;
		end else begin
			mem_state <= mem_next_state;
		end
	end

	always @(*) begin
		case (mem_state)
			MEM_INIT: mem_next_state = MEM_SL_BEFORE;
			MEM_SL_BEFORE: begin
				if (mem_work) begin
					if (mem_load || mem_store) begin
						mem_next_state = MEM_SL;
					end else begin
						mem_next_state = MEM_SL_DONE;
					end
				end else begin
					mem_next_state = MEM_SL_BEFORE;
				end
			end
			MEM_SL: begin
				if (mem_load && Mem_Req_Ready) begin
					mem_next_state = MEM_RDW;
				end else if (mem_store && Mem_Req_Ready) begin
					mem_next_state = MEM_SL_DONE;
				end else begin
					mem_next_state = MEM_SL;
				end
			end
			MEM_RDW: begin
				if (Read_data_Valid && Read_data_Ready) begin
					mem_next_state = MEM_SL_DONE;
				end else begin
					mem_next_state = MEM_RDW;
				end
			end
			MEM_SL_DONE: begin
				if (ex_to_mem_valid) begin
					mem_next_state = MEM_SL_BEFORE;
				end else begin
					mem_next_state = MEM_SL_DONE;
				end
			end
			default: mem_next_state = MEM_INIT;
		endcase
	end

	assign MemRead = mem_load && (mem_state == MEM_SL);
	assign MemWrite = mem_store && (mem_state == MEM_SL);
	assign Read_data_Ready = (mem_state == MEM_RDW) || (mem_state == MEM_INIT);
	assign Address = mem_address_wire;
	assign Write_strb = mem_write_strb_wire;
	assign Write_data = mem_write_data_wire;

	always @(posedge clk) begin
		if (rst) begin
			mem_work <= 1'b0;
		end else if (mem_ready) begin
			mem_work <= ex_to_mem_valid;
		end
	end

	assign mem_ready = ~mem_work || ((mem_state == MEM_SL_DONE) && wb_ready);
	assign mem_to_wb_valid = (mem_state == MEM_SL_DONE) && mem_work;

	always @(posedge clk) begin
		if (rst) begin
			read_data_current <= 32'b0;
		end else if (Read_data_Ready && Read_data_Valid) begin
			read_data_current <= Read_data;
		end
	end

	wire [7:0] read_byte_3 = read_data_current[31:24];
	wire [7:0] read_byte_2 = read_data_current[23:16];
	wire [7:0] read_byte_1 = read_data_current[15:8];
	wire [7:0] read_byte_0 = read_data_current[7:0];

	wire [31:0] mem_rf_wdata =
		((mem_opcode == JAL_OP) || (mem_opcode == JALR_OP)) ? (mem_pc + 32'd4) :
		(mem_opcode == AUIPC_OP) ? (mem_pc + mem_u_imm) :
		(mem_opcode == LUI_OP) ? mem_u_imm :
		(mem_opcode == I_TYPE_L) ?
			((mem_func[1:0] == 2'b00) ?
				((mem_eff == 2'b00) ? ((mem_func[2] == 1'b0) ? {{24{read_byte_0[7]}}, read_byte_0} : {{24{1'b0}}, read_byte_0}) :
				 (mem_eff == 2'b01) ? ((mem_func[2] == 1'b0) ? {{24{read_byte_1[7]}}, read_byte_1} : {{24{1'b0}}, read_byte_1}) :
				 (mem_eff == 2'b10) ? ((mem_func[2] == 1'b0) ? {{24{read_byte_2[7]}}, read_byte_2} : {{24{1'b0}}, read_byte_2}) :
									  ((mem_func[2] == 1'b0) ? {{24{read_byte_3[7]}}, read_byte_3} : {{24{1'b0}}, read_byte_3})) :
			 (mem_func[1:0] == 2'b01) ?
				((mem_eff == 2'b00) ? ((mem_func[2] == 1'b0) ? {{16{read_byte_1[7]}}, read_data_current[15:0]} : {{16{1'b0}}, read_data_current[15:0]}) :
									   ((mem_func[2] == 1'b0) ? {{16{read_byte_3[7]}}, read_data_current[31:16]} : {{16{1'b0}}, read_data_current[31:16]})) :
				read_data_current) :
		mem_result;

	assign mem_to_id_bypath_data = {
		mem_load,
		mem_work && mem_rf_wen_wire,
		mem_rf_waddr_wire,
		mem_rf_wdata
	};

	wire [69:0] mem_to_wb_data = {
		mem_pc,
		mem_rf_waddr_wire,
		mem_rf_wen_wire,
		mem_rf_wdata
	};

	always @(posedge clk) begin
		if (rst) begin
			mem_to_wb_reg <= {MEM_TO_WB_WIDTH{1'b0}};
		end else if (wb_ready && mem_to_wb_valid) begin
			mem_to_wb_reg <= mem_to_wb_data;
		end
	end

	wire [31:0] wb_pc = mem_to_wb_reg[69:38];
	wire [4:0]  wb_rf_waddr = mem_to_wb_reg[37:33];
	wire        wb_rf_wen = mem_to_wb_reg[32];
	wire [31:0] wb_rf_wdata = mem_to_wb_reg[31:0];

	always @(posedge clk) begin
		if (rst) begin
			wb_work <= 1'b0;
		end else if (wb_ready) begin
			wb_work <= mem_to_wb_valid;
		end
	end

	assign wb_ready = 1'b1;
	wire inst_retire_valid = wb_work;
	wire inst_wen = inst_retire_valid && wb_rf_wen;
	assign inst_retire = {inst_wen, wb_rf_waddr, wb_rf_wdata, wb_pc};

	assign wb_to_id_bypath_data = {
		wb_rf_wen,
		wb_rf_waddr,
		wb_rf_wdata
	};

	assign rf_waddr_wb = wb_rf_waddr;
	assign rf_wdata_wb = wb_rf_wdata;
	assign rf_wen_wb = wb_rf_wen && inst_retire_valid;

	always @(posedge clk) begin
		if (rst) begin
			inst_cnt <= 32'd0;
		end else if (Inst_Ready && Inst_Valid) begin
			inst_cnt <= inst_cnt + 32'd1;
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			mem_cnt <= 32'd0;
		end else if (Read_data_Ready && Read_data_Valid) begin
			mem_cnt <= mem_cnt + 32'd1;
		end
	end

	assign cpu_perf_cnt_1 = inst_cnt;
	assign cpu_perf_cnt_2 = mem_cnt;
	assign cpu_perf_cnt_3 = 32'd0;
	assign cpu_perf_cnt_4 = 32'd0;
	assign cpu_perf_cnt_5 = 32'd0;
	assign cpu_perf_cnt_6 = 32'd0;
	assign cpu_perf_cnt_7 = 32'd0;
	assign cpu_perf_cnt_8 = 32'd0;
	assign cpu_perf_cnt_9 = 32'd0;
	assign cpu_perf_cnt_10 = 32'd0;
	assign cpu_perf_cnt_11 = 32'd0;
	assign cpu_perf_cnt_12 = 32'd0;
	assign cpu_perf_cnt_13 = 32'd0;
	assign cpu_perf_cnt_14 = 32'd0;
	assign cpu_perf_cnt_15 = 32'd0;

endmodule
