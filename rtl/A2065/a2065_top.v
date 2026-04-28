/*
 * a2065_top.v
 *
 * Top-level integration module for A2065 ZorroII Ethernet emulation.
 *
 * Instantiates:
 *   a2065_autoconfig  — ZorroII autoconfig ROM + state machine
 *   a2065_registers   — DTACK-stretch for RAP/RDP chip register access
 *
 * boardram (32KB) is NOT instantiated here — it is mapped directly
 * through the HPS2FPGA lightweight bridge window. The FPGA just needs
 * to decode the address and assert DTACK for that range.
 *
 * Integration checklist (see IMPLEMENTATION_PLAN.md Step 9):
 *   [ ] Add this module to Minimig RTL hierarchy
 *   [ ] Connect ZorroII expansion bus signals
 *   [ ] Assign HPS2FPGA bridge window (64KB @ BRIDGE_PHYS_BASE)
 *   [ ] Wire int2_n output to Minimig interrupt controller
 *   [ ] Add enable bit in OSD/config register
 */

module a2065_top (
    input  wire        clk,
    input  wire        rst_n,

    /* ── 68k bus ──────────────────────────────────────────────────── */
    input  wire [23:0] cpu_addr,
    input  wire        cpu_rw,
    input  wire        cpu_as_n,
    input  wire        cpu_ds_n,
    input  wire [15:0] cpu_data_in,
    output wire [15:0] cpu_data_out,
    output wire        cpu_dtack_n,
    output wire        cpu_berr_n,

    /* ── ARM bridge interface ─────────────────────────────────────── */
    /* Chip register bridge (8 bytes) */
    output wire [15:0] bridge_data,
    output wire [7:0]  bridge_addr_off,
    output wire        bridge_rw,
    output wire        bridge_new_req,
    input  wire        bridge_done,
    input  wire [15:0] bridge_result,
    output wire        bridge_done_clr,

    /* MAC bytes from ARM (written before Amiga boot) */
    input  wire [7:0]  mac_byte2,
    input  wire [7:0]  mac_byte3,
    input  wire [7:0]  mac_byte4,
    input  wire [7:0]  mac_byte5,

    /* Interrupt to 68k (active low, ZorroII INT2) */
    output wire        int2_n,

    /* Interrupt request from ARM daemon */
    input  wire        arm_int_req,

    /* Enable (from OSD config) */
    input  wire        a2065_enabled
);

    /* ── Internal signals ─────────────────────────────────────────── */
    wire [7:0]  card_base;
    wire        card_configured;
    wire        card_shutup;

    wire [15:0] autoconfig_data_out;
    wire        autoconfig_dtack_n;

    wire [15:0] regs_data_out;
    wire        regs_dtack_n;
    wire        regs_berr_n;

    /* ── Autoconfig ───────────────────────────────────────────────── */
    a2065_autoconfig u_autoconfig (
        .clk            (clk),
        .rst_n          (rst_n && a2065_enabled),
        .cpu_addr       (cpu_addr),
        .cpu_rw         (cpu_rw),
        .cpu_as_n       (cpu_as_n),
        .cpu_data_in    (cpu_data_in),
        .cpu_data_out   (autoconfig_data_out),
        .cpu_dtack_n    (autoconfig_dtack_n),
        .mac_byte2      (mac_byte2),
        .mac_byte3      (mac_byte3),
        .mac_byte4      (mac_byte4),
        .mac_byte5      (mac_byte5),
        .card_base      (card_base),
        .card_configured(card_configured),
        .card_shutup    (card_shutup)
    );

    /* ── Chip registers (RAP/RDP) ─────────────────────────────────── */
    a2065_registers u_registers (
        .clk            (clk),
        .rst_n          (rst_n && a2065_enabled),
        .card_base      (card_base),
        .card_configured(card_configured),
        .cpu_addr       (cpu_addr),
        .cpu_rw         (cpu_rw),
        .cpu_as_n       (cpu_as_n),
        .cpu_ds_n       (cpu_ds_n),
        .cpu_data_in    (cpu_data_in),
        .cpu_data_out   (regs_data_out),
        .cpu_dtack_n    (regs_dtack_n),
        .cpu_berr_n     (regs_berr_n),
        .bridge_data    (bridge_data),
        .bridge_addr_off(bridge_addr_off),
        .bridge_rw      (bridge_rw),
        .bridge_new_req (bridge_new_req),
        .bridge_done    (bridge_done),
        .bridge_result  (bridge_result),
        .bridge_done_clr(bridge_done_clr)
    );

    /* ── boardram DTACK (direct HPS2FPGA, no ARM mediation needed) ── */
    /* The boardram region (card+0x8000 to card+0xFFFF) is mapped       */
    /* directly through the HPS2FPGA bridge. Standard DTACK timing.     */
    wire sel_boardram = card_configured &&
                        (cpu_addr[23:16] == card_base) &&
                        (cpu_addr[15] == 1'b1) &&
                        (!cpu_as_n);
    reg boardram_dtack_n;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) boardram_dtack_n <= 1'b1;
        else        boardram_dtack_n <= sel_boardram ? 1'b0 : 1'b1;

    /* ── Output mux ───────────────────────────────────────────────── */
    assign cpu_data_out = (!autoconfig_dtack_n) ? autoconfig_data_out :
                          (!regs_dtack_n)        ? regs_data_out       :
                                                   16'hFFFF;

    assign cpu_dtack_n  = autoconfig_dtack_n & regs_dtack_n & boardram_dtack_n;
    assign cpu_berr_n   = regs_berr_n;

    /* ── Interrupt ────────────────────────────────────────────────── */
    /* ARM daemon asserts arm_int_req when RINT/TINT+INEA conditions met */
    assign int2_n = ~arm_int_req;

endmodule
