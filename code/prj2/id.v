//Instruction Recode，指令译码器，解析指令并生成所有控制信号

`timescale 10ns / 1ns
`include "define.v"

module id(
	input             clk,

	input  [31:0]	  PC,
	input  [31:0]     Instruction,


	output [4:0]	  waddr,
	output [4:0]	  raddr1,
	output [4:0]	  raddr2,
	
	//定义一些控制信号
	output		Regdst,
	output 		Branch,
	output		MemRead,
	output	        MemWrite,
	output 		MemtoReg,
	output		ALUSrc,
	output [2:0]    ALUop,
	output [1:0]	Shiftop,
	output		RegWrite,
	output		Jump,

	//ALU和Shifter二者二选一的选择信号
	output		AluShi_sel,

	//ALU的操作数
	output [31:0]	ALUop_A,
	output [31:0]	ALUop_B,

	//Shifter的操作数
	output [31:0]	Shiftop_A,
	output [4:0]	Shiftop_B,

	//与内存有关操作的控制信号, 符号扩展和字长
	output 		Ext,
	output [1:0]	memLen,	//2'b00字节, 2'b01半字, 2'b10字	


	//有关分支的offset输出
	output [15:0]	offset,

	//长跳转的位置指令
	output [25:0]	instr_index,

	//分支和跳转的目标地址
	output [31:0]	Jump_addr,
	output [31:0]	Branch_addr,

	//从寄存器中读出来的两个数据,用于ALUop和shiftop的选择
	input [31:0]	rdata1,
	input [31:0]	rdata2
	);
	
	//进行R-type指令分块赋值
	wire [5:0] opcode = Instruction [31:26];
	wire [4:0] rs	  = Instruction [25:21];//第一个寄存器编号
	wire [4:0] rt	  = Instruction [20:16];//第二个寄存器编号
	wire [4:0] rd     = Instruction [15:11];//目标寄存器编号
	wire [4:0] shamt  = Instruction [10:6];//移位位数
	wire [5:0] func   = Instruction [5:0];//R型指令功能码
	assign offset     = Instruction [15:0];//分支指令偏移量
	wire [15:0] imm	  = Instruction [15:0];//I型指令立即数
	wire [4:0] base   = Instruction [25:21];//访问基地址寄存器
	wire [4:0] REG    = Instruction [20:16];//REGIMM类指令立即数
	assign instr_index = Instruction [25:0];//跳转指令立即数
	
	assign MemRead  = opcode[5] & ~opcode[3];//读内存
	assign MemWrite = opcode[5] & opcode[3];//写内存
	assign MemtoReg = MemRead;
	
	assign RegDst = (opcode==`R_TYPE)? 1:0;//控制寄存器写地址选择，0就用rt，1就用rd
	assign ALUSrc = (opcode==`R_TYPE || opcode[5:1]==5'b00010)? 0:1;//ALU第二个操作数来源，0来自rdata2,1来自立即数扩展后的值
	assign Branch = (opcode[5:2]==4'b0001 || opcode==`REGIMM);
	assign Jump   = (opcode[5:1]==5'b00001 || (opcode==`R_TYPE && func[3:1]==3'b100) || opcode==`JAL);
	//运算器功能选择信号 
	assign ALUop =  ((opcode[5]==1) || (opcode==`ADDIU) || (opcode==`R_TYPE && (func==`ADDU || func[5:3]==3'b001)))? 	`ADD :	//用到add的情况
	                ((opcode==`R_TYPE && func==`SUBU) || opcode[5:1]==5'b00010)?						`SUB :  //用到sub的情况
		        ((opcode==`R_TYPE && func==`AND_) || opcode==`ANDI)?							`AND :  //用到and的情况
		        ((opcode==`R_TYPE && func==`OR_) || opcode==`ORI)?							`OR  :	//用到or的情况
	                ((opcode==`R_TYPE && func==`XOR_) || opcode==`XORI)?							`XOR :  //用到xor的情况
		        (opcode==`R_TYPE && func==`NOR_)?									`NOR :  //用到NOR的情况
		        ((opcode==`R_TYPE && func==`SLT_) || opcode==`SLTI || opcode==`REGIMM || opcode[5:1]==5'b00011)?	`SLT : 	//用到SLT的情况
		        ((opcode==`R_TYPE && func==`SLTU_) || opcode==`SLTIU)?							`SLTU:	//用到SLTU的情况
			`OR;	//有的情况不需要ALU,默认赋值为or
															
	//移位器选择信号
	assign Shiftop = ((opcode==`R_TYPE && func[5:3]==3'b000))? 	func[1:0] :			//Rtype算数移位指令
		         ((opcode==`LUI))? 			   	2'b00     :			//加载到高位
		 	2'b01;				//其他情况下不移位	
	
	assign AluShi_sel = ((opcode==`R_TYPE && func[5:3]==3'b000) || opcode==`LUI);	//最终结果来源，ALU还是移位器		//结果为1,选择shifter,否则选择alu
	
	//内存读出时的拓展控制信号
	assign Ext =	(opcode[5:4]==2'b10 && (opcode[2]==0))? 	1 : 	//符号扩展
								        0;  	//零扩展
	assign memLen = ({opcode[5:4],opcode[1:0]}==4'b1000)?		2'b00:	//字节
		        ({opcode[5:4],opcode[1:0]}==4'b1001)?		2'b01:	//半字
		        ({opcode[5:4],opcode[1:0]}==4'b1010)?		2'b10:	//低两位为10的时候是非对齐, 用10来标记非对齐
		        ({opcode[5:4],opcode[1:0]}==4'b1011)?		2'b11:	//字
					     			        2'b00;	//默认	
	
	//读寄存器地址
	assign raddr1 = rs;
	assign raddr2 = rt;
	//写寄存器地址
	assign waddr  =	(RegDst==1)?		rd:
		        (opcode==`JAL)?		5'b11111:
					        rt;
	
	//定义一个中间控制信号,用于控制movn和movz
	wire mov_con;
	assign mov_con = (rdata2 == 32'b0);
	
	//定义寄存器写使能信号
	assign RegWrite    = 	(opcode==`R_TYPE && func==`JR)?									0://JR时不写入
			        ((opcode==`R_TYPE && {func[5:3],func[1]}!=4'b0011) || opcode[5:3]==3'b001 || MemRead)? 	1:
	       		        (opcode==`R_TYPE && func==`MOVZ)?								mov_con://rt==0则写入
			        (opcode==`R_TYPE && func==`MOVN)?								~mov_con://rt!=0则写入
			        (opcode==`JAL)?											1://JAL的情况, 拉高wen
				                                                                                                0;//其他情况下不写入
																
	//对立即数进行拓展(零拓展和符号位拓展，16变32)
	wire [31:0]  op_imm;
	assign op_imm=(opcode[5:2]==4'b0011)?{{16{1'b0}},imm}://零扩展
					     {{16{imm[15]}},imm};//符号扩展
								
	//对ALU中两个操作数赋值
	assign ALUop_A    =	(opcode==`BGTZ)?			32'b0:		//要判断rdata1>0，ALU做的运算是：rdata1-0，所以ALUop_A 必须给0
			        (opcode==`REGIMM && REG[0]==1)?		{32{1'b1}}:	//判断>=0，ALU做的运算：rdata1-(-1)		
				rdata1;
	//MOVZ：rs == 0 → 把 rt 赋值给 rd，	MOVN：rs != 0 → 把 rt 赋值给 rd						
	assign ALUop_B	  =	(opcode==`R_TYPE && (func==`MOVZ || func==`MOVN))?		32'b0:		//对于R中的两个移动指令,ALUop为add,因此rdata1+0
				(opcode==`REGIMM && REG[0]==0)?					32'b0:		//rdata1小于0时分支
				(opcode==`BLEZ)?						32'b1:		//rdata1小于1时分支,也就是小于等于0时分支
				(opcode==`BGTZ || (opcode==`REGIMM && REG[0]==1))?		rdata1:		//对于上面的两种情况,B应该是rdata1
				(ALUSrc)?							op_imm:
												rdata2;


	//对Shifter中的两个操作数赋值
	assign Shiftop_A=(opcode==`LUI)?op_imm:		//LUI指令对立即数做移位
					rdata2;		//rt移动
	assign Shiftop_B=(opcode==`R_TYPE && rs==5'b0)?	shamt:
		         (opcode==`LUI)? 5'b10000:	//LUI指令将立即数左移16位
					rdata1[4:0];	//可变目标左右移量为rs[4:0]

	//计算出分支目标地址
	wire [15:0]	offset_temp;//定义一个临时16位变量，存中间结果
	assign offset_temp  =  offset << 2;//MIPS 指令是32位，地址必须按4对齐，所以偏移量要×4
	assign Branch_addr  =   {{16{offset_temp[15]}},offset_temp};

	//计算出跳转目标地址
	assign Jump_addr    =	(opcode[5:1]==5'b00001)?	{PC[31:28],instr_index,2'b00} :	//J型指令,j,jal
							rdata1;				//R型跳转指令,jr,jalr


	endmodule
