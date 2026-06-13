/*
 * a2065_registers.v
 *
 * Am7990 LANCE register access for A2065 Ethernet emulation.
 *
 * Two modes:
 *   1. ARM bridge mode: DTACK-stretch with ARM daemon handling CSR state.
 *      When bridge_done is connected to a real signal, the module holds
 *      the 68k bus until ARM responds.
 *
 *   2. Local passthrough mode: when BRIDGE_LOCAL is set (or bridge_done
 *      is tied to 0), a small CSR register file in BRAM responds directly
 *      without holding the bus. This allows basic Amiga-side testing
 *      before the ARM bridge is wired up.
 *
 * Bridge register interface (8 bytes mapped via HPS2FPGA bridge):
 *   bridge[0:1]  data (write: from 68k; read: set by ARM before DONE)
 *   bridge[2]    addr offset (0=RDP, 0x02=RAP)
 *   bridge[3]    rw (0=read, 1=write)
 *   bridge[4]    NEW_REQ (FPGA writes 1 on new access, ARM clears)
 *   bridge[5]    DONE (ARM writes 1 when result ready, FPGA clears)
 *   bridge[6:7]  result data (ARM writes read result here)
 */

module a2065_registers #(
    parameter WATCHDOG_CYCLES = 700000,
    parameter BRIDGE_LOCAL    = 1
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  card_base,
    input  wire        card_configured,

    input  wire [23:0] cpu_addr,
    input  wire        cpu_rw,
    input  wire        cpu_as_n,
    input  wire        cpu_ds_n,
    input  wire [15:0] cpu_data_in,
    output reg  [15:0] cpu_data_out,
    output reg         cpu_dtack_n,
    output reg         cpu_berr_n,

    output reg  [15:0] bridge_data,
    output reg  [7:0]  bridge_addr_off,
    output reg         bridge_rw,
    output reg         bridge_new_req,
    input  wire        bridge_done,
    input  wire [15:0] bridge_result,
    output reg         bridge_done_clr,

    output wire        regs_nrdy
);

    wire sel_chipreg = card_configured &&
                       (cpu_addr[23:16] == card_base) &&
                       (cpu_addr[15:2]  == 14'h1000) &&
                       (!cpu_as_n) &&
                       (!cpu_ds_n);

    localparam ST_IDLE      = 2'd0;
    localparam ST_WAIT_ARM  = 2'd1;
    localparam ST_RELEASE   = 2'd2;
    localparam ST_BERR      = 2'd3;

    reg [1:0]  state;
    reg [19:0] watchdog;

    assign regs_nrdy = BRIDGE_LOCAL ? 1'b0 : ((state == ST_WAIT_ARM) || (sel_chipreg && state == ST_IDLE));

    generate
    if (BRIDGE_LOCAL) begin : gen_local

        reg [15:0] csr [0:127];
        reg [6:0]  rap;
        reg [15:0] local_out;
        reg        local_out_en;
        reg [15:0] csr0_next;

        initial begin
            csr[0] = 16'h0004;
            csr[4] = 16'h0115;
        end

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                rap          <= 7'd0;
                local_out_en <= 1'b0;
                local_out    <= 16'h0000;
                csr[0]       <= 16'h0004;
                csr[4]       <= 16'h0115;
            end else begin
                local_out_en <= 1'b0;

                if (sel_chipreg) begin
                    if (cpu_addr[1:0] == 2'b10) begin
                        if (!cpu_rw)
                            rap <= cpu_data_in[6:0];
                    end else begin
                        if (!cpu_rw) begin
                            case (rap)
                            7'd0: begin
                                csr0_next = csr[0];
                                csr0_next = (csr0_next & ~16'h0040) | (cpu_data_in & 16'h0040);
                                csr0_next = csr0_next | (cpu_data_in & (16'h0001 | 16'h0002 | 16'h0004 | 16'h0008));
                                csr0_next = csr0_next & ~(cpu_data_in & (16'h0100 | 16'h0200 | 16'h0400 |
                                                                          16'h0800 | 16'h1000 | 16'h2000 | 16'h4000));
                                csr0_next = csr0_next & ~16'h8000;
                                if ((cpu_data_in & 16'h0004) && (~csr0_next & 16'h0004))
                                    csr0_next = 16'h0004;
                                csr[0] <= csr0_next;
                            end
                            7'd1: if (csr[0] & 16'h0004) csr[1] <= cpu_data_in & ~16'h0001;
                            7'd2: if (csr[0] & 16'h0004) csr[2] <= cpu_data_in & 16'h00FF;
                            7'd3: if (csr[0] & 16'h0004) csr[3] <= cpu_data_in & 16'h0007;
                            default: csr[rap] <= cpu_data_in;
                            endcase
                        end else begin
                            local_out_en <= 1'b1;
                            case (rap)
                            7'd0: begin
                                local_out <= csr[0];
                                if (csr[0] & (16'h4000 | 16'h2000 | 16'h1000 | 16'h0800))
                                    local_out <= csr[0] | 16'h8000;
                            end
                            7'd88: local_out <= 16'h0001;
                            7'd89: local_out <= 16'h3003;
                            default: local_out <= csr[rap];
                            endcase
                        end
                    end
                end
            end
        end

        always @(*) begin
            cpu_data_out = local_out_en ? local_out : 16'h0000;
        end

    end else begin : gen_bridge

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                state          <= ST_IDLE;
                cpu_dtack_n    <= 1'b1;
                cpu_berr_n     <= 1'b1;
                cpu_data_out   <= 16'h0000;
                bridge_new_req <= 1'b0;
                bridge_done_clr<= 1'b0;
                bridge_data    <= 16'h0000;
                bridge_addr_off<= 8'h00;
                bridge_rw      <= 1'b0;
                watchdog       <= 20'h0;
            end else begin
                bridge_done_clr <= 1'b0;

                case (state)
                ST_IDLE: begin
                    cpu_dtack_n <= 1'b1;
                    cpu_berr_n  <= 1'b1;
                    cpu_data_out <= 16'h0000;
                    if (sel_chipreg) begin
                        bridge_data     <= cpu_data_in;
                        bridge_addr_off <= {6'b0, cpu_addr[1:0]};
                        bridge_rw       <= ~cpu_rw;
                        bridge_new_req  <= 1'b1;
                        watchdog        <= 20'h0;
                        state           <= ST_WAIT_ARM;
                    end
                end

                ST_WAIT_ARM: begin
                    bridge_new_req <= 1'b1;
                    watchdog <= watchdog + 1;

                    if (bridge_done) begin
                        bridge_done_clr <= 1'b1;
                        bridge_new_req  <= 1'b0;
                        cpu_data_out    <= bridge_result;
                        state           <= ST_RELEASE;
                    end else if (watchdog >= WATCHDOG_CYCLES[19:0]) begin
                        bridge_new_req <= 1'b0;
                        state          <= ST_BERR;
                    end
                end

                ST_RELEASE: begin
                    cpu_dtack_n  <= 1'b0;
                    if (cpu_as_n) begin
                        cpu_dtack_n <= 1'b1;
                        state       <= ST_IDLE;
                    end
                end

                ST_BERR: begin
                    cpu_berr_n <= 1'b0;
                    if (cpu_as_n) begin
                        cpu_berr_n <= 1'b1;
                        state      <= ST_IDLE;
                    end
                end
                endcase
            end
        end

    end
    endgenerate

endmodule
