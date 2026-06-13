/*
 * a2065_autoconfig.v
 *
 * ZorroII autoconfig ROM state machine for A2065 emulation.
 *
 * Responds to 68k reads at 0xE80000 with A2065 card identity nibbles.
 * Latches the configured base address written by AmigaOS.
 *
 * Autoconfig protocol (ZorroII):
 *   - Reads are nibble-wide on D[15:12] (inverted: ROM 0 → bus 1)
 *   - Each read is a 16-bit bus cycle; one nibble per cycle
 *   - 32 nibbles total (16 bytes of config data)
 *   - AmigaOS writes base address to 0xE80048/0xE8004A
 *   - AmigaOS writes SHUTUP to 0xE8004C to end autoconfig for this card
 *
 * MAC bytes [2:5] are loaded into the serial number nibbles by the ARM
 * daemon via the mac_nibble_* inputs before the Amiga boots.
 */

module a2065_autoconfig (
    input  wire        clk,
    input  wire        rst_n,

    /* 68k bus */
    input  wire [23:0] cpu_addr,
    input  wire        cpu_rw,       /* 1=read, 0=write */
    input  wire        cpu_as_n,     /* address strobe, active low */
    input  wire [15:0] cpu_data_in,  /* data from 68k (for writes) */
    output reg  [15:0] cpu_data_out, /* data to 68k (for reads) */
    output reg         cpu_dtack_n,  /* data transfer ack, active low */

    /* ARM writes MAC bytes before boot (via bridge) */
    input  wire [7:0]  mac_byte2,    /* realmac[2] → serial number byte 0 */
    input  wire [7:0]  mac_byte3,    /* realmac[3] → serial number byte 1 */
    input  wire [7:0]  mac_byte4,    /* realmac[4] → serial number byte 2 */
    input  wire [7:0]  mac_byte5,    /* realmac[5] → serial number byte 3 */

    /* Configuration outputs */
    output reg  [7:0]  card_base,    /* configured address >> 16 (e.g. 0xE9) */
    output reg         card_configured, /* high after base address written */
    output reg         card_shutup   /* high after SHUTUP received */
);

    /* ── Autoconfig ROM (32 nibbles, indexed by addr[5:1]) ─────────── */
    /* Nibbles are output INVERTED on the ZorroII bus.                   */
    /* A2065: type=0xC1 product=0x70 flags=0x00 mfr=0x0202              */
    /* Serial number (nibbles 12–19) = MAC bytes 2–5 (set from inputs)  */

    reg [3:0] rom [0:31];

    always @(*) begin
        /* Static nibbles */
        rom[ 0] = 4'hC;  /* er_Type high:  0xC (ZorroII=0xC0>>4) */
        rom[ 1] = 4'h1;  /* er_Type low:   0x1 (64KB)            */
        rom[ 2] = 4'h7;  /* er_Product high: 0x7                  */
        rom[ 3] = 4'h0;  /* er_Product low:  0x0 → product=0x70  */
        rom[ 4] = 4'h0;  /* er_Flags high                        */
        rom[ 5] = 4'h0;  /* er_Flags low                         */
        rom[ 6] = 4'hF;  /* reserved (inverted zero)             */
        rom[ 7] = 4'hF;  /* reserved                             */
        rom[ 8] = 4'h0;  /* er_Manufacturer high high: 0x0       */
        rom[ 9] = 4'h2;  /* er_Manufacturer high low:  0x2       */
        rom[10] = 4'h0;  /* er_Manufacturer low high:  0x0       */
        rom[11] = 4'h2;  /* er_Manufacturer low low:   0x2 → 0x0202 */
        /* er_SerialNumber = MAC bytes [2:5] (set by ARM at runtime) */
        rom[12] = mac_byte2[7:4];
        rom[13] = mac_byte2[3:0];
        rom[14] = mac_byte3[7:4];
        rom[15] = mac_byte3[3:0];
        rom[16] = mac_byte4[7:4];
        rom[17] = mac_byte4[3:0];
        rom[18] = mac_byte5[7:4];
        rom[19] = mac_byte5[3:0];
        /* er_InitDiagVec: 0x0000 (no diagnostic vector) */
        rom[20] = 4'hF;
        rom[21] = 4'hF;
        rom[22] = 4'hF;
        rom[23] = 4'hF;
        /* reserved */
        rom[24] = 4'hF;
        rom[25] = 4'hF;
        rom[26] = 4'hF;
        rom[27] = 4'hF;
        rom[28] = 4'hF;
        rom[29] = 4'hF;
        rom[30] = 4'hF;
        rom[31] = 4'hF;
    end

    /* ── Address decode ─────────────────────────────────────────────── */
    /* Autoconfig space: 0xE80000–0xE8FFFF, active before card is shut up */
    wire sel_autoconfig = (!card_shutup) &&
                          (cpu_addr[23:16] == 8'hE8) &&
                          (!cpu_as_n);

    /* Nibble index: bits [5:1] of address → 0..31 */
    wire [4:0] nibble_idx = cpu_addr[5:1];

    /* ── Address write decode ────────────────────────────────────────── */
    /* AmigaOS writes base address at 0xE80048 (low) / 0xE8004A (high)  */
    /* and SHUTUP at 0xE8004C                                            */
    wire write_base_lo = sel_autoconfig && !cpu_rw && (cpu_addr[7:0] == 8'h48);
    wire write_base_hi = sel_autoconfig && !cpu_rw && (cpu_addr[7:0] == 8'h4A);
    wire write_shutup  = sel_autoconfig && !cpu_rw && (cpu_addr[7:0] == 8'h4C);

    /* ── Sequential logic ───────────────────────────────────────────── */
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            card_base       <= 8'h00;
            card_configured <= 1'b0;
            card_shutup     <= 1'b0;
            cpu_dtack_n     <= 1'b1;
            cpu_data_out    <= 16'hFFFF;
        end else begin
            cpu_dtack_n  <= 1'b1;
            cpu_data_out <= 16'hFFFF;

            if (sel_autoconfig) begin
                if (cpu_rw) begin
                    /* Read: output inverted nibble on D[15:12] */
                    cpu_data_out <= {~rom[nibble_idx], 12'hFFF};
                    cpu_dtack_n  <= 1'b0;
                end else begin
                    /* Write cycles */
                    if (write_base_lo) begin
                        card_base       <= cpu_data_in[15:8]; /* D[15:8] = base addr >> 16 */
                        card_configured <= 1'b1;
                        cpu_dtack_n     <= 1'b0;
                    end else if (write_base_hi) begin
                        /* high byte of address — usually ignored for 64KB boards */
                        cpu_dtack_n <= 1'b0;
                    end else if (write_shutup) begin
                        card_shutup <= 1'b1;
                        cpu_dtack_n <= 1'b0;
                    end else begin
                        cpu_dtack_n <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
