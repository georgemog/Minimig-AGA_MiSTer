/*
 * a2065_boardram.v
 *
 * 32KB dual-port boardram for A2065 Ethernet emulation.
 *
 * Port A: 68k ZorroII bus (read/write at card+0x8000..card+0xFFFF)
 * Port B: ARM daemon (for DDR3 mailbox boardram access)
 *
 * Separate hi/lo byte arrays with no_rw_check attribute for
 * Quartus TDP M10K inference across two clock domains.
 */

module a2065_boardram (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [23:1] cpu_addr,
    input  wire [15:0] cpu_data_in,
    output reg  [15:0] cpu_data_out,
    input  wire        cpu_rd,
    input  wire        cpu_hwr,
    input  wire        cpu_lwr,
    input  wire        sel,

    input  wire        clk_b,
    input  wire [14:1] arm_addr,
    input  wire [15:0] arm_data_in,
    output reg  [15:0] arm_rdata,
    input  wire        arm_wr,
    input  wire  [1:0] arm_be
);

    wire sel_boardram = sel && cpu_addr[15];

    wire [13:0] ram_addr_a = cpu_addr[14:1];
    wire [13:0] ram_addr_b = arm_addr[14:1];

    (* ramstyle = "no_rw_check, M10K" *) reg [7:0] ram_hi [0:16383];
    (* ramstyle = "no_rw_check, M10K" *) reg [7:0] ram_lo [0:16383];

    reg [15:0] ram_rd;

    always @(posedge clk) begin
        if (sel_boardram && cpu_hwr)
            ram_hi[ram_addr_a] <= cpu_data_in[15:8];
        if (sel_boardram && cpu_lwr)
            ram_lo[ram_addr_a] <= cpu_data_in[7:0];
        ram_rd <= {ram_hi[ram_addr_a], ram_lo[ram_addr_a]};
    end

    always @(*) begin
        cpu_data_out = sel_boardram ? ram_rd : 16'h0000;
    end

    reg [15:0] ram_rd_b;

    always @(posedge clk_b) begin
        if (arm_wr) begin
            if (arm_be[1]) ram_hi[ram_addr_b] <= arm_data_in[15:8];
            if (arm_be[0]) ram_lo[ram_addr_b] <= arm_data_in[7:0];
        end
        ram_rd_b <= {ram_hi[ram_addr_b], ram_lo[ram_addr_b]};
    end

    always @(*) begin
        arm_rdata = ram_rd_b;
    end

endmodule
