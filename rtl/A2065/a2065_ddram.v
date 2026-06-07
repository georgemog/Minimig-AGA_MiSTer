/*
 * a2065_ddram.v
 *
 * 68k boardram DDR3 window — clk_sys interface module.
 *
 * Handles the 68k bus side of boardram access: address decode, request
 * latch, DTACK stretch, and CDC handshake with the clk_audio mailbox
 * FSM that performs the actual DDR3 read/write.
 *
 * Port A (68k bus, clk_sys):
 *   - sel + cpu_addr[15] selects boardram at card+0x8000
 *   - DTACK-stretched: nrdy asserted until DDR3 response arrives
 *   - cpu_data_out driven on read completion
 *
 * The clk_audio FSM (in a2065_ddr3_mailbox) sees the request via CDC,
 * performs DDR3 access, and signals completion back via CDC.
 */

module a2065_ddram (
    input  wire         clk_sys,
    input  wire         rst_n_sys,

    input  wire [23:1]  cpu_addr,
    input  wire [15:0]  cpu_data_in,
    output reg  [15:0]  cpu_data_out,
    input  wire         cpu_hwr,
    input  wire         cpu_lwr,
    input  wire         sel,
    output wire         nrdy,

    output reg          bram_req_valid,
    output reg  [13:0]  bram_req_addr,
    output reg  [15:0]  bram_req_wdata,
    output reg          bram_req_rw,

    input  wire         bram_req_ack_audio,
    input  wire         bram_resp_valid_audio,
    input  wire [15:0]  bram_resp_data_audio
);

    wire sel_br   = sel && cpu_addr[15];
    wire is_write = ~cpu_hwr | ~cpu_lwr;
    wire [13:0] word_idx = cpu_addr[14:1];

    reg  sys_req;
    reg  sys_got_resp;

    reg  ack_sync0, ack_sync1;
    reg  rv_sync0, rv_sync1;
    reg [15:0] rd_sync0, rd_sync1;

    always @(posedge clk_sys or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            sys_req       <= 1'b0;
            sys_got_resp  <= 1'b0;
            cpu_data_out  <= 16'h0000;
            bram_req_valid <= 1'b0;
            bram_req_addr  <= 0;
            bram_req_wdata <= 0;
            bram_req_rw    <= 1'b0;
            ack_sync0  <= 1'b0;
            ack_sync1  <= 1'b0;
            rv_sync0   <= 1'b0;
            rv_sync1   <= 1'b0;
            rd_sync0   <= 16'd0;
            rd_sync1   <= 16'd0;
        end else begin
            sys_got_resp <= 1'b0;

            ack_sync0 <= bram_req_ack_audio;
            ack_sync1 <= ack_sync0;

            rv_sync0 <= bram_resp_valid_audio;
            rv_sync1 <= rv_sync0;

            rd_sync0 <= bram_resp_data_audio;
            rd_sync1 <= rd_sync0;

            if (sys_req && ack_sync1) begin
                sys_req        <= 1'b0;
                bram_req_valid <= 1'b0;
            end

            if (rv_sync1) begin
                sys_got_resp <= 1'b1;
                cpu_data_out <= rd_sync1;
            end

            if (sel_br && !sys_req && !sys_got_resp && (nrdy_state == NR_IDLE)) begin
                bram_req_addr  <= word_idx;
                bram_req_wdata <= cpu_data_in;
                bram_req_rw    <= is_write;
                bram_req_valid <= 1'b1;
                sys_req        <= 1'b1;
            end
        end
    end

    reg  [1:0] nrdy_state;
    localparam NR_IDLE  = 2'd0;
    localparam NR_WAIT  = 2'd1;
    localparam NR_DONE  = 2'd2;

    always @(posedge clk_sys or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            nrdy_state <= NR_IDLE;
        end else begin
            case (nrdy_state)
            NR_IDLE: begin
                if (sel_br)
                    nrdy_state <= NR_WAIT;
            end
            NR_WAIT: begin
                if (rv_sync1)
                    nrdy_state <= NR_DONE;
            end
            NR_DONE: begin
                if (!sel_br)
                    nrdy_state <= NR_IDLE;
            end
            default: nrdy_state <= NR_IDLE;
            endcase
        end
    end

    assign nrdy = (nrdy_state == NR_WAIT);

endmodule
