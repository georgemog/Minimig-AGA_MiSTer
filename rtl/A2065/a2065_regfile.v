/*
 * a2065_regfile.v
 *
 * Am7990 LANCE register file + CSR doorbell.
 *
 * Replaces the DTACK-stretch bridge RPC (a2065_registers.v bridge mode).
 * The 68k reads/writes RAP/RDP at full bus speed.  RDP writes with side
 * effects raise a doorbell for the ARM daemon; the ARM writes status bits
 * back into the CSR shadow which the 68k polls at full speed.
 *
 * No DTACK stretch on reads or RAP writes.  Only an RDP write while the
 * previous doorbell is still pending will stretch (back-pressure).
 */

module a2065_regfile (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [23:0] cpu_addr,
    input  wire        cpu_rw,
    input  wire        cpu_as_n,
    input  wire        cpu_ds_n,
    input  wire [15:0] cpu_data_in,
    output reg  [15:0] cpu_data_out,
    output wire        regs_nrdy,

    input  wire [7:0]  card_base,
    input  wire        card_configured,

    output reg         cmd_pending,
    output reg  [6:0]  cmd_rap,
    output reg  [15:0] cmd_data,
    input  wire        cmd_clear,

    input  wire [15:0] csr0_in,
    input  wire [15:0] csr1_in,
    input  wire [15:0] csr2_in,
    input  wire [15:0] csr3_in
);

    wire sel_chipreg = card_configured &&
                       (cpu_addr[23:16] == card_base) &&
                       (cpu_addr[15:2]  == 14'h1000) &&
                       (!cpu_as_n) &&
                       (!cpu_ds_n);

    wire is_rap = cpu_addr[1];

    reg [6:0]  rap;
    reg [15:0] csr_shadow [0:3];

    always @(posedge clk) begin
        csr_shadow[0] <= csr0_in;
        csr_shadow[1] <= csr1_in;
        csr_shadow[2] <= csr2_in;
        csr_shadow[3] <= csr3_in;
    end

    always @(posedge clk) begin
        cpu_data_out <= 16'h0000;
        if (sel_chipreg && cpu_rw) begin
            if (is_rap)
                cpu_data_out <= {9'b0, rap};
            else begin
                case (rap)
                7'd88: cpu_data_out <= 16'h0001;
                7'd89: cpu_data_out <= 16'h3003;
                default: begin
                    if (rap < 4)
                        cpu_data_out <= csr_shadow[rap];
                end
                endcase
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rap         <= 7'd0;
            cmd_pending <= 1'b0;
            cmd_rap     <= 7'd0;
            cmd_data    <= 16'd0;
        end else begin
        if (cmd_clear)
            cmd_pending <= 1'b0;

        if (sel_chipreg && !cpu_rw && !is_rap && !cmd_pending) begin
            cmd_rap     <= rap;
            cmd_data    <= cpu_data_in;
            cmd_pending <= 1'b1;
        end

            if (sel_chipreg && !cpu_rw && is_rap)
                rap <= cpu_data_in[6:0];
        end
    end

    reg cmd_pending_d;
    always @(posedge clk)
        cmd_pending_d <= cmd_pending;

    assign regs_nrdy = sel_chipreg && !cpu_rw && !is_rap && cmd_pending_d;

endmodule
