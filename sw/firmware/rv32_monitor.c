/* ============================================================================
 * rv32_monitor.c  -  Zynq PS bare-metal monitor for the RV32 PL platform
 *
 * The PS (ARM) talks to a host PC over UART and drives the rv32_platform
 * AXI4-Lite control slave (mapped at 0x4000_0000 by the BD) to load programs,
 * control reset/run/step, and read back register / PC / commit / data state.
 *
 * Build: Vitis (standalone/bare-metal app on ps7_cortexa9_0), stdin/stdout
 *        routed to the PS UART (Zybo USB-UART on MIO). xil_printf + inbyte().
 *
 * Protocol (host -> PS), one ASCII line per command (\n or \r terminated);
 * all numbers HEX. PS replies one line.
 *   r                  reset+hold CPU (prep for load)            -> "OK"
 *   i <addr> <data>    imem[addr] = data                         -> "OK"
 *   d <addr> <data>    dmem[addr] = data                         -> "OK"
 *   g                  release reset, run                        -> "OK"
 *   s                  single step                               -> "OK rd=<n> wd=<hex> cc=<n>"
 *   x <n>              read register n (0..31)                   -> "x<n>=<hex>"
 *   m <addr>           read data memory word                     -> "m<addr>=<hex>"
 *   p                  read PC                                   -> "pc=<hex>"
 *   c                  commit count                             -> "cc=<n>"
 *   t                  status (b0=halted,b2=run)                 -> "st=<hex>"
 *   D                  dump x0..x31                              -> 32 lines "x<n>=<hex>"
 *   L                  read LED register   (board outputs)       -> "led=<hex>"
 *   W                  read SW  inputs     (board switches)      -> "sw=<hex>"
 *   N                  read BTN inputs     (board buttons)       -> "btn=<hex>"
 *   h                  help                                      -> usage
 *
 * L/W/N need the peripheral-readback build (ctrl-slave regs 0x38/0x3C/0x40,
 * wired in rv32_ctrl_axi.vhd + rv32_platform.vhd). On an older bitstream those
 * reads return 0; the host GUI auto-detects support and falls back to a probe.
 * ==========================================================================*/
#include "xparameters.h"
#include "xil_io.h"
#include "xil_printf.h"

/* AXI-Lite control slave base (matches the BD address assignment) */
#ifndef RV32_BASE
#define RV32_BASE   0x40000000u
#endif

/* register offsets (SOC_PLATFORM_DESIGN.md / docs) */
#define R_CTRL        0x00u   /* W: b0 reset, b1 run, b2 step, b3 clr_commit */
#define R_STATUS      0x04u   /* R: b0 halted, b2 run                        */
#define R_IMEM_ADDR   0x08u
#define R_IMEM_WDATA  0x0Cu
#define R_DMEM_ADDR   0x10u
#define R_DMEM_WDATA  0x14u
#define R_REG_ADDR    0x18u
#define R_REG_RDATA   0x1Cu
#define R_PC          0x20u
#define R_LAST_RD     0x24u
#define R_LAST_WDATA  0x28u
#define R_COMMIT_CNT  0x2Cu
#define R_DMEM_RADDR  0x30u
#define R_DMEM_RDATA  0x34u
#define R_LED         0x38u   /* R: board LED register (peripheral-readback build) */
#define R_SW          0x3Cu   /* R: board switches                                 */
#define R_BTN         0x40u   /* R: board buttons                                  */

#define CTRL_RESET    0x1u
#define CTRL_RUN      0x2u
#define CTRL_STEP     0x4u
#define CTRL_CLRCNT   0x8u

extern char inbyte(void);   /* Xilinx standalone console input (PS UART) */

static inline void wr(u32 off, u32 v) { Xil_Out32(RV32_BASE + off, v); }
static inline u32  rd(u32 off)        { return Xil_In32(RV32_BASE + off); }

static void load_imem(u32 a, u32 d) { wr(R_IMEM_ADDR, a); wr(R_IMEM_WDATA, d); }
static void load_dmem(u32 a, u32 d) { wr(R_DMEM_ADDR, a); wr(R_DMEM_WDATA, d); }
static u32  read_reg(u32 n)         { wr(R_REG_ADDR, n);  return rd(R_REG_RDATA); }
static u32  read_dmem(u32 a)        { wr(R_DMEM_RADDR, a); return rd(R_DMEM_RDATA); }

