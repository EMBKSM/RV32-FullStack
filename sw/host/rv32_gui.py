#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
rv32_gui.py - Dark "developer console" restyle of the RV32-FullStack GUI.

Same functionality and UART line protocol as rv32_gui.py / rv32_console.py:
  * type RISC-V assembly and see its machine code
  * load it to the FPGA CPU over UART, run / single-step / reset
  * watch the 32 registers (changes highlighted), data memory, serial log
  * watch the board peripherals (LED / SW / BTN), probe / live auto-poll

Only the Qt presentation layer changed (dark terminal theme, restyled
register table, peripheral LEDs, colored serial log, status bar). The
assembler, SerialLink and SerialWorker below are unchanged.

  pip install pyserial PySide6
  python rv32_gui_dark.py
"""
import sys, re, time, os
os.environ.setdefault("QT_LOGGING_RULES", "qt.qpa.fonts.warning=false")  # silence benign DirectWrite font warnings

# ---------------------------------------------------------------------------
# Mini RV32I assembler  (identical encoding logic to the verified console/TB)
# ---------------------------------------------------------------------------
M = (1 << 32) - 1
ABI = {
    'zero':0,'ra':1,'sp':2,'gp':3,'tp':4,'t0':5,'t1':6,'t2':7,'s0':8,'fp':8,'s1':9,
    'a0':10,'a1':11,'a2':12,'a3':13,'a4':14,'a5':15,'a6':16,'a7':17,
    's2':18,'s3':19,'s4':20,'s5':21,'s6':22,'s7':23,'s8':24,'s9':25,'s10':26,'s11':27,
    't3':28,'t4':29,'t5':30,'t6':31}

def reg(t):
    t = t.strip().lower()
    if t in ABI: return ABI[t]
    if re.fullmatch(r'x\d+', t):
        n = int(t[1:])
        if 0 <= n <= 31: return n
    raise ValueError(f"bad register '{t}'")

def imm(t):
    return int(t.strip(), 0)

def _R(f7,rs2,rs1,f3,rd,op): return ((f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op)&M
def _I(im,rs1,f3,rd,op):     return (((im&0xFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op)&M
def _S(im,rs2,rs1,f3,op):    return ((((im>>5)&0x7F)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((im&0x1F)<<7)|op)&M
def _B(im,rs2,rs1,f3,op):
    return ((((im>>12)&1)<<31)|(((im>>5)&0x3F)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|
            (((im>>1)&0xF)<<8)|(((im>>11)&1)<<7)|op)&M
def _U(im,rd,op): return (((im&0xFFFFF)<<12)|(rd<<7)|op)&M
def _J(im,rd,op):
    return ((((im>>20)&1)<<31)|(((im>>1)&0x3FF)<<21)|(((im>>11)&1)<<20)|
            (((im>>12)&0xFF)<<12)|(rd<<7)|op)&M

OP_R,OP_I,OP_LD,OP_S,OP_B,OP_JAL,OP_JALR,OP_LUI,OP_AUIPC = 0x33,0x13,0x03,0x23,0x63,0x6F,0x67,0x37,0x17
RI = {'add':(0,0),'sub':(0x20,0),'sll':(0,1),'slt':(0,2),'sltu':(0,3),
      'xor':(0,4),'srl':(0,5),'sra':(0x20,5),'or':(0,6),'and':(0,7)}
II = {'addi':0,'slti':2,'sltiu':3,'xori':4,'ori':6,'andi':7}
LD = {'lb':0,'lh':1,'lw':2,'lbu':4,'lhu':5}
ST = {'sb':0,'sh':1,'sw':2}
BR = {'beq':0,'bne':1,'blt':4,'bge':5,'bltu':6,'bgeu':7}

def split_ops(s): return [x for x in re.split(r'[,\s]+', s.strip()) if x]

def mem_operand(t):
    m = re.fullmatch(r'(-?(?:0x[0-9a-fA-F]+|\d+))?\((\w+)\)', t.strip())
    if not m: raise ValueError(f"bad mem operand '{t}'")
    return (imm(m.group(1)) if m.group(1) else 0), reg(m.group(2))

def _ck(v, lo, hi, what):
    if not (lo <= v <= hi):
        raise ValueError(f"{what}: immediate {v} out of range [{lo}..{hi}]")
    return v

def _cke(v, lo, hi, what):
    if v & 1:
        raise ValueError(f"{what}: target offset {v} is misaligned (odd)")
    if not (lo <= v <= hi):
        raise ValueError(f"{what}: target out of reach ({v} not in [{lo}..{hi}])")
    return v

def encode(mn, ops, pc, labels):
    mn = mn.lower()
    def tgt(t):
        if t in labels: return labels[t] - pc
        try:
            return imm(t)
        except ValueError:
            raise ValueError(f"unknown label '{t}'")
    if mn in RI: f7,f3 = RI[mn]; return _R(f7,reg(ops[2]),reg(ops[1]),f3,reg(ops[0]),OP_R)
    if mn in II: return _I(_ck(imm(ops[2]),-2048,2047,mn),reg(ops[1]),II[mn],reg(ops[0]),OP_I)
    if mn == 'slli': return _I(_ck(imm(ops[2]),0,31,mn),reg(ops[1]),1,reg(ops[0]),OP_I)
    if mn == 'srli': return _I(_ck(imm(ops[2]),0,31,mn),reg(ops[1]),5,reg(ops[0]),OP_I)
    if mn == 'srai': return _I(0x400|_ck(imm(ops[2]),0,31,mn),reg(ops[1]),5,reg(ops[0]),OP_I)
    if mn in LD: off,rs1 = mem_operand(ops[1]); return _I(_ck(off,-2048,2047,mn),rs1,LD[mn],reg(ops[0]),OP_LD)
    if mn in ST: off,rs1 = mem_operand(ops[1]); return _S(_ck(off,-2048,2047,mn),reg(ops[0]),rs1,ST[mn],OP_S)
    if mn in BR: return _B(_cke(tgt(ops[2]),-4096,4094,mn),reg(ops[1]),reg(ops[0]),BR[mn],OP_B)
    if mn == 'lui':   return _U(_ck(imm(ops[1]),0,0xFFFFF,'lui'),reg(ops[0]),OP_LUI)
    if mn == 'auipc': return _U(_ck(imm(ops[1]),0,0xFFFFF,'auipc'),reg(ops[0]),OP_AUIPC)
    if mn == 'jal':
        if len(ops)==1: return _J(_cke(tgt(ops[0]),-(1<<20),(1<<20)-2,'jal'),0,OP_JAL)
        return _J(_cke(tgt(ops[1]),-(1<<20),(1<<20)-2,'jal'),reg(ops[0]),OP_JAL)
    if mn == 'jalr':
        if len(ops)==2: off,rs1 = mem_operand(ops[1]); return _I(_ck(off,-2048,2047,'jalr'),rs1,0,reg(ops[0]),OP_JALR)
        return _I(_ck(imm(ops[2]),-2048,2047,'jalr'),reg(ops[1]),0,reg(ops[0]),OP_JALR)
    if mn == 'nop':  return _I(0,0,0,0,OP_I)
    if mn == 'mv':   return _I(0,reg(ops[1]),0,reg(ops[0]),OP_I)
    if mn == 'li':   return _I(_ck(imm(ops[1]),-2048,2047,'li'),0,0,reg(ops[0]),OP_I)
    if mn == 'j':    return _J(_cke(tgt(ops[0]),-(1<<20),(1<<20)-2,'j'),0,OP_JAL)
    if mn == 'ret':  return _I(0,1,0,0,OP_JALR)
    if mn in ('halt','hlt'): return _J(0,0,OP_JAL)
    raise ValueError(f"unknown instruction '{mn}'")

def expand(mn, ops):
    mn = mn.lower()
    if mn == 'li':
        rd = ops[0]; v = imm(ops[1]) & M
        sv = v - (1 << 32) if (v & 0x80000000) else v
        if -2048 <= sv <= 2047:
            return [('addi', [rd, 'x0', str(sv)])]
        hi = ((v + 0x800) >> 12) & 0xFFFFF
        lo = v - (hi << 12)
        if lo == 0:
            return [('lui', [rd, str(hi)])]
        return [('lui', [rd, str(hi)]), ('addi', [rd, rd, str(lo)])]
    if mn in ('beqz', 'bnez', 'bgez', 'bltz'):
        base = {'beqz': 'beq', 'bnez': 'bne', 'bgez': 'bge', 'bltz': 'blt'}[mn]
        return [(base, [ops[0], 'x0', ops[1]])]
    if mn in ('blez', 'bgtz'):
        base = {'blez': 'bge', 'bgtz': 'blt'}[mn]
        return [(base, ['x0', ops[0], ops[1]])]
    return [(mn, ops)]

def assemble(lines):
    items, labels, pc = [], {}, 0
    for raw in lines:
        s = raw.split('#')[0].split(';')[0].strip()
        if not s: continue
        while ':' in s:
            lab, _, rest = s.partition(':')
            labels[lab.strip()] = pc
            s = rest.strip()
            if not s: break
        if not s: continue
        mn, *rest = s.split(None, 1)
        ops = split_ops(rest[0]) if rest else []
        for bmn, bops in expand(mn, ops):
            items.append((pc, bmn, bops))
            pc += 4
    return [encode(mn, ops, pc, labels) for (pc, mn, ops) in items]

# ---------------------------------------------------------------------------
# Serial link to the PS monitor
# ---------------------------------------------------------------------------
HALT_WORD = 0x0000006F

PROBE_WORDS = [0x10000137,
               0x00012283,
               0x00412303,
               0x00812383,
               HALT_WORD]

class SerialLink:
    def __init__(self, port, baud):
        import serial
        self.s = serial.Serial(port, baud, timeout=1)
    def close(self):
        try: self.s.close()
        except Exception: pass
    def cmd(self, line):
        self.s.reset_input_buffer()
        self.s.write((line + "\n").encode())
        return self.s.readline().decode(errors="replace").strip()
    def cmd_lines(self, line, n):
        self.s.reset_input_buffer()
        self.s.write((line + "\n").encode())
        return [self.s.readline().decode(errors="replace").strip() for _ in range(n)]

# ---------------------------------------------------------------------------
# Qt
# ---------------------------------------------------------------------------
from PySide6.QtCore import Qt, QObject, QThread, Signal, Slot, QTimer
from PySide6.QtGui import QFont, QColor, QTextCursor, QFontDatabase
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QPlainTextEdit, QPushButton, QLabel,
    QLineEdit, QComboBox, QHBoxLayout, QVBoxLayout, QGridLayout, QSplitter,
    QTabWidget, QTableWidget, QTableWidgetItem, QGroupBox, QHeaderView,
    QCheckBox, QFrame, QMessageBox, QSpinBox, QSizePolicy
)

# ---- palette ----------------------------------------------------------------
C_BG      = "#0a0e15"
C_PANEL   = "#0b1018"
C_PANEL2  = "#080c12"
C_BAR     = "#0c1119"
C_BORDER  = "#1b2330"
C_BORDER2 = "#232c3a"
C_HAIR    = "#131922"
C_TEXT    = "#cdd8e6"
C_DIM     = "#5c6878"
C_DIM2    = "#46586c"
C_GREEN   = "#46d39a"
C_AMBER   = "#ffce47"
C_BLUE    = "#5aa9ff"
C_RED     = "#ff5f56"
C_ORANGE  = "#e8973a"
C_PURPLE  = "#b98bff"

def _pick_mono():
    fams = set(QFontDatabase.families())
    for name in ("IBM Plex Mono", "JetBrains Mono", "Cascadia Code", "Consolas",
                 "DejaVu Sans Mono", "Menlo", "Monaco"):
        if name in fams:
            return name
    return "monospace"

def _pick_sans():
    fams = set(QFontDatabase.families())
    for name in ("IBM Plex Sans", "Segoe UI", "Inter", "Helvetica Neue", "Arial"):
        if name in fams:
            return name
    return "sans-serif"

QSS_TEMPLATE = """
* {{ outline: none; }}
QWidget {{ background: {bg}; color: {text}; font-family: '{sans}'; font-size: 13px; }}
QToolTip {{ background: {panel}; color: {text}; border: 1px solid {border2}; }}

