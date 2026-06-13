# A2065 legacy / unused RTL

These files are **not** in `files.qip` and are **not** instantiated anywhere in the
build. They are kept for reference only. The live A2065 core is the four modules in
the parent directory:

- `a2065_regfile.v`      — LANCE RAP/RDP register file + autoconfig identity + CSR shadow
- `a2065_ddram.v`        — 68k-side DDR3 boardram window + CDC handshake
- `avalon_arbiter.v`     — 2-master Avalon arbiter onto the second DDR3 (f2sdram2) port
- `a2065_ddr3_mailbox.v` — DDR3 doorbell: CMD / boardram / CSR+INT poll (clk_audio)

## Why each file here is dead

| File | Reason |
|------|--------|
| `a2065_axi_slave.v`   | Intended HPS→FPGA (h2f) AXI consumer. The h2f bridge was abandoned; the live design uses the f2sdram2 DDR3 path. Never instantiated. |
| `a2065_ddr3_test.v`   | DDR3 bring-up/test harness. Was compiled (in qip) but never instantiated. |
| `ddr_arbiter.v`       | Superseded by `avalon_arbiter.v`. Looks like the live arbiter but is not — do not confuse them. |
| `a2065_top.v`         | Legacy Zorro-II top level (earlier line of development, pre flat-DDR3). |
| `a2065_autoconfig.v`  | Only referenced by `a2065_top.v`. |
| `a2065_registers.v`   | Only referenced by `a2065_top.v` (old DTACK-stretch register bridge). |
| `a2065_boardram.v`    | Old TDP-BRAM boardram. Replaced by the flat DDR3 window in `a2065_ddram.v`. |

Moved here during the merge of the doorbell core onto upstream Minimig
Release 20260603 (Finding A / Risk R6 of `docs/A2065_Minimig_Merge_Plan.md`).
