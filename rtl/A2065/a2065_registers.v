/*
 * a2065_registers.v
 *
 * DTACK-stretch state machine for A2065 chip register accesses (RAP/RDP).
 *
 * When the 68k accesses the 4-byte chip register region (card+0x4000),
 * this module:
 *   1. Holds the 68k bus (asserts DTACK override / wait states)
 *   2. Signals the ARM daemon via bridge registers
 *   3. Waits for ARM to set DONE
 *   4. Releases the bus with the ARM's response on the data bus
 *
 * Watchdog: if ARM does not respond within WATCHDOG_CYCLES, the module
 * releases the bus with a bus error to prevent a hard system lockup.
 *
 * Bridge register interface (8 bytes mapped via HPS2FPGA bridge):
 *   bridge[0:1]  data (write: from 68k; read: set by ARM before DONE)
 *   bridge[2]    addr offset (0=RDP, 2=RAP)
 *   bridge[3]    rw (0=read, 1=write)
 *   bridge[4]    NEW_REQ (FPGA writes 1 on new access, ARM clears on service)
 *   bridge[5]    DONE (ARM writes 1 when result ready, FPGA clears)
 *   bridge[6:7]  result data (ARM writes read result here)
 */

module a2065_registers #(
    parameter WATCHDOG_CYCLES = 700000  /* ~10ms at 70MHz */
) (
    input  wire        clk,
    input  wire        rst_n,

    /* Card address range (from autoconfig) */
    input  wire [7:0]  card_base,
    input  wire        card_configured,

    /* 68k bus */
    input  wire [23:0] cpu_addr,
    input  wire        cpu_rw,
    input  wire        cpu_as_n,
    input  wire        cpu_ds_n,        /* data strobe */
    input  wire [15:0] cpu_data_in,
    output reg  [15:0] cpu_data_out,
    output reg         cpu_dtack_n,     /* active low, held until ARM done */
    output reg         cpu_berr_n,      /* bus error output, active low */

    /* Bridge register interface (ARM reads/writes these) */
    output reg  [15:0] bridge_data,     /* 68k write data / read address */
    output reg  [7:0]  bridge_addr_off, /* 0x00=RDP, 0x02=RAP */
    output reg         bridge_rw,       /* 1=write, 0=read */
    output reg         bridge_new_req,  /* strobe to ARM */
    input  wire        bridge_done,     /* ARM sets when result ready */
    input  wire [15:0] bridge_result,   /* ARM's read result */
    output reg         bridge_done_clr  /* FPGA clears DONE after latching */
);

    /* ── Address decode ─────────────────────────────────────────────── */
    /* Chip register region: card_base<<16 + 0x4000 .. +0x4003          */
    wire sel_chipreg = card_configured &&
                       (cpu_addr[23:16] == card_base) &&
                       (cpu_addr[15:2]  == 14'h1000) && /* 0x4000>>2 */
                       (!cpu_as_n) &&
                       (!cpu_ds_n);

    /* ── State machine ──────────────────────────────────────────────── */
    localparam ST_IDLE      = 2'd0;
    localparam ST_WAIT_ARM  = 2'd1;
    localparam ST_RELEASE   = 2'd2;
    localparam ST_BERR      = 2'd3;

    reg [1:0]  state;
    reg [19:0] watchdog;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            cpu_dtack_n    <= 1'b1;
            cpu_berr_n     <= 1'b1;
            cpu_data_out   <= 16'hFFFF;
            bridge_new_req <= 1'b0;
            bridge_done_clr<= 1'b0;
            bridge_data    <= 16'h0000;
            bridge_addr_off<= 8'h00;
            bridge_rw      <= 1'b0;
            watchdog       <= 20'h0;
        end else begin
            bridge_done_clr <= 1'b0; /* default: not clearing */

            case (state)
            ST_IDLE: begin
                cpu_dtack_n <= 1'b1;
                cpu_berr_n  <= 1'b1;
                if (sel_chipreg) begin
                    /* Capture access details */
                    bridge_data     <= cpu_data_in;
                    bridge_addr_off <= {6'b0, cpu_addr[1:0]};
                    bridge_rw       <= ~cpu_rw; /* bus rw: 1=read → bridge rw: 0=read */
                    bridge_new_req  <= 1'b1;
                    watchdog        <= 20'h0;
                    state           <= ST_WAIT_ARM;
                end
            end

            ST_WAIT_ARM: begin
                bridge_new_req <= 1'b1; /* hold until ARM acknowledges */
                watchdog <= watchdog + 1;

                if (bridge_done) begin
                    /* ARM has result ready */
                    bridge_done_clr <= 1'b1;
                    bridge_new_req  <= 1'b0;
                    cpu_data_out    <= bridge_result;
                    state           <= ST_RELEASE;
                end else if (watchdog >= WATCHDOG_CYCLES[19:0]) begin
                    /* ARM didn't respond — bus error */
                    bridge_new_req <= 1'b0;
                    state          <= ST_BERR;
                end
            end

            ST_RELEASE: begin
                cpu_dtack_n  <= 1'b0;  /* assert DTACK (active low) */
                if (cpu_as_n) begin    /* 68k deasserts AS on next cycle */
                    cpu_dtack_n <= 1'b1;
                    state       <= ST_IDLE;
                end
            end

            ST_BERR: begin
                cpu_berr_n <= 1'b0;    /* assert bus error */
                if (cpu_as_n) begin
                    cpu_berr_n <= 1'b1;
                    state      <= ST_IDLE;
                end
            end
            endcase
        end
    end

endmodule
