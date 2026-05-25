module a2065_ddr3_mailbox (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [15:0]  bridge_data,
    input  wire [7:0]   bridge_addr_off,
    input  wire         bridge_rw,
    input  wire         bridge_new_req,
    output reg          bridge_done,
    output reg  [15:0]  bridge_result,

    output wire [14:1]  bram_addr,
    output wire [15:0]  bram_wdata,
    output wire         bram_wr,
    output wire [1:0]   bram_be,
    input  wire [15:0]  bram_rdata,

    output reg          a2065_int2,

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

    localparam DDR3_BASE    = 29'h03FE0000;
    localparam MBX_REG_REQ  = 29'h1000;
    localparam MBX_REG_RSP  = 29'h1001;
    localparam MBX_RAM_REQ  = 29'h1002;
    localparam MBX_RAM_RSP  = 29'h1003;
    localparam MBX_INT      = 29'h1004;

    localparam S_IDLE          = 5'd0;
    localparam S_REG_CAPTURE   = 5'd1;
    localparam S_REG_WR_REQ    = 5'd2;
    localparam S_REG_POLL      = 5'd3;
    localparam S_REG_POLL_W    = 5'd4;
    localparam S_REG_CLR_RSP   = 5'd5;
    localparam S_REG_CLR_REQ   = 5'd6;
    localparam S_REG_DONE      = 5'd7;
    localparam S_RAM_CAPTURE   = 5'd8;
    localparam S_RAM_BRAM_RD   = 5'd9;
    localparam S_RAM_WR_RSP    = 5'd10;
    localparam S_RAM_CLR_REQ   = 5'd11;
    localparam S_RAM_DONE      = 5'd12;
    localparam S_RAM_WAIT      = 5'd13;
    localparam S_RAM_BRAM_LAT  = 5'd14;
    localparam S_RAM_BRAM_WAIT = 5'd15;
    localparam S_INT_CAPTURE   = 5'd16;
    localparam S_INT_WAIT      = 5'd17;

    reg [4:0]  state;
    reg [15:0] saved_data;
    reg [7:0]  saved_addr;
    reg        saved_rw;

    reg req_sync0, req_sync1, req_prev;
    wire req_edge = req_sync1 && !req_prev;

    reg  [14:1] bram_addr_r;
    reg  [15:0] bram_wdata_r;
    reg         bram_wr_r;
    reg  [1:0]  bram_be_r;
    reg  [15:0] bram_rdata_r;
    reg  [7:0]  poll_div;
    reg  [7:0]  timeout_cnt;

    assign bram_addr  = bram_addr_r;
    assign bram_wdata = bram_wdata_r;
    assign bram_wr    = bram_wr_r;
    assign bram_be    = bram_be_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            avl_address    <= 0;
            avl_burstcount <= 1;
            avl_read       <= 0;
            avl_write      <= 0;
            avl_writedata  <= 0;
            avl_byteenable <= 8'hFF;
            bridge_result  <= 0;
            saved_data     <= 0;
            saved_addr     <= 0;
            saved_rw       <= 0;
            req_sync0      <= 0;
            req_sync1      <= 0;
            req_prev       <= 0;
            bram_addr_r    <= 0;
            bram_wdata_r   <= 0;
            bram_wr_r      <= 0;
            bram_be_r      <= 0;
            bram_rdata_r   <= 0;
            poll_div       <= 0;
            a2065_int2     <= 0;
            timeout_cnt    <= 0;
        end else begin
            avl_read  <= 0;
            avl_write <= 0;
            bram_wr_r <= 0;
            req_sync0 <= bridge_new_req;
            req_sync1 <= req_sync0;
            req_prev  <= req_sync1;
            poll_div  <= poll_div + 1'b1;

            case (state)
            S_IDLE: begin
                bridge_done <= 0;
                if (req_sync1) begin
                    saved_data <= bridge_data;
                    saved_addr <= bridge_addr_off;
                    saved_rw   <= bridge_rw;
                    state      <= S_REG_CAPTURE;
                end else if (&poll_div) begin
                    timeout_cnt    <= 8'd255;
                    avl_address    <= DDR3_BASE + MBX_RAM_REQ;
                    avl_burstcount <= 1;
                    avl_read       <= 1;
                    state          <= S_RAM_CAPTURE;
                end else if (&poll_div[4:0]) begin
                    timeout_cnt    <= 8'd255;
                    avl_address    <= DDR3_BASE + MBX_INT;
                    avl_burstcount <= 1;
                    avl_read       <= 1;
                    state          <= S_INT_CAPTURE;
                end
            end

            S_REG_CAPTURE: begin
                avl_address    <= DDR3_BASE + MBX_REG_REQ;
                avl_writedata  <= {14'b0, saved_data,
                                   saved_addr,
                                   saved_rw, 1'b1};
                avl_byteenable <= 8'hFF;
                avl_burstcount <= 1;
                avl_write      <= 1;
                state          <= S_REG_WR_REQ;
            end

            S_REG_WR_REQ: begin
                if (!avl_waitrequest) begin
                    avl_write <= 0;
                    state     <= S_REG_POLL;
                end else begin
                    avl_write <= 1;
                end
            end

            S_REG_POLL: begin
                avl_address    <= DDR3_BASE + MBX_REG_RSP;
                avl_burstcount <= 1;
                avl_read       <= 1;
                state          <= S_REG_POLL_W;
            end

            S_REG_POLL_W: begin
                if (avl_readdatavalid) begin
                    if (avl_readdata[0]) begin
                        bridge_result  <= avl_readdata[16:1];
                        avl_address    <= DDR3_BASE + MBX_REG_RSP;
                        avl_writedata  <= 64'b0;
                        avl_byteenable <= 8'hFF;
                        avl_burstcount <= 1;
                        avl_write      <= 1;
                        state          <= S_REG_CLR_RSP;
                    end else begin
                        avl_address    <= DDR3_BASE + MBX_REG_RSP;
                        avl_burstcount <= 1;
                        avl_read       <= 1;
                    end
                end else begin
                    avl_address    <= DDR3_BASE + MBX_REG_RSP;
                    avl_burstcount <= 1;
                    avl_read       <= 1;
                end
            end

            S_REG_CLR_RSP: begin
                if (!avl_waitrequest) begin
                    avl_address    <= DDR3_BASE + MBX_REG_REQ;
                    avl_writedata  <= 64'b0;
                    avl_byteenable <= 8'hFF;
                    avl_burstcount <= 1;
                    avl_write      <= 1;
                    state          <= S_REG_CLR_REQ;
                end else begin
                    avl_write <= 1;
                end
            end

            S_REG_CLR_REQ: begin
                if (!avl_waitrequest) begin
                    bridge_done <= 1;
                    state       <= S_REG_DONE;
                end else begin
                    avl_write <= 1;
                end
            end

            S_REG_DONE: begin
                bridge_done <= 1;
                if (!req_sync1) begin
                    bridge_done <= 0;
                    state       <= S_IDLE;
                end
            end

            S_RAM_CAPTURE: begin
                if (timeout_cnt == 0) begin
                    state <= S_IDLE;
                end else if (!avl_waitrequest) begin
                    timeout_cnt <= 8'd255;
                    state <= S_RAM_WAIT;
                end else begin
                    timeout_cnt <= timeout_cnt - 1'b1;
                    avl_address    <= DDR3_BASE + MBX_RAM_REQ;
                    avl_burstcount <= 1;
                    avl_read       <= 1;
                end
            end

            S_RAM_WAIT: begin
                if (timeout_cnt == 0) begin
                    state <= S_IDLE;
                end else if (avl_readdatavalid) begin
                    if (avl_readdata[0]) begin
                        bram_addr_r <= avl_readdata[16:3];
                        bram_be_r   <= 2'b11;
                        saved_rw    <= avl_readdata[1];
                        if (avl_readdata[1]) begin
                            bram_wdata_r <= avl_readdata[32:17];
                            bram_wr_r    <= 1'b1;
                        end
                        state <= S_RAM_BRAM_RD;
                    end else begin
                        state <= S_IDLE;
                    end
                end else begin
                    timeout_cnt <= timeout_cnt - 1'b1;
                end
            end

            S_RAM_BRAM_RD: begin
                if (saved_rw) begin
                    avl_address    <= DDR3_BASE + MBX_RAM_RSP;
                    avl_writedata  <= 64'h1;
                    avl_byteenable <= 8'hFF;
                    avl_burstcount <= 1;
                    avl_write      <= 1;
                    state          <= S_RAM_WR_RSP;
                end else begin
                    state <= S_RAM_BRAM_LAT;
                end
            end

            S_RAM_BRAM_LAT: begin
                state <= S_RAM_BRAM_WAIT;
            end

            S_RAM_BRAM_WAIT: begin
                avl_address    <= DDR3_BASE + MBX_RAM_RSP;
                avl_writedata  <= {16'b0, bram_rdata, 1'b1};
                avl_byteenable <= 8'hFF;
                avl_burstcount <= 1;
                avl_write      <= 1;
                state          <= S_RAM_WR_RSP;
            end

            S_RAM_WR_RSP: begin
                if (!avl_waitrequest) begin
                    avl_address    <= DDR3_BASE + MBX_RAM_REQ;
                    avl_writedata  <= 64'b0;
                    avl_byteenable <= 8'hFF;
                    avl_burstcount <= 1;
                    avl_write      <= 1;
                    state          <= S_RAM_CLR_REQ;
                end else begin
                    avl_write <= 1;
                end
            end

            S_RAM_CLR_REQ: begin
                if (!avl_waitrequest) begin
                    state <= S_RAM_DONE;
                end else begin
                    avl_write <= 1;
                end
            end

            S_RAM_DONE: begin
                state <= S_IDLE;
            end

            S_INT_CAPTURE: begin
                if (timeout_cnt == 0) begin
                    state <= S_IDLE;
                end else if (!avl_waitrequest) begin
                    timeout_cnt <= 8'd255;
                    state <= S_INT_WAIT;
                end else begin
                    timeout_cnt <= timeout_cnt - 1'b1;
                    avl_address    <= DDR3_BASE + MBX_INT;
                    avl_burstcount <= 1;
                    avl_read       <= 1;
                end
            end

            S_INT_WAIT: begin
                if (timeout_cnt == 0) begin
                    state <= S_IDLE;
                end else if (avl_readdatavalid) begin
                    a2065_int2 <= avl_readdata[0];
                    state      <= S_IDLE;
                end else begin
                    timeout_cnt <= timeout_cnt - 1'b1;
                end
            end
            endcase
        end
    end

endmodule