QSplitter::handle {{ background: {border}; }}
QSplitter::handle:horizontal {{ width: 1px; }}
QSplitter::handle:vertical {{ height: 1px; }}

QGroupBox {{
    border: 1px solid {border}; border-radius: 9px; margin-top: 16px;
    padding: 10px 8px 8px 8px; background: {panel};
}}
QGroupBox::title {{
    subcontrol-origin: margin; subcontrol-position: top left; left: 12px; padding: 0 5px;
    color: {dim}; font-size: 10px; font-weight: 600; text-transform: uppercase;
}}

QPlainTextEdit {{
    background: {panel2}; border: 1px solid {border}; border-radius: 7px;
    font-family: '{mono}'; font-size: 13px; padding: 8px;
    selection-background-color: #284268; selection-color: #eaf2ff;
}}

QLineEdit, QComboBox, QSpinBox {{
    background: #11161f; border: 1px solid {border2}; border-radius: 6px;
    padding: 5px 9px; color: {text}; font-family: '{mono}'; font-size: 12px;
}}
QLineEdit:focus, QComboBox:focus, QSpinBox:focus {{ border: 1px solid #3f6da8; }}
QComboBox::drop-down {{ border: none; width: 16px; }}
QComboBox::down-arrow {{ image: none; border-left: 4px solid transparent;
    border-right: 4px solid transparent; border-top: 5px solid {dim};
    margin-right: 6px; }}
QComboBox QAbstractItemView {{
    background: #11161f; border: 1px solid {border2}; color: {text};
    selection-background-color: #1d2838; outline: none;
}}
QSpinBox::up-button, QSpinBox::down-button {{ width: 0; height: 0; border: none; }}

QPushButton {{
    background: #11161f; border: 1px solid {border2}; border-radius: 7px;
    padding: 7px 14px; font-weight: 600; color: #a9b6c6; font-size: 12px;
}}
QPushButton:hover {{ background: #1a2230; }}
QPushButton:pressed {{ background: #0f1722; }}
QPushButton:disabled {{ color: {dim2}; border-color: {border}; background: #0e131b; }}

QPushButton#run {{ background: #14301f; border: 1px solid #2f7a51; color: #8fe0bf; padding: 7px 18px; }}
QPushButton#run:hover {{ background: #173a26; }}
QPushButton#run:disabled {{ background: #0e131b; border-color: {border}; color: {dim2}; }}

QPushButton#connect {{ background: #14301f; border: 1px solid {green}; color: #8fe0bf; }}
QPushButton#connect:hover {{ background: #173a26; }}
QPushButton#connect[on="true"] {{ background: #11161f; border: 1px solid {border2}; color: {text}; }}
QPushButton#connect[on="true"]:hover {{ background: #1a2230; }}

QPushButton#flat {{ background: transparent; border: none; color: {dim}; padding: 4px 6px; }}
QPushButton#flat:hover {{ color: #9fb0c4; }}

QTabWidget::pane {{ border: 1px solid {border}; border-radius: 9px; background: {bg}; top: -1px; }}
QTabBar {{ qproperty-drawBase: 0; }}
QTabBar::tab {{
    background: transparent; color: {dim}; padding: 8px 16px; margin-right: 2px;
    border: none; border-bottom: 2px solid transparent; font-weight: 600; font-size: 12px;
}}
QTabBar::tab:selected {{ color: #dce6f2; border-bottom: 2px solid {blue}; }}
QTabBar::tab:hover {{ color: #aab6c6; }}

QTableWidget {{
    background: {bg}; gridline-color: {hair}; border: 1px solid {border};
    border-radius: 7px; font-family: '{mono}'; font-size: 12px;
}}
QTableWidget::item {{ padding: 2px 8px; border: none; }}
QTableWidget::item:selected {{ background: #1a2536; color: {text}; }}
QHeaderView::section {{
    background: {panel}; color: {dim2}; border: none; border-bottom: 1px solid #141a24;
    padding: 6px 8px; font-family: '{sans}'; font-size: 10px; font-weight: 600;
}}

QCheckBox {{ color: #8fa0b3; font-family: '{mono}'; font-size: 12px; spacing: 7px; }}
QCheckBox::indicator {{ width: 14px; height: 14px; border: 1px solid #384356; border-radius: 4px; background: transparent; }}
QCheckBox::indicator:checked {{ background: {blue}; border-color: {blue}; image: none; }}

QScrollBar:vertical {{ background: transparent; width: 10px; margin: 0; }}
QScrollBar::handle:vertical {{ background: #283142; border-radius: 5px; min-height: 26px; }}
QScrollBar::handle:vertical:hover {{ background: #36425a; }}
QScrollBar:horizontal {{ background: transparent; height: 10px; margin: 0; }}
QScrollBar::handle:horizontal {{ background: #283142; border-radius: 5px; min-width: 26px; }}
QScrollBar::add-line, QScrollBar::sub-line {{ width: 0; height: 0; }}
QScrollBar::add-page, QScrollBar::sub-page {{ background: transparent; }}

QStatusBar {{ background: {bar}; color: {dim}; border-top: 1px solid {border};
    font-family: '{mono}'; font-size: 11px; }}
QStatusBar::item {{ border: none; }}
"""


class SerialWorker(QObject):
    logged       = Signal(str, str)
    connected    = Signal(bool, str)
    regsReady    = Signal(object)
    memReady     = Signal(int, int)
    periphReady  = Signal(int, int, int, str)
    statusReady  = Signal(int)
    busy         = Signal(bool)
    note         = Signal(str)

    def __init__(self):
        super().__init__()
        self.link = None
        self.periph_direct = None
        self.fw_has_lwn = False

    def _tx(self, line):
        self.logged.emit(">", line)
        r = self.link.cmd(line)
        self.logged.emit("<", r)
        return r

    @Slot(str, int)
    def do_connect(self, port, baud):
        try:
            self.link = SerialLink(port, baud)
        except Exception as e:
            self.connected.emit(False, str(e)); return
        self.periph_direct = None
        try:
            r = self.link.cmd("L")
            self.logged.emit(">", "L"); self.logged.emit("<", r)
            self.fw_has_lwn = bool(re.search(r'led\s*=\s*[0-9a-fA-F]+', r))
        except Exception:
            self.fw_has_lwn = False
        self.periph_direct = self._verify_direct() if self.fw_has_lwn else False
        mode = "direct" if self.periph_direct else "probe"
        self.connected.emit(True, f"{port} @ {baud}  (peripherals: {mode})")
        if self.fw_has_lwn and not self.periph_direct:
            self.note.emit("Peripherals: probe mode (this bitstream has no direct "
                           "readback). Use 'Refresh / Probe' to read SW/BTN; live "
                           "auto-poll needs the peripheral-readback bitstream.")

    @Slot()
    def do_disconnect(self):
        if self.link: self.link.close(); self.link = None
        self.connected.emit(False, "disconnected")

    @Slot(list, bool)
    def do_run(self, words, run):
        if not self.link: return
        self.busy.emit(True)
        try:
            self._tx("r")
            for i, w in enumerate(words):
                self._tx(f"i {i*4:x} {w & M:08x}")
            self._tx(f"i {len(words)*4:x} {HALT_WORD:08x}")
            if run:
                self._tx("g")
                time.sleep(0.15)
            self._emit_regs()
        finally:
            self.busy.emit(False)

    @Slot()
    def do_step(self):
        if not self.link: return
        self.busy.emit(True)
        try:
            self._tx("s")
            self._emit_regs()
        finally:
            self.busy.emit(False)

    @Slot()
    def do_reset(self):
        if not self.link: return
        self.busy.emit(True)
        try:
            self._tx("r"); self._emit_regs()
        finally:
            self.busy.emit(False)

    @Slot()
    def do_read_regs(self):
        if not self.link: return
        self.busy.emit(True)
        try: self._emit_regs()
        finally: self.busy.emit(False)

    def _emit_regs(self):
        out = self.link.cmd_lines("D", 32)
        self.logged.emit(">", "D")
        regs = {}
        for ln in out:
            m = re.fullmatch(r'x(\d+)\s*=\s*([0-9a-fA-F]+)', ln.strip())
            if m: regs[int(m.group(1))] = int(m.group(2), 16)
        nz = "  ".join(f"x{n}={regs[n]:x}" for n in sorted(regs) if regs[n])
        self.logged.emit("<", f"regs: {nz if nz else '(all zero)'}")
        self.regsReady.emit(regs)

    @Slot(int)
    def do_read_mem(self, addr):
        if not self.link: return
        r = self._tx(f"m {addr:x}")
        m = re.search(r'=\s*([0-9a-fA-F]+)', r)
        if m: self.memReady.emit(addr, int(m.group(1), 16))

    @Slot()
    def do_poll_periph(self):
        if not self.link or not self.periph_direct: return
        try:
            rl = self.link.cmd("L"); rs = self.link.cmd("W"); rb = self.link.cmd("N")
            def val(s):
                m = re.search(r'=\s*([0-9a-fA-F]+)', s); return int(m.group(1),16) if m else 0
            self.periphReady.emit(val(rl), val(rs), val(rb), "direct")
        except Exception:
            pass

    @Slot()
    def do_probe_periph(self):
        if not self.link: return
        self.busy.emit(True)
        try:
            self._tx("r")
            for i, w in enumerate(PROBE_WORDS):
                self._tx(f"i {i*4:x} {w:08x}")
            self._tx("g"); time.sleep(0.12)
            led = self._read_reg(5); sw = self._read_reg(6); btn = self._read_reg(7)
            self.periphReady.emit(led & 0xF, sw & 0xF, btn & 0xF, "probe")
            self.note.emit("Peripherals probed via micro-program (CPU program overwritten; press Run to reload yours).")
        finally:
            self.busy.emit(False)

    def _verify_direct(self):
        try:
            self.logged.emit("*", "peripheral capability check…")
            self.link.cmd("r")
            for i, w in enumerate(PROBE_WORDS):
                self.link.cmd(f"i {i*4:x} {w:08x}")
            self.link.cmd("g"); time.sleep(0.12)
            led_t, sw_t, btn_t = (self._read_reg(5) & 0xF,
                                  self._read_reg(6) & 0xF,
                                  self._read_reg(7) & 0xF)
            def val(s):
                m = re.search(r'=\s*([0-9a-fA-F]+)', s)
                return int(m.group(1), 16) if m else 0
            led_d = val(self.link.cmd("L")) & 0xF
            sw_d  = val(self.link.cmd("W")) & 0xF
            btn_d = val(self.link.cmd("N")) & 0xF
            agree   = (led_d == led_t and sw_d == sw_t and btn_d == btn_t)
            nonzero = bool(led_t or sw_t or btn_t)
            ok = bool(agree and nonzero)
            self.logged.emit("*", f"MMIO L/S/B={led_t:x}/{sw_t:x}/{btn_t:x}  "
                                  f"direct={led_d:x}/{sw_d:x}/{btn_d:x}  -> "
                                  f"{'direct' if ok else 'probe'}")
            self.link.cmd("r")
            return ok
        except Exception as e:
            self.logged.emit("*", f"capability check failed: {e}")
            return False

    def _read_reg(self, n):
        r = self._tx(f"x {n:x}")
        m = re.search(r'=\s*([0-9a-fA-F]+)', r)
        return int(m.group(1), 16) if m else 0


class LedDot(QFrame):
    """A small round indicator. set(True/False) to light it."""
    def __init__(self, on_color, diameter=28):
        super().__init__()
        self.on_color, self.d = on_color, diameter
        self.setFixedSize(diameter, diameter)
        self.set(False)
    def set(self, on):
        if on:
            self.setStyleSheet(
                f"background:{self.on_color}; border-radius:{self.d//2}px; "
                f"border:1px solid {self.on_color};")
        else:
            self.setStyleSheet(
                f"background:#10161f; border-radius:{self.d//2}px; border:1px solid #28313f;")


class MainWindow(QMainWindow):
    reqConnect    = Signal(str, int)
    reqDisconnect = Signal()
    reqRun        = Signal(list, bool)
    reqStep       = Signal()
    reqReset      = Signal()
    reqReadRegs   = Signal()
    reqReadMem    = Signal(int)
    reqPoll       = Signal()
    reqProbe      = Signal()

    def __init__(self):
        super().__init__()
        self.setWindowTitle("RV32-FullStack  —  FPGA RISC-V Console")
        self.resize(1240, 820)
        self.setMinimumSize(1060, 680)
        self.prev_regs = {n: 0 for n in range(32)}
        self.connected = False
        self.periph_mode = "probe"
        self._build_ui()
        self._start_worker()
        self._refresh_ports()

    # ---------- worker thread ----------
    def _start_worker(self):
        self.thread = QThread(self)
        self.worker = SerialWorker()
        self.worker.moveToThread(self.thread)
        self.reqConnect.connect(self.worker.do_connect)
        self.reqDisconnect.connect(self.worker.do_disconnect)
        self.reqRun.connect(self.worker.do_run)
        self.reqStep.connect(self.worker.do_step)
        self.reqReset.connect(self.worker.do_reset)
        self.reqReadRegs.connect(self.worker.do_read_regs)
        self.reqReadMem.connect(self.worker.do_read_mem)
        self.reqPoll.connect(self.worker.do_poll_periph)
        self.reqProbe.connect(self.worker.do_probe_periph)
        self.worker.logged.connect(self._on_log)
        self.worker.connected.connect(self._on_connected)
        self.worker.regsReady.connect(self._on_regs)
        self.worker.memReady.connect(self._on_mem)
        self.worker.periphReady.connect(self._on_periph)
        self.worker.busy.connect(self._on_busy)
        self.worker.note.connect(self._on_note)
        self.thread.start()
        self.poll_timer = QTimer(self)
        self.poll_timer.setInterval(800)
        self.poll_timer.timeout.connect(self._maybe_poll)

    # ---------- small helpers ----------
    def _section_label(self, text):
        lab = QLabel(text)
        lab.setStyleSheet(f"color:{C_DIM}; font-size:10px; font-weight:600; "
                          f"letter-spacing:1.4px; padding:2px 2px;")
        return lab

    # ---------- UI ----------
    def _build_ui(self):
        # ===== top title + connection bar =====
        bar = QHBoxLayout(); bar.setContentsMargins(16, 10, 14, 10); bar.setSpacing(10)
        title = QLabel("RV32-FullStack  —  FPGA RISC-V Console")
        title.setStyleSheet(f"color:#8a98ab; font-family:'{MONO_FAMILY}'; font-size:13px;")
        bar.addWidget(title)
        bar.addStretch(1)

        def tiny(text):
            l = QLabel(text); l.setStyleSheet(f"color:{C_DIM}; font-family:'{MONO_FAMILY}'; font-size:11px;")
            return l

        self.port_box = QComboBox(); self.port_box.setEditable(True); self.port_box.setMinimumWidth(140)
        self.baud_box = QComboBox(); self.baud_box.addItems(["115200","9600","19200","57600","230400"])
        self.btn_refresh = QPushButton("Ports"); self.btn_refresh.clicked.connect(self._refresh_ports)
        self.btn_conn = QPushButton("Connect"); self.btn_conn.setObjectName("connect"); self.btn_conn.clicked.connect(self._toggle_conn)
        self.lbl_conn = QLabel("● offline")
        self.lbl_conn.setStyleSheet(f"color:{C_RED}; font-family:'{MONO_FAMILY}'; font-size:11px; "
                                    f"padding:5px 11px; border:1px solid #3a2422; border-radius:999px; background:#1a1011;")
        bar.addWidget(tiny("PORT")); bar.addWidget(self.port_box)
        bar.addWidget(self.btn_refresh)
        bar.addWidget(tiny("BAUD")); bar.addWidget(self.baud_box)
        bar.addWidget(self.btn_conn); bar.addWidget(self.lbl_conn)
        bar_w = QWidget(); bar_w.setStyleSheet(f"background:{C_BAR}; border-bottom:1px solid {C_BORDER};")
        bar_w.setLayout(bar)

        # ===== left: editor + buttons + machine code =====
        self.editor = QPlainTextEdit(); self.editor.setFont(MONO)
        self.editor.setPlainText(
            "# RV32I demo — edit, then Run\n"
            "addi x1, x0, 7\n"
            "addi x2, x0, 11\n"
            "add  x3, x1, x2      # x3 = 18\n"
            "sw   x3, 0(x0)       # store to data RAM\n"
            "lui  x4, 0x10000     # x4 = LED base\n"
            "sw   x1, 0(x4)       # drive LEDs = 7\n")
        self.editor.textChanged.connect(self._live_assemble)

        btns = QHBoxLayout(); btns.setSpacing(7)
        self.btn_run   = QPushButton("▶  Run"); self.btn_run.setObjectName("run")
        self.btn_step  = QPushButton("Step")
        self.btn_reset = QPushButton("Reset")
        self.btn_asm   = QPushButton("Assemble")
        for b in (self.btn_run, self.btn_step, self.btn_reset, self.btn_asm): btns.addWidget(b)
        btns.addStretch(1)
        self.btn_run.clicked.connect(self._run)
        self.btn_step.clicked.connect(lambda: self._guard(self.reqStep.emit))
        self.btn_reset.clicked.connect(lambda: self._guard(self.reqReset.emit))
        self.btn_asm.clicked.connect(self._assemble_preview)

        self.mcode = QPlainTextEdit(); self.mcode.setFont(MONO); self.mcode.setReadOnly(True)
        self.mcode.setFixedHeight(178); self.mcode.setPlaceholderText("machine code…")

        left = QWidget(); lv = QVBoxLayout(left); lv.setContentsMargins(12,10,8,10); lv.setSpacing(8)
        ed_head = QHBoxLayout()
        ed_head.addWidget(self._section_label("ASSEMBLY")); ed_head.addStretch(1)
        self.lbl_asmtag = QLabel("")
        self.lbl_asmtag.setStyleSheet(f"color:{C_DIM}; font-family:'{MONO_FAMILY}'; font-size:10px;")
        ed_head.addWidget(self.lbl_asmtag)
        lv.addLayout(ed_head)
        lv.addWidget(self.editor, 1)
        lv.addLayout(btns)
        lv.addWidget(self._section_label("MACHINE CODE"))
        lv.addWidget(self.mcode)

        # ===== right: tabs =====
        self.tabs = QTabWidget()
        self.tabs.addTab(self._build_regs_tab(), "Registers")
        self.tabs.addTab(self._build_mem_tab(),  "Data memory")
        self.tabs.addTab(self._build_periph_tab(), "Peripherals")
        right = QWidget(); rv = QVBoxLayout(right); rv.setContentsMargins(8,10,12,10)
        rv.addWidget(self.tabs)

        top = QSplitter(Qt.Horizontal); top.addWidget(left); top.addWidget(right)
        top.setSizes([560, 640]); top.setHandleWidth(1)

        # ===== serial log =====
        log_w = QWidget(); lgl = QVBoxLayout(log_w); lgl.setContentsMargins(12,8,12,10); lgl.setSpacing(6)
        log_head = QHBoxLayout()
        log_head.addWidget(self._section_label("SERIAL LOG")); log_head.addStretch(1)
        b_clear = QPushButton("clear log"); b_clear.setObjectName("flat"); b_clear.clicked.connect(self._clear_log)
        log_head.addWidget(b_clear)
        self.log = QPlainTextEdit(); self.log.setFont(MONO); self.log.setReadOnly(True)
        self.log.setMaximumBlockCount(2000)
        self.log.setStyleSheet(f"background:{C_PANEL2}; border:1px solid {C_BORDER}; border-radius:7px;")
        lgl.addLayout(log_head); lgl.addWidget(self.log)

        outer = QSplitter(Qt.Vertical); outer.addWidget(top); outer.addWidget(log_w)
        outer.setSizes([560, 200]); outer.setHandleWidth(1)

        central = QWidget(); central.setObjectName("central")
        cv = QVBoxLayout(central); cv.setContentsMargins(0,0,0,0); cv.setSpacing(0)
        cv.addWidget(bar_w); cv.addWidget(outer, 1)
        self.setCentralWidget(central)

        self.statusBar().showMessage("Ready. Connect to the board, type assembly, press Run.")
        self._live_assemble()
        self._set_online(False)

    def _build_regs_tab(self):
        w = QWidget(); v = QVBoxLayout(w); v.setContentsMargins(12,12,12,12); v.setSpacing(10)
        self.reg_table = QTableWidget(32, 3)
        self.reg_table.setHorizontalHeaderLabels(["reg", "hex", "dec"])
        self.reg_table.verticalHeader().setVisible(False)
        self.reg_table.setFont(MONO)
        self.reg_table.setShowGrid(False)
        self.reg_table.horizontalHeader().setSectionResizeMode(0, QHeaderView.Stretch)
        self.reg_table.horizontalHeader().setSectionResizeMode(1, QHeaderView.ResizeToContents)
        self.reg_table.horizontalHeader().setSectionResizeMode(2, QHeaderView.Stretch)
        self.reg_table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.reg_table.setSelectionMode(QTableWidget.NoSelection)
        self.reg_table.setVerticalScrollMode(QTableWidget.ScrollPerPixel)
        abi_names = ['zero','ra','sp','gp','tp','t0','t1','t2','s0','s1','a0','a1','a2','a3',
                     'a4','a5','a6','a7','s2','s3','s4','s5','s6','s7','s8','s9','s10','s11',
                     't3','t4','t5','t6']
        for n in range(32):
            it0 = QTableWidgetItem(f"x{n}  {abi_names[n]}")
            it1 = QTableWidgetItem("0x00000000")
            it2 = QTableWidgetItem("0"); it2.setTextAlignment(Qt.AlignRight | Qt.AlignVCenter)
            self.reg_table.setItem(n,0,it0); self.reg_table.setItem(n,1,it1); self.reg_table.setItem(n,2,it2)
            self.reg_table.setRowHeight(n, 24)
        r = QHBoxLayout(); r.setSpacing(14)
        b = QPushButton("Refresh registers"); b.clicked.connect(lambda: self._guard(self.reqReadRegs.emit))
        self.chk_signed = QCheckBox("signed dec"); self.chk_signed.stateChanged.connect(self._redraw_regs)
        r.addWidget(b); r.addWidget(self.chk_signed); r.addStretch(1)
        v.addWidget(self.reg_table); v.addLayout(r)
        self._last_regs = dict(self.prev_regs)
        self._redraw_regs()
        return w

    def _build_mem_tab(self):
        w = QWidget(); v = QVBoxLayout(w); v.setContentsMargins(12,12,12,12); v.setSpacing(10)
        row = QHBoxLayout(); row.setSpacing(9)
        self.mem_addr = QLineEdit("0x00000000"); self.mem_addr.setFont(MONO); self.mem_addr.setFixedWidth(140)
        self.mem_count = QSpinBox(); self.mem_count.setRange(1,64); self.mem_count.setValue(8); self.mem_count.setFixedWidth(70)
        b = QPushButton("Read"); b.clicked.connect(self._read_mem_range)
        row.addWidget(self._mono_lab("addr")); row.addWidget(self.mem_addr)
        row.addWidget(self._mono_lab("words")); row.addWidget(self.mem_count)
        row.addWidget(b); row.addStretch(1)
        self.mem_table = QTableWidget(0, 2)
        self.mem_table.setHorizontalHeaderLabels(["address", "word (hex)"])
        self.mem_table.verticalHeader().setVisible(False)
        self.mem_table.setFont(MONO); self.mem_table.setShowGrid(False)
        self.mem_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.mem_table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.mem_table.setSelectionMode(QTableWidget.NoSelection)
        self._mem_rows = {}
        note = QLabel("Reads the data RAM via the PS dump port (MMIO region 0x1000_xxxx not included).")
        note.setStyleSheet(f"color:{C_DIM2}; font-family:'{MONO_FAMILY}'; font-size:10px;")
        v.addLayout(row); v.addWidget(self.mem_table, 1); v.addWidget(note)
        return w

    def _build_periph_tab(self):
        w = QWidget(); v = QVBoxLayout(w); v.setContentsMargins(16,16,16,16); v.setSpacing(14)
        gb = QGroupBox("Board peripherals"); gv = QVBoxLayout(gb); gv.setContentsMargins(16,16,16,14); gv.setSpacing(14)
        g = QGridLayout(); g.setHorizontalSpacing(12); g.setVerticalSpacing(14)
        self.led_dots = [LedDot(C_AMBER) for _ in range(4)]
        self.sw_dots  = [LedDot(C_GREEN) for _ in range(4)]
        self.btn_dots = [LedDot(C_BLUE)  for _ in range(4)]
        for r,(name, dotrow) in enumerate([("LED  [3..0]", self.led_dots),
                                           ("SW   [3..0]", self.sw_dots),
                                           ("BTN  [3..0]", self.btn_dots)]):
            lab = QLabel(name); lab.setStyleSheet(f"color:#8fa0b3; font-family:'{MONO_FAMILY}'; font-size:12px;")
            g.addWidget(lab, r, 0)
            for i in range(4):                       # MSB on the left
                g.addWidget(dotrow[3-i], r, i+1, Qt.AlignCenter)
        g.setColumnStretch(5, 1)
        gv.addLayout(g)
        row = QHBoxLayout(); row.setSpacing(12)
        self.btn_probe = QPushButton("Refresh / Probe")
        self.btn_probe.clicked.connect(self._probe_periph)
        self.chk_autopoll = QCheckBox("auto-poll (live)")
        self.chk_autopoll.stateChanged.connect(self._toggle_poll)
        row.addWidget(self.btn_probe); row.addWidget(self.chk_autopoll); row.addStretch(1)
        gv.addLayout(row)
        self.lbl_periph = QLabel(
            "LED is driven by your program's stores to 0x1000_0000.\n"
            "SW / BTN are physical board inputs read at 0x1000_0004 / 0x1000_0008.")
        self.lbl_periph.setStyleSheet(f"color:{C_DIM2}; font-family:'{MONO_FAMILY}'; font-size:11px;")
        v.addWidget(gb); v.addWidget(self.lbl_periph); v.addStretch(1)
        return w

    def _mono_lab(self, text):
        l = QLabel(text); l.setStyleSheet(f"color:{C_DIM}; font-family:'{MONO_FAMILY}'; font-size:11px;")
        return l

    # ---------- actions ----------
    def _refresh_ports(self):
        cur = self.port_box.currentText()
        self.port_box.clear()
        try:
            from serial.tools import list_ports
            for p in list_ports.comports():
                self.port_box.addItem(p.device)
        except Exception:
            pass
        if cur: self.port_box.setEditText(cur)

    def _toggle_conn(self):
        if self.connected:
            self.poll_timer.stop()
            self.reqDisconnect.emit()
        else:
            port = self.port_box.currentText().strip()
            if not port:
                QMessageBox.warning(self, "No port", "Select or type a serial port (e.g. COM5)."); return
            self._set_conn_label("connecting…", C_ORANGE)
            self.reqConnect.emit(port, int(self.baud_box.currentText()))

    def _set_conn_label(self, text, color):
        self.lbl_conn.setText(text if text.startswith("●") else "● " + text)
        tint = {C_GREEN: ("#14301f", "#2f7a51"), C_RED: ("#1a1011", "#3a2422"),
                C_ORANGE: ("#211608", "#4a3417")}.get(color, ("#11161f", C_BORDER2))
        self.lbl_conn.setStyleSheet(
            f"color:{color}; font-family:'{MONO_FAMILY}'; font-size:11px; "
            f"padding:5px 11px; border:1px solid {tint[1]}; border-radius:999px; background:{tint[0]};")

    def _live_assemble(self):
        """Assemble on every edit to keep the machine-code panel live (offline-safe)."""
        try:
            words = assemble(self.editor.toPlainText().splitlines())
            lines = "\n".join(f"{i*4:04x}:   {w:08x}" for i, w in enumerate(words))
            self.mcode.setPlainText(lines)
            self.lbl_asmtag.setText(f"{len(words)} words · {len(words)*4} B")
            self.lbl_asmtag.setStyleSheet(f"color:{C_DIM}; font-family:'{MONO_FAMILY}'; font-size:10px;")
            return words
        except Exception as e:
            self.mcode.setPlainText(f"; error: {e}")
            self.lbl_asmtag.setText("● assemble error")
            self.lbl_asmtag.setStyleSheet(f"color:{C_RED}; font-family:'{MONO_FAMILY}'; font-size:10px;")
            return None

    def _assemble_preview(self):
        words = self._live_assemble()
        if words is not None:
            self.statusBar().showMessage(f"assembled {len(words)} instruction(s).", 4000)
        else:
            self.statusBar().showMessage("assembler error (see machine code panel).", 4000)

    def _run(self):
        words = self._live_assemble()
        if words is None:
            QMessageBox.warning(self, "Assembler error", "Fix the assembly (see machine code panel)."); return
        if not words:
            self.statusBar().showMessage("empty program.", 3000); return
        if not self.connected:
            self.statusBar().showMessage("offline — assembled only (connect to run).", 4000); return
        self._guard(lambda: self.reqRun.emit(words, True))

    def _read_mem_range(self):
        if not self.connected: return
        try: base = int(self.mem_addr.text().strip(), 0)
        except ValueError: return
        n = self.mem_count.value()
        self.mem_table.setRowCount(n); self._mem_rows = {}
        for i in range(n):
            a = base + i*4
            self._mem_rows[a] = i
            it0 = QTableWidgetItem(f"0x{a:08x}"); it0.setForeground(QColor("#6b7888"))
            it1 = QTableWidgetItem("…");          it1.setForeground(QColor(C_DIM2))
            self.mem_table.setItem(i,0,it0); self.mem_table.setItem(i,1,it1)
            self.mem_table.setRowHeight(i, 25)
            self._guard(lambda a=a: self.reqReadMem.emit(a))

    def _probe_periph(self):
        if not self.connected: return
        if self.periph_mode == "direct":
            self._guard(self.reqPoll.emit)
        else:
            self._guard(self.reqProbe.emit)

    def _toggle_poll(self, state):
        if state and self.connected and self.periph_mode == "direct":
            self.poll_timer.start()
        else:
            self.poll_timer.stop()
            if state and self.periph_mode != "direct":
                self.chk_autopoll.setChecked(False)
                QMessageBox.information(self, "Live poll unavailable",
                    "Live auto-poll needs the optional peripheral-readback firmware/bitstream "
                    "(L/W/N commands). Use 'Refresh / Probe' instead, or rebuild with the upgrade "
                    "(see README).")

    def _maybe_poll(self):
        if self.connected and self.periph_mode == "direct" and not self._is_busy():
            self.reqPoll.emit()

    def _clear_log(self):
        self.log.clear()

    # ---------- worker callbacks ----------
    @Slot(str, str)
    def _on_log(self, d, text):
        color = {">": C_BLUE, "<": C_GREEN, "*": C_PURPLE}.get(d, C_DIM)
        body  = {">": "#7e8da0", "<": "#8fe0bf", "*": "#b98bff"}.get(d, C_TEXT)
        safe = (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))
        self.log.appendHtml(
            f'<span style="color:{color}; font-weight:600;">{d}</span>'
            f'<span style="color:{body};"> {safe}</span>')
        self.log.moveCursor(QTextCursor.End)

    @Slot(bool, str)
    def _on_connected(self, ok, msg):
        self.connected = ok
        self._set_online(ok)
        if ok:
            self._set_conn_label(msg, C_GREEN)
            self.periph_mode = "direct" if "direct" in msg else "probe"
            self.btn_probe.setText("Refresh (live)" if self.periph_mode=="direct" else "Probe (micro-program)")
            self.reqReadRegs.emit()
        else:
            self._set_conn_label(msg if msg else "offline", C_RED)
            self.poll_timer.stop()

    @Slot(dict)
    def _on_regs(self, regs):
        self._last_regs = dict(self.prev_regs)
        self.prev_regs = {n: regs.get(n, 0) for n in range(32)}
        self._redraw_regs()

    def _redraw_regs(self):
        signed = self.chk_signed.isChecked()
        self.reg_table.horizontalHeaderItem(2).setText("dec (signed)" if signed else "dec")
        amber_bg = QColor("#2c2713"); amber_fg = QColor("#ffdc78")
        for n in range(32):
            v = self.prev_regs.get(n, 0)
            changed = self._last_regs.get(n,0) != v
            zero = (v == 0)
            self.reg_table.item(n,1).setText(f"0x{v:08x}")
            dec = v - (1<<32) if (signed and v & 0x80000000) else v
            self.reg_table.item(n,2).setText(str(dec))
            name_fg = QColor("#54606f") if zero else QColor("#9fb0c4")
            hex_fg  = amber_fg if changed else (QColor("#3a4452") if zero else QColor(C_TEXT))
            dec_fg  = amber_fg if changed else (QColor("#3a4452") if zero else QColor("#7e8da0"))
            bg = amber_bg if changed else QColor(Qt.transparent)
            cols_fg = [name_fg, hex_fg, dec_fg]
            for c in range(3):
                self.reg_table.item(n,c).setBackground(bg)
                self.reg_table.item(n,c).setForeground(cols_fg[c])

    @Slot(int, int)
    def _on_mem(self, addr, val):
        i = self._mem_rows.get(addr)
        if i is not None:
            it = QTableWidgetItem(f"0x{val:08x}")
            it.setForeground(QColor(C_BLUE) if val else QColor("#3f4a57"))
            self.mem_table.setItem(i,1,it)

    @Slot(int, int, int, str)
    def _on_periph(self, led, sw, btn, mode):
        for i in range(4): self.led_dots[i].set(bool((led>>i)&1))
        for i in range(4): self.sw_dots[i].set(bool((sw>>i)&1))
        for i in range(4): self.btn_dots[i].set(bool((btn>>i)&1))
        self.statusBar().showMessage(
            f"peripherals ({mode}): LED={led:04b} SW={sw:04b} BTN={btn:04b}", 4000)

    @Slot(bool)
    def _on_busy(self, b):
        self._busy = b
        for w in (self.btn_run, self.btn_step, self.btn_reset, self.btn_probe):
            w.setEnabled(self.connected and not b)

    @Slot(str)
    def _on_note(self, s):
        self.statusBar().showMessage(s, 6000)

    # ---------- helpers ----------
    def _is_busy(self):  return getattr(self, "_busy", False)
    def _guard(self, fn):
        if not self.connected:
            self.statusBar().showMessage("not connected.", 3000); return
        if self._is_busy():
            self.statusBar().showMessage("busy…", 1500); return
        fn()

    def _set_online(self, on):
        for w in (self.btn_run, self.btn_step, self.btn_reset, self.btn_probe):
            w.setEnabled(on)
        self.btn_conn.setText("Disconnect" if on else "Connect")
        self.btn_conn.setProperty("on", "true" if on else "false")
        self.btn_conn.style().unpolish(self.btn_conn); self.btn_conn.style().polish(self.btn_conn)

    def closeEvent(self, e):
        try:
            self.poll_timer.stop()
            self.reqDisconnect.emit()
            self.thread.quit(); self.thread.wait(800)
        except Exception:
            pass
        super().closeEvent(e)


MONO = None
MONO_FAMILY = "monospace"


def _apply_dark_titlebar(win):
    """Native Windows frame, but with a dark title bar (Win10 20H1+/Win11) so the
    window chrome matches the dark app. Native controls / resize / snap / shadow stay."""
    if not sys.platform.startswith("win"):
        return
    try:
        import ctypes
        hwnd = ctypes.c_void_p(int(win.winId()))
        dwm = ctypes.windll.dwmapi
        on = ctypes.c_int(1)
        for attr in (20, 19):                        # DWMWA_USE_IMMERSIVE_DARK_MODE
            if dwm.DwmSetWindowAttribute(hwnd, ctypes.c_int(attr),
                    ctypes.byref(on), ctypes.c_uint(ctypes.sizeof(on))) == 0:
                break
        rnd = ctypes.c_int(2)                         # DWMWA_WINDOW_CORNER_PREFERENCE -> round
        dwm.DwmSetWindowAttribute(hwnd, ctypes.c_int(33),
                ctypes.byref(rnd), ctypes.c_uint(ctypes.sizeof(rnd)))
    except Exception:
        pass


def main():
    global MONO, MONO_FAMILY
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    mono_family = _pick_mono(); sans_family = _pick_sans()
    MONO_FAMILY = mono_family
    MONO = QFont(mono_family); MONO.setStyleHint(QFont.Monospace); MONO.setPointSize(10)
    app.setStyleSheet(QSS_TEMPLATE.format(
        bg=C_BG, panel=C_PANEL, panel2=C_PANEL2, bar=C_BAR, border=C_BORDER, border2=C_BORDER2,
        hair=C_HAIR, text=C_TEXT, dim=C_DIM, dim2=C_DIM2, green=C_GREEN, blue=C_BLUE,
        mono=mono_family, sans=sans_family))
    win = MainWindow()
    _apply_dark_titlebar(win)
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