/* ---- tiny line reader + hex parser ---- */
static int getline(char *buf, int max)
{
    int n = 0; char c;
    for (;;) {
        c = inbyte();
        if (c == '\r' || c == '\n') { buf[n] = 0; if (n) return n; else continue; }
        if (c == 8 || c == 127) { if (n) n--; continue; }   /* backspace */
        if (n < max - 1) buf[n++] = c;
    }
}
static u32 hex(const char **p)
{
    u32 v = 0; const char *s = *p;
    while (*s == ' ' || *s == '\t') s++;
    while (1) {
        char c = *s; u32 d;
        if      (c >= '0' && c <= '9') d = c - '0';
        else if (c >= 'a' && c <= 'f') d = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') d = c - 'A' + 10;
        else break;
        v = (v << 4) | d; s++;
    }
    *p = s; return v;
}

static void help(void)
{
    xil_printf("RV32 monitor: r | i A D | d A D | g | s | x N | m A | p | c | t | D | L | W | N | h\r\n");
}

int main(void)
{
    char line[128];
    xil_printf("\r\n=== RV32 PS monitor @0x%08x ===\r\n", RV32_BASE);
    help();

    for (;;) {
        getline(line, sizeof(line));
        const char *p = line + 1;            /* args after the command char */
        switch (line[0]) {
        case 'r':                            /* reset + hold (clear commit, no glitch) */
            wr(R_CTRL, CTRL_RESET | CTRL_CLRCNT);
            xil_printf("OK\r\n");
            break;
        case 'i': { u32 a = hex(&p), d = hex(&p); load_imem(a, d); xil_printf("OK\r\n"); } break;
        case 'd': { u32 a = hex(&p), d = hex(&p); load_dmem(a, d); xil_printf("OK\r\n"); } break;
        case 'g':                            /* release reset + run */
            wr(R_CTRL, 0);                   /* deassert reset (frozen) */
            wr(R_CTRL, CTRL_RUN);            /* run */
            xil_printf("OK\r\n");
            break;
        case 's': {                          /* single step (from frozen state) */
            u32 c0 = rd(R_COMMIT_CNT);
            wr(R_CTRL, CTRL_STEP);
            /* wait until a commit retires (cache miss may take many cycles) */
            u32 guard = 0; while (rd(R_COMMIT_CNT) == c0 && guard < 100000u) guard++;
            xil_printf("OK rd=%u wd=%08x cc=%u\r\n",
                       (unsigned)rd(R_LAST_RD), (unsigned)rd(R_LAST_WDATA),
                       (unsigned)rd(R_COMMIT_CNT));
        } break;
        case 'x': { u32 n = hex(&p); xil_printf("x%u=%08x\r\n", (unsigned)n, (unsigned)read_reg(n)); } break;
        case 'm': { u32 a = hex(&p); xil_printf("m%08x=%08x\r\n", (unsigned)a, (unsigned)read_dmem(a)); } break;
        case 'p':   xil_printf("pc=%08x\r\n", (unsigned)rd(R_PC)); break;
        case 'c':   xil_printf("cc=%u\r\n", (unsigned)rd(R_COMMIT_CNT)); break;
        case 't':   xil_printf("st=%08x\r\n", (unsigned)rd(R_STATUS)); break;
        case 'D': { int n; for (n = 0; n < 32; n++)
                       xil_printf("x%d=%08x\r\n", n, (unsigned)read_reg((u32)n)); } break;
        case 'L':   xil_printf("led=%x\r\n", (unsigned)rd(R_LED)); break;
        case 'W':   xil_printf("sw=%x\r\n",  (unsigned)rd(R_SW));  break;
        case 'N':   xil_printf("btn=%x\r\n", (unsigned)rd(R_BTN)); break;
        case 'h':   help(); break;
        default:    xil_printf("ERR\r\n"); break;
        }
    }
    return 0;
}
