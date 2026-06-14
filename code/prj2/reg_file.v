`timescale 10 ns / 1 ns

`define DATA_WIDTH 32
`define ADDR_WIDTH 5

module reg_file(
	input                       clk,
	input  [`ADDR_WIDTH - 1:0]  waddr,
	input  [`ADDR_WIDTH - 1:0]  raddr1,
	input  [`ADDR_WIDTH - 1:0]  raddr2,
	input                       wen,
	input  [`DATA_WIDTH - 1:0]  wdata,
	output [`DATA_WIDTH - 1:0]  rdata1,
	output [`DATA_WIDTH - 1:0]  rdata2
);

	// TODO: Please add your logic design here
	// 定义32个32位寄存器
	reg [`DATA_WIDTH-1:0] regs [2**`ADDR_WIDTH - 1:0];

	// 异步读操作 组合逻辑
	// 0号寄存器恒输出0
	assign rdata1 = (raddr1 == {`ADDR_WIDTH{1'b0}}) ? {`DATA_WIDTH{1'b0}} : regs[raddr1];
	assign rdata2 = (raddr2 == {`ADDR_WIDTH{1'b0}}) ? {`DATA_WIDTH{1'b0}} : regs[raddr2];

	// 同步写操作 时钟上升沿触发
	always @(posedge clk) begin
		// 写使能有效 且 不是0号寄存器时才写入
		if (wen && (waddr != {`ADDR_WIDTH{1'b0}})) begin
			regs[waddr] <= wdata;
		end
	end

endmodule
