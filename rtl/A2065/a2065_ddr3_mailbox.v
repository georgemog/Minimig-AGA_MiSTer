/*
 * a2065_ddr3_mailbox.v
 *
 * DDR3 mailbox adapter for A2065 (Phase 2 — doorbell architecture).
 *
 * Runs entirely in clk_audio (~49 MHz).  Handles three functions:
 *
 *   1. CMD doorbell: regfile raises cmd_pending → mailbox writes CMD to
 *      DDR3 for ARM daemon → pulses cmd_clear.  No DTACK stretch for
 *      reads/RAP writes — only back-pressure on overlapping RDP writes.
 *
 *   2. Boardram DDR3 window: 68k accesses boardram at card+0x8000 via
 *      DTACK-stretched DDR3 read/write.  Request arrives via async
 *      handshake from clk_sys; FSM performs direct DDR3 access.
 *
 *   3. CSR shadow + INT state poll: periodically reads CSR_SHADOW and
 *      INT_STATE from DDR3 (written by ARM daemon).  CSR values feed
 *      back to regfile for 68k zero-latency reads.  INT_STATE drives
 *      the a2065_int2 output.
 *
 * Priority: CMD doorbell > boardram window > CSR/INT poll.
 */

module a2065_ddr3_mailbox (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         cmd_pending,
    input  wire  [6:0]  cmd_rap,
    input  wire  [15:0] cmd_data,
    output reg          cmd_clear,

    output reg  [15:0]  csr0_out,
    output reg  [15:0]  csr1_out,
    output reg  [15:0]  csr2_out,
    output reg  [15:0]  csr3_out,
    output reg          a2065_int2,

    input  wire         bram_req_valid,
    input  wire  [13:0] bram_req_addr,
    input  wire  [15:0] bram_req_wdata,
    input  wire         bram_req_rw,
    output reg          bram_req_ack,
    output reg          bram_resp_valid,
    output reg  [15:0]  bram_resp_data,

    output reg  [28:0]  avl_address,
    output reg  [7:0]   avl_burstcount,
    output reg          avl_read,
    input  wire [63:0]  avl_readdata,
    input  wire         avl_readdatavalid,
    output reg  [63:0]  avl_writedata,
    output reg  [7:0]   avl_byteenable,
    output reg          avl_write,
    input  wire         avl_waitrequest
);

    localparam DDR3_BASE = 29'h03FE0000;

    localparam AV_CMD          = 29'h1000;
    localparam AV_CSR          = 29'h1002;
    localparam AV_INT          = 29'h1003;

    localparam S_IDLE          = 4'd0;
    localparam S_CMD_WR_W      = 4'd1;
    localparam S_CMD_DONE      = 4'd2;

    localparam S_BR_CAPTURE    = 4'd3;
    localparam S_BR_READ_W     = 4'd4;
    localparam S_BR_READ_D     = 4'd5;
    localparam S_BR_WRITE_W    = 4'd6;
    localparam S_BR_DONE       = 4'd7;

    localparam S_CSR_RD_W      = 4'd8;
    localparam S_CSR_RD_D      = 4'd9;
    localparam S_INT_RD_W      = 4'd10;
    localparam S_INT_RD_D      = 4'd11;

    reg [3:0] state;

    reg  [7:0] poll_div;

    reg  [13:0] br_addr;
    reg  [15:0] br_wdata;
    reg         br_rw;
    reg  [1:0]  br_lane;

    wire [28:0] br_ddr3_addr = DDR3_BASE + {17'b0, br_addr[13:2]};

    reg [7:0] br_be;
    reg [63:0] br_wdata_shifted;

    always @(*) begin
        case (br_lane)
        2'd0: begin br_be = 8'h03; br_wdata_shifted = {48'b0, br_wdata}; end
        2'd1: begin br_be = 8'h0C; br_wdata_shifted = {32'b0, br_wdata, 16'b0}; end
        2'd2: begin br_be = 8'h30; br_wdata_shifted = {16'b0, br_wdata, 32'b0}; end
        2'd3: begin br_be = 8'hC0; br_wdata_shifted = {br_wdata, 48'b0}; end
        endcase
    end

    reg bram_req_valid_s, bram_req_valid_s1;
    reg [13:0] bram_req_addr_s;
    reg [15:0] bram_req_wdata_s;
    reg        bram_req_rw_s;

    always @(posedge clk) begin
        bram_req_valid_s  <= bram_req_valid;
        bram_req_valid_s1 <= bram_req_valid_s;

        bram_req_addr_s   <= bram_req_addr;
        bram_req_wdata_s  <= bram_req_wdata;
        bram_req_rw_s     <= bram_req_rw;
    end

    wire bram_req_active = bram_req_valid_s1;

    reg cmd_pending_s, cmd_pending_s1;
    reg [6:0]  cmd_rap_s;
    reg [15:0] cmd_data_s;

    always @(posedge clk) begin
        cmd_pending_s  <= cmd_pending;
        cmd_pending_s1 <= cmd_pending_s;
        cmd_rap_s      <= cmd_rap;
        cmd_data_s     <= cmd_data;
    end

    wire cmd_active = cmd_pending_s1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            avl_address     <= 0;
            avl_burstcount  <= 1;
            avl_read        <= 0;
            avl_write       <= 0;
            avl_writedata   <= 0;
            avl_byteenable  <= 8'hFF;
            poll_div        <= 0;
            cmd_clear       <= 0;
            csr0_out        <= 0;
            csr1_out        <= 0;
            csr2_out        <= 0;
            csr3_out        <= 0;
            a2065_int2      <= 0;
            bram_req_ack    <= 0;
            bram_resp_valid <= 0;
            bram_resp_data  <= 0;
            br_lane         <= 0;
        end else begin
            avl_read        <= 0;
            avl_write       <= 0;
            cmd_clear       <= 0;
            bram_req_ack    <= 0;
            bram_resp_valid <= 0;

            poll_div <= poll_div + 1'b1;

            case (state)
            S_IDLE: begin
                if (cmd_active) begin
                    avl_address    <= DDR3_BASE + AV_CMD;
                    avl_writedata  <= {39'b0, cmd_data_s, cmd_rap_s, 1'b1};
                    avl_byteenable <= 8'hFF;
                    avl_burstcount <= 1;
                    avl_write      <= 1;
                    state          <= S_CMD_WR_W;
                end else if (bram_req_active) begin
                    br_addr      <= bram_req_addr_s;
                    br_wdata     <= bram_req_wdata_s;
                    br_rw        <= bram_req_rw_s;
                    br_lane      <= bram_req_addr_s[1:0];
                    bram_req_ack <= 1'b1;
                    state        <= S_BR_CAPTURE;
                end else if (&poll_div[5:0]) begin
                    avl_address    <= DDR3_BASE + AV_CSR;
                    avl_burstcount <= 1;
                    avl_read       <= 1;
                    state          <= S_CSR_RD_W;
                end
            end

            S_CMD_WR_W: begin
                cmd_clear <= 1'b1;
                if (!avl_waitrequest) begin
                    state <= S_CMD_DONE;
                end else begin
                    avl_write <= 1;
                end
            end

            S_CMD_DONE: begin
                cmd_clear <= 1'b1;
                if (!cmd_pending_s1) begin
                    cmd_clear <= 1'b0;
                    state     <= S_IDLE;
                end
            end

            S_BR_CAPTURE: begin
                if (br_rw) begin
                    avl_address    <= br_ddr3_addr;
                    avl_writedata  <= br_wdata_shifted;
                    avl_byteenable <= br_be;
                    avl_burstcount <= 1;
                    avl_write      <= 1;
                    state          <= S_BR_WRITE_W;
                end else begin
                    avl_address    <= br_ddr3_addr;
                    avl_burstcount <= 1;
                    avl_read       <= 1;
                    state          <= S_BR_READ_W;
                end
            end

            S_BR_READ_W: begin
                if (!avl_waitrequest) begin
                    avl_read <= 0;
                    state    <= S_BR_READ_D;
                end else begin
                    avl_read <= 1;
                end
            end

            S_BR_READ_D: begin
                if (avl_readdatavalid) begin
                    case (br_lane)
                    2'd0: bram_resp_data <= avl_readdata[15:0];
                    2'd1: bram_resp_data <= avl_readdata[31:16];
                    2'd2: bram_resp_data <= avl_readdata[47:32];
                    2'd3: bram_resp_data <= avl_readdata[63:48];
                    endcase
                    bram_resp_valid <= 1'b1;
                    state           <= S_BR_DONE;
                end
            end

            S_BR_WRITE_W: begin
                if (!avl_waitrequest) begin
                    bram_resp_valid <= 1'b1;
                    state           <= S_BR_DONE;
                end else begin
                    avl_write <= 1;
                end
            end

            S_BR_DONE: begin
                state <= S_IDLE;
            end

            S_CSR_RD_W: begin
                if (!avl_waitrequest) begin
                    avl_read <= 0;
                    state    <= S_CSR_RD_D;
                end else begin
                    avl_read <= 1;
                end
            end

            S_CSR_RD_D: begin
                if (avl_readdatavalid) begin
                    csr0_out <= avl_readdata[15:0];
                    csr1_out <= avl_readdata[31:16];
                    csr2_out <= avl_readdata[47:32];
                    csr3_out <= avl_readdata[63:48];
                    avl_address    <= DDR3_BASE + AV_INT;
                    avl_burstcount <= 1;
                    avl_read       <= 1;
                    state          <= S_INT_RD_W;
                end
            end

            S_INT_RD_W: begin
                if (!avl_waitrequest) begin
                    avl_read <= 0;
                    state    <= S_INT_RD_D;
                end else begin
                    avl_read <= 1;
                end
            end

            S_INT_RD_D: begin
                if (avl_readdatavalid) begin
                    a2065_int2 <= avl_readdata[0];
                    state      <= S_IDLE;
                end
            end

            default: state <= S_IDLE;
            endcase
        end
    end

endmodule
