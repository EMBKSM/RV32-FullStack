"""
RV32-FullStack — Cycle-accurate Python reference models of the VHDL entities.

These models mirror the behavior of the RTL under ip_workspace/0_IF/ so that the
testbench (test_rv32.py) can exercise them deterministically without an HDL
simulator. Each class documents the exact VHDL file/entity it reflects.

NOTE: This is model-based verification. It validates the *logic and protocol*
of the design. It is NOT a substitute for elaboration/synthesis sign-off with
GHDL or Vivado xsim. See VERIFICATION_REPORT.md, "Methodology & Limitations".
"""

M32 = (1 << 32) - 1
M20 = (1 << 20) - 1
M8 = (1 << 8) - 1
M4 = (1 << 4) - 1


# --------------------------------------------------------------------------
# 0_PC/pc_adder.vhd  (entity pc_adder)
# --------------------------------------------------------------------------
def pc_adder(pc_in: int) -> int:
    """pc_out <= pc_in + 4 (mod 2^32)."""
    return (pc_in + 4) & M32


# --------------------------------------------------------------------------
# 0_PC/next_pc_mux.vhd  (entity next_pc_mux)
# --------------------------------------------------------------------------
def next_pc_mux(pc_plus_4: int, target_addr: int, pc_src: int) -> int:
    """next_pc <= target_addr when pc_src='1' else pc_plus_4."""
    return (target_addr if pc_src == 1 else pc_plus_4) & M32


# --------------------------------------------------------------------------
# 0_PC/program_counter.vhd  (entity pc_reg)
# --------------------------------------------------------------------------
class PCReg:
    """Async-reset, stall-gated program counter register."""

    def __init__(self, reset_addr: int = 0x0000_0000):
        self.reset_addr = reset_addr & M32
        self.pc = self.reset_addr  # represents pc_internal

    def step(self, reset: int, stall: int, next_pc: int):
        # Async reset dominates (process(clk,reset)).
        if reset == 1:
            self.pc = self.reset_addr
        elif stall == 0:
            self.pc = next_pc & M32
        # stall==1 -> hold
        return self.pc


# --------------------------------------------------------------------------
# 1_adress_split/address_aligner.vhd  (entity addr_aligner)
# --------------------------------------------------------------------------
def addr_aligner(address: int):
    """Combinational slice: tag[31:12], idx[11:4], offset[3:0]."""
    a = address & M32
    tag = (a >> 12) & M20
    idx = (a >> 4) & M8
    offset = a & M4
    return tag, idx, offset


# --------------------------------------------------------------------------
# 1_adress_split/comparator.vhd  (entity comparator)
# --------------------------------------------------------------------------
def comparator(addr_tag: int, cache_tag: int, valid_bit: int) -> int:
    """hit <= '1' when valid and addr_tag == cache_tag."""
    return 1 if (valid_bit == 1 and (addr_tag & M20) == (cache_tag & M20)) else 0


# --------------------------------------------------------------------------
# 1_adress_split/tag_array.vhd  (entity tag_array)
# --------------------------------------------------------------------------
class TagArray:
    """256 x 20-bit tag store + per-line valid. Async read, sync write."""

    def __init__(self):
        self.tag_mem = [None] * 256       # None models 'U' (uninitialized)
        self.valid_mem = [0] * 256        # init (others => '0')

    def read(self, idx: int):
        i = idx & M8
        return self.tag_mem[i], self.valid_mem[i]

    def step(self, clk_rising: bool, reset: int, we: int, idx: int, tag_in: int, inv: int = 0):
        if reset == 1:
            self.valid_mem = [0] * 256
        elif clk_rising:
            if inv == 1:                       # invalidate: single-cycle full clear of valid
                self.valid_mem = [0] * 256
            elif we == 1:
                i = idx & M8
                self.tag_mem[i] = tag_in & M20
                self.valid_mem[i] = 1


# --------------------------------------------------------------------------
# 1_adress_split/cache_controller.vhd  (entity cache_controller)
# --------------------------------------------------------------------------
S_IDLE, S_SEND_AR, S_WAIT_R, S_UPDATE_CACHE, S_WAKE_UP = range(5)
STATE_NAMES = {
    S_IDLE: "S_IDLE", S_SEND_AR: "S_SEND_AR", S_WAIT_R: "S_WAIT_R",
    S_UPDATE_CACHE: "S_UPDATE_CACHE", S_WAKE_UP: "S_WAKE_UP",
}


class CacheController:
    """
    Refill FSM controlling a simplified AXI read path.

    legacy=True  -> mirrors the ORIGINAL RTL (we asserted in S_UPDATE_CACHE).
    legacy=False -> mirrors the FIXED RTL    (we asserted on the RVALID beat).
    """

    def __init__(self, legacy: bool = False):
        self.state = S_IDLE
        self.legacy = legacy

    # --- combinational next-state: process(state, miss, arready, rvalid) ---
    def next_state(self, miss, arready, rvalid, fence_i=0, ext_inv=0):
        s = self.state
        if s == S_IDLE:
            if fence_i or ext_inv:             # 1-cycle invalidate, stay IDLE, then re-fetch
                return S_IDLE
            return S_SEND_AR if miss == 1 else S_IDLE
        if s == S_SEND_AR:
            return S_WAIT_R if arready == 1 else S_SEND_AR
        if s == S_WAIT_R:
            return S_UPDATE_CACHE if rvalid == 1 else S_WAIT_R
        if s == S_UPDATE_CACHE:
            return S_WAKE_UP
        if s == S_WAKE_UP:
            return S_IDLE
        return S_IDLE

    # --- combinational Moore/Mealy outputs ---
    def outputs(self, miss, rvalid, fence_i=0, ext_inv=0):
        o = dict(stall=0, wake_up=0, we=0, arvalid=0, rready=0, inv=0, iflush=0)
        s = self.state
        if s == S_IDLE:
            if fence_i or ext_inv:             # B1: I-Cache invalidate (FENCE.I / host load)
                o["inv"] = 1
                o["stall"] = 1
                o["iflush"] = 1 if fence_i else 0
            elif miss == 1:
                o["stall"] = 1
        elif s == S_SEND_AR:
            o["stall"] = 1
            o["arvalid"] = 1
        elif s == S_WAIT_R:
            o["stall"] = 1
            o["rready"] = 1
            if not self.legacy:
                o["we"] = rvalid          # FIX: capture exactly on RVALID handshake
        elif s == S_UPDATE_CACHE:
            o["stall"] = 1
            if self.legacy:
                o["we"] = 1               # ORIGINAL: capture one cycle after RVALID
        elif s == S_WAKE_UP:
            o["wake_up"] = 1
        return o

    def clock(self, next_state):
        self.state = next_state
