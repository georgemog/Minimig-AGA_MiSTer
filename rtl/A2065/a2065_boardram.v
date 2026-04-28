/*
 * a2065_boardram.v
 *
 * 32KB dual-port boardram for A2065 Ethernet emulation.
 *
 * Port A: 68k ZorroII bus (read/write at card+0x8000..card+0xFFFF)
 * Port B: ARM bridge (for daemon access via HPS2FPGA)
 *
 * The 68k side uses sel_a2065 from gary + internal address bit 15
 * to decode the boardram region. Data output is gated by sel_boardram
 * so it drives 0 when not selected (safe for OR-tie into cpu_data_in).
 *
 * DTACK for this region is handled by the Minimig 68000 bridge
 * automatically — no explicit DTACK output is needed from this module.
 * The RAM is synchronous and data is available within 1 clock cycle,
 * well within the fixed expansion-card DTACK window (~3-4 CCK clocks).
 */

module a2065_boardram (
    input  wire        clk,
    input  wire        rst_n,

    /* ── 68k bus (Port A) ─────────────────────────────────────────── */
    input  wire [23:1] cpu_addr,
    input  wire [15:0] cpu_data_in,
    output reg  [15:0] cpu_data_out,
    input  wire        cpu_rd,
    input  wire        cpu_hwr,
    input  wire        cpu_lwr,
    input  wire        sel,

    /* ── ARM bridge (Port B) ──────────────────────────────────────── */
    input  wire [14:1] arm_addr,
    input  wire [15:0] arm_data_in,
    input  wire        arm_wr,
    input  wire        arm_sel
);

    /* ── Address decode ─────────────────────────────────────────────── */
    wire sel_boardram = sel && cpu_addr[15];

    wire [13:0] ram_addr_a = cpu_addr[14:1];
    wire [13:0] ram_addr_b = arm_addr[14:1];

    reg [15:0] ram [0:16383];
    reg [15:0] ram_rd;

    always @(posedge clk) begin
        if (sel_boardram && ~cpu_rd)
            ram[ram_addr_a] <= cpu_data_in;
    end

    always @(posedge clk) begin
        ram_rd <= ram[ram_addr_a];
    end

    always @(*) begin
        cpu_data_out = sel_boardram ? ram_rd : 16'h0000;
    end

endmodule
