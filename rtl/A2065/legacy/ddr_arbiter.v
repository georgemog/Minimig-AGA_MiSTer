module ddr_arbiter
(
	input  wire        clk,

	output wire        DDRAM_CLK,
	output wire [7:0]  DDRAM_BURSTCNT,
	input  wire        DDRAM_BUSY,
	output wire [28:0] DDRAM_ADDR,
	output wire [63:0] DDRAM_DIN,
	output wire [7:0]  DDRAM_BE,
	output wire        DDRAM_RD,
	output wire        DDRAM_WE,
	input  wire [63:0] DDRAM_DOUT,
	input  wire        DDRAM_DOUT_READY,

	input  wire [28:0] m0_addr,
	input  wire [63:0] m0_din,
	input  wire [7:0]  m0_be,
	input  wire        m0_rd,
	input  wire        m0_we,
	output wire [63:0] m0_dout,
	output wire        m0_dout_ready,

	input  wire [28:0] m1_addr,
	input  wire [63:0] m1_din,
	input  wire [7:0]  m1_be,
	input  wire        m1_rd,
	input  wire        m1_we,
	output wire [63:0] m1_dout,
	output wire        m1_dout_ready,
	output wire        m1_bus_avail
);

assign DDRAM_CLK = clk;
assign DDRAM_BURSTCNT = 8'd1;

reg grant;
reg pend_rd_m0;
reg pend_rd_m1;

always @(posedge clk) begin
	if (DDRAM_DOUT_READY) begin
		pend_rd_m0 <= 0;
		pend_rd_m1 <= 0;
	end

	if (!pend_rd_m0 && !pend_rd_m1) begin
		if (m0_rd || m0_we) begin
			grant <= 0;
			pend_rd_m0 <= m0_rd;
		end else if (m1_rd || m1_we) begin
			grant <= 1;
			pend_rd_m1 <= m1_rd;
		end
	end
end

assign DDRAM_ADDR = grant ? m1_addr : m0_addr;
assign DDRAM_DIN  = grant ? m1_din  : m0_din;
assign DDRAM_BE   = grant ? m1_be   : m0_be;
assign DDRAM_RD   = grant ? m1_rd   : m0_rd;
assign DDRAM_WE   = grant ? m1_we   : m0_we;

assign m0_dout        = DDRAM_DOUT;
assign m0_dout_ready  = (~grant & pend_rd_m0) ? DDRAM_DOUT_READY : 1'b0;
assign m1_dout        = DDRAM_DOUT;
assign m1_dout_ready  = (grant & pend_rd_m1)  ? DDRAM_DOUT_READY : 1'b0;

assign m1_bus_avail = !m0_rd && !m0_we && !pend_rd_m0 && !pend_rd_m1;

endmodule
