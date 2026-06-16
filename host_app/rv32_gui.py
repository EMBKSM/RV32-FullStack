#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
rv32_gui.py - Windows/PC desktop GUI for the RV32-FullStack FPGA CPU.

A PySide6 application that lets you:
  * type RISC-V assembly and see its machine code
  * load it to the FPGA CPU over UART (via the Zynq PS monitor), run / single-step
  * watch the 32 registers (changes highlighted), data memory, and a raw serial log
  * watch the board peripherals (LED / SW / BTN)

  pip install pyserial PySide6
  python rv32_gui.py

The same UART line protocol as rv32_console.py is used (PS monitor):
  r | i A D | d A D | g | s | x N | m A | p | c | t | D    (all numbers hex)
Optional peripheral readback commands (L / W / N) are auto-detected; if the
running firmware/bitstream does not support them, the panel falls back to an
on-demand "probe" micro-program that works on any build.
"""
import sys, re, time

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
    m = re.fullmatch(r'(-?(?:0x)?[0-9a-fA-F]+)?\((\w+)\)', t.strip())
    if not m: raise ValueError(f"bad mem operand '{t}'")
    return (imm(m.group(1)) if m.group(1) else 0), reg(m.group(2))

def encode(mn, ops, pc, labels):
    mn = mn.lower()
    def tgt(t):
        if t in labels: return labels[t] - pc
        return imm(t)
    if mn in RI: f7,f3 = RI[mn]; return _R(f7,reg(ops[2]),reg(ops[1]),f3,reg(ops[0]),OP_R)
    if mn in II: return _I(imm(ops[2]),reg(ops[1]),II[mn],reg(ops[0]),OP_I)
    if mn == 'slli': return _I(imm(ops[2])&0x1F,reg(ops[1]),1,reg(ops[0]),OP_I)
    if mn == 'srli': return _I(imm(ops[2])&0x1F,reg(ops[1]),5,reg(ops[0]),OP_I)
    if mn == 'srai': return _I(0x400|(imm(ops[2])&0x1F),reg(ops[1]),5,reg(ops[0]),OP_I)
    if mn in LD: off,rs1 = mem_operand(ops[1]); return _I(off,rs1,LD[mn],reg(ops[0]),OP_LD)
    if mn in ST: off,rs1 = mem_operand(ops[1]); return _S(off,reg(ops[0]),rs1,ST[mn],OP_S)
    if mn in BR: return _B(tgt(ops[2]),reg(ops[1]),reg(ops[0]),BR[mn],OP_B)
    if mn == 'lui':   return _U(imm(ops[1]),reg(ops[0]),OP_LUI)
    if mn == 'auipc': return _U(imm(ops[1]),reg(ops[0]),OP_AUIPC)
    if mn == 'jal':
        if len(ops)==1: return _J(tgt(ops[0]),0,OP_JAL)
        return _J(tgt(ops[1]),reg(ops[0]),OP_JAL)
    if mn == 'jalr':
        if len(ops)==2: off,rs1 = mem_operand(ops[1]); return _I(off,rs1,0,reg(ops[0]),OP_JALR)
        return _I(imm(ops[2]),reg(ops[1]),0,reg(ops[0]),OP_JALR)
    if mn == 'nop':  return _I(0,0,0,0,OP_I)
    if mn == 'mv':   return _I(0,reg(ops[1]),0,reg(ops[0]),OP_I)
    if mn == 'li':   return _I(imm(ops[1]),0,0,reg(ops[0]),OP_I)
    if mn == 'j':    return _J(tgt(ops[0]),0,OP_JAL)
    if mn == 'ret':  return _I(0,1,0,0,OP_JALR)
    if mn in ('halt','hlt'): return _J(0,0,OP_JAL)
    raise ValueError(f"unknown instruction '{mn}'")

def assemble(lines):
    """Two-pass: returns list of 32-bit words. Raises ValueError on bad input."""
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
        items.append((pc, mn, split_ops(rest[0]) if rest else []))
        pc += 4
    return [encode(mn, ops, pc, labels) for (pc, mn, ops) in items]

# ---------------------------------------------------------------------------
# Serial link to the PS monitor
# ---------------------------------------------------------------------------
HALT_WORD = 0x0000006F            # jal x0,0  (self-loop) used as program terminator

# probe micro-program: read LED(0x10000000+0), SW(+4), BTN(+8) into x5,x6,x7
PROBE_WORDS = [0x10000137,        # lui  x2, 0x10000
               0x00012283,        # lw   x5, 0(x2)   -> LED readback
               0x00412303,        # lw   x6, 4(x2)   -> SW
               0x00812383,        # lw   x7, 8(x2)   -> BTN
               HALT_WORD]

class SerialLink:
    """Thin pyserial wrapper. All access happens on the worker thread."""
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
# PySide6 GUI
# ---------------------------------------------------------------------------
from PySide6.QtCore import Qt, QObject, QThread, Signal, Slot, QTimer
from PySide6.QtGui import QFont, QColor, QTextCursor
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QPlainTextEdit, QPushButton, QLabel,
    QLineEdit, QComboBox, QHBoxLayout, QVBoxLayout, QGridLayout, QSplitter,
    QTabWidget, QTableWidget, QTableWidgetItem, QGroupBox, QHeaderView,
    QCheckBox, QFrame, QMessageBox, QSpinBox
)

MONO = QFont("Consolas"); MONO.setStyleHint(QFont.Monospace); MONO.setPointSize(10)


class SerialWorker(QObject):
    """Owns the serial link; runs in its own thread. One request at a time."""
    logged       = Signal(str, str)        # (direction '>'/'<'/'*', text)
    connected    = Signal(bool, str)       # (ok, message)
    regsReady    = Signal(object)          # {n: value} -- object, NOT dict: a dict
                                           # with int keys can't be marshalled across
                                           # the worker->GUI thread (Shiboken QVariantMap
                                           # needs str keys) so the table never updated.
    memReady     = Signal(int, int)        # (addr, value)
    periphReady  = Signal(int, int, int, str)  # (led, sw, btn, mode)
    statusReady  = Signal(int)             # status word
    busy         = Signal(bool)
    note         = Signal(str)

    def __init__(self):
        super().__init__()
        self.link = None
        self.periph_direct = None          # None=unknown, True/False after probe
        self.fw_has_lwn = False             # firmware implements L/W/N (≠ bitstream support)

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
        # Does the *firmware* implement L/W/N?  NOTE: a reply is NOT proof that
        # the *bitstream* wires the readback registers — the L/W/N-capable
        # monitor always answers "led=0/sw=0/btn=0", even on an old bitstream
        # whose ctrl-slave lacks 0x38/0x3C/0x40 (those reads just return 0).
        # So we only record firmware capability here and verify the bitstream
        # separately (see _verify_direct), which can never false-positive.
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
            self._tx(f"i {len(words)*4:x} {HALT_WORD:08x}")   # append halt
            if run:
                self._tx("g")
                time.sleep(0.15)                              # let it retire
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
        """Live read via direct registers (cheap). Only used when supported."""
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
        """Fallback: run a tiny MMIO-read program (works on any build).
        NOTE: this overwrites the CPU's instruction memory with the probe."""
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
        """Decide *reliably* whether the running bitstream supports direct
        peripheral readback (ctrl-slave 0x38/0x3C/0x40).  The firmware always
        answers L/W/N, so a reply is not proof.  Cross-check the direct
        registers against the truth read through the CPU's MMIO bus (the same
        probe micro-program used by the fallback).  An old bitstream returns 0
        on the direct regs, so this passes only when the values provably agree
        on a non-zero reading — it can never false-positive.  Leaves the CPU
        reset/clean afterwards."""
        try:
            self.logged.emit("*", "peripheral capability check…")
            # 1) truth via MMIO (works on any bitstream that has the mmio_bridge)
            self.link.cmd("r")
            for i, w in enumerate(PROBE_WORDS):
                self.link.cmd(f"i {i*4:x} {w:08x}")
            self.link.cmd("g"); time.sleep(0.12)
            led_t, sw_t, btn_t = (self._read_reg(5) & 0xF,
                                  self._read_reg(6) & 0xF,
                                  self._read_reg(7) & 0xF)
            # 2) direct ctrl-slave readback
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
            self.link.cmd("r")          # leave CPU reset/clean for the user
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
    def __init__(self, on_color="#37d67a", off_color="#3a3f44", diameter=26):
        super().__init__()
        self.on_color, self.off_color, self.d = on_color, off_color, diameter
        self.setFixedSize(diameter, diameter)
        self.set(False)
    def set(self, on):
        c = self.on_color if on else self.off_color
        self.setStyleSheet(
            f"background:{c}; border-radius:{self.d//2}px; border:1px solid #555;")


class MainWindow(QMainWindow):
    # request signals -> worker slots (queued across threads)
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
        self.resize(1180, 760)
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

    # ---------- UI ----------
    def _build_ui(self):
        # top connection bar
        bar = QHBoxLayout()
        self.port_box = QComboBox(); self.port_box.setEditable(True); self.port_box.setMinimumWidth(150)
        self.baud_box = QComboBox(); self.baud_box.addItems(["115200","9600","19200","57600","230400"])
        self.btn_refresh = QPushButton("Ports"); self.btn_refresh.clicked.connect(self._refresh_ports)
        self.btn_conn = QPushButton("Connect"); self.btn_conn.clicked.connect(self._toggle_conn)
        self.lbl_conn = QLabel("offline"); self.lbl_conn.setStyleSheet("color:#c0392b;")
        bar.addWidget(QLabel("Port:")); bar.addWidget(self.port_box)
        bar.addWidget(self.btn_refresh)
        bar.addWidget(QLabel("Baud:")); bar.addWidget(self.baud_box)
        bar.addWidget(self.btn_conn); bar.addWidget(self.lbl_conn); bar.addStretch(1)

        # left: editor + buttons + machine code
        self.editor = QPlainTextEdit(); self.editor.setFont(MONO)
        self.editor.setPlainText(
            "# type RISC-V assembly, then Run\n"
            "addi x1, x0, 7\n"
            "addi x2, x0, 11\n"
            "add  x3, x1, x2\n")
        btns = QHBoxLayout()
        self.btn_run   = QPushButton("Run ▶")
        self.btn_step  = QPushButton("Step")
        self.btn_reset = QPushButton("Reset")
        self.btn_asm   = QPushButton("Assemble")
        for b in (self.btn_run, self.btn_step, self.btn_reset, self.btn_asm): btns.addWidget(b)
        self.btn_run.clicked.connect(self._run)
        self.btn_step.clicked.connect(lambda: self._guard(self.reqStep.emit))
        self.btn_reset.clicked.connect(lambda: self._guard(self.reqReset.emit))
        self.btn_asm.clicked.connect(self._assemble_preview)
        self.mcode = QPlainTextEdit(); self.mcode.setFont(MONO); self.mcode.setReadOnly(True)
        self.mcode.setFixedHeight(150); self.mcode.setPlaceholderText("machine code…")

        left = QWidget(); lv = QVBoxLayout(left); lv.setContentsMargins(0,0,0,0)
        gb_ed = QGroupBox("Assembly"); ev = QVBoxLayout(gb_ed)
        ev.addWidget(self.editor); ev.addLayout(btns)
        gb_mc = QGroupBox("Machine code"); mv = QVBoxLayout(gb_mc); mv.addWidget(self.mcode)
        lv.addWidget(gb_ed, 3); lv.addWidget(gb_mc, 1)

        # right tabs: registers / memory / peripherals
        self.tabs = QTabWidget()
        self.tabs.addTab(self._build_regs_tab(), "Registers")
        self.tabs.addTab(self._build_mem_tab(),  "Data memory")
        self.tabs.addTab(self._build_periph_tab(), "Peripherals")

        top = QSplitter(Qt.Horizontal); top.addWidget(left); top.addWidget(self.tabs)
        top.setSizes([560, 600])

        # serial log
        gb_log = QGroupBox("Serial log"); lgl = QVBoxLayout(gb_log)
        self.log = QPlainTextEdit(); self.log.setFont(MONO); self.log.setReadOnly(True)
        self.log.setMaximumBlockCount(2000)
        logbtns = QHBoxLayout()
        b_clear = QPushButton("Clear log"); b_clear.clicked.connect(self.log.clear)
        logbtns.addStretch(1); logbtns.addWidget(b_clear)
        lgl.addWidget(self.log); lgl.addLayout(logbtns)

        outer = QSplitter(Qt.Vertical); outer.addWidget(top); outer.addWidget(gb_log)
        outer.setSizes([540, 200])

        central = QWidget(); cv = QVBoxLayout(central)
        cv.addLayout(bar); cv.addWidget(outer)
        self.setCentralWidget(central)
        self.statusBar().showMessage("Ready. Connect to the board, type assembly, press Run.")
        self._set_online(False)

    def _build_regs_tab(self):
        w = QWidget(); v = QVBoxLayout(w)
        self.reg_table = QTableWidget(32, 3)
        self.reg_table.setHorizontalHeaderLabels(["reg", "hex", "dec"])
        self.reg_table.verticalHeader().setVisible(False)
        self.reg_table.setFont(MONO)
        self.reg_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.reg_table.setEditTriggers(QTableWidget.NoEditTriggers)
        abi_names = ['zero','ra','sp','gp','tp','t0','t1','t2','s0','s1','a0','a1','a2','a3',
                     'a4','a5','a6','a7','s2','s3','s4','s5','s6','s7','s8','s9','s10','s11',
                     't3','t4','t5','t6']
        for n in range(32):
            self.reg_table.setItem(n,0,QTableWidgetItem(f"x{n} ({abi_names[n]})"))
            self.reg_table.setItem(n,1,QTableWidgetItem("0x00000000"))
            self.reg_table.setItem(n,2,QTableWidgetItem("0"))
        r = QHBoxLayout()
        b = QPushButton("Refresh registers"); b.clicked.connect(lambda: self._guard(self.reqReadRegs.emit))
        self.chk_signed = QCheckBox("signed dec"); self.chk_signed.stateChanged.connect(self._redraw_regs)
        r.addWidget(b); r.addWidget(self.chk_signed); r.addStretch(1)
        v.addWidget(self.reg_table); v.addLayout(r)
        self._last_regs = dict(self.prev_regs)
        return w

    def _build_mem_tab(self):
        w = QWidget(); v = QVBoxLayout(w)
        row = QHBoxLayout()
        self.mem_addr = QLineEdit("0x00000000"); self.mem_addr.setFont(MONO)
        self.mem_count = QSpinBox(); self.mem_count.setRange(1,64); self.mem_count.setValue(8)
        b = QPushButton("Read"); b.clicked.connect(self._read_mem_range)
        row.addWidget(QLabel("Addr:")); row.addWidget(self.mem_addr)
        row.addWidget(QLabel("Words:")); row.addWidget(self.mem_count)
        row.addWidget(b); row.addStretch(1)
        self.mem_table = QTableWidget(0, 2)
        self.mem_table.setHorizontalHeaderLabels(["address", "word (hex)"])
        self.mem_table.setFont(MONO)
        self.mem_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.mem_table.setEditTriggers(QTableWidget.NoEditTriggers)
        self._mem_rows = {}
        v.addLayout(row); v.addWidget(self.mem_table)
        v.addWidget(QLabel("Reads the data RAM via the PS dump port (MMIO region 0x1xxx_xxxx not included)."))
        return w

    def _build_periph_tab(self):
        w = QWidget(); v = QVBoxLayout(w)
        g = QGridLayout()
        self.led_dots = [LedDot("#ffce3a") for _ in range(4)]   # LEDs (yellow)
        self.sw_dots  = [LedDot("#37d67a") for _ in range(4)]   # switches (green)
        self.btn_dots = [LedDot("#4aa3ff") for _ in range(4)]   # buttons (blue)
        g.addWidget(QLabel("LED  [3..0]"), 0, 0)
        g.addWidget(QLabel("SW   [3..0]"), 1, 0)
        g.addWidget(QLabel("BTN  [3..0]"), 2, 0)
        for i in range(4):                                      # MSB on the left
            g.addWidget(self.led_dots[3-i], 0, i+1)
            g.addWidget(self.sw_dots[3-i],  1, i+1)
            g.addWidget(self.btn_dots[3-i], 2, i+1)
        gb = QGroupBox("Board peripherals"); gv = QVBoxLayout(gb)
        gv.addLayout(g)
        row = QHBoxLayout()
        self.btn_probe = QPushButton("Refresh / Probe")
        self.btn_probe.clicked.connect(self._probe_periph)
        self.chk_autopoll = QCheckBox("auto-poll (live)")
        self.chk_autopoll.stateChanged.connect(self._toggle_poll)
        row.addWidget(self.btn_probe); row.addWidget(self.chk_autopoll); row.addStretch(1)
        gv.addLayout(row)
        self.lbl_periph = QLabel("LED is driven by your program's stores to 0x1000_0000;\n"
                                 "SW/BTN are physical board inputs read at 0x1000_0004 / 0x1000_0008.")
        self.lbl_periph.setStyleSheet("color:#888;")
        v.addWidget(gb); v.addWidget(self.lbl_periph); v.addStretch(1)
        return w

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
            self.lbl_conn.setText("connecting…"); self.lbl_conn.setStyleSheet("color:#e67e22;")
            self.reqConnect.emit(port, int(self.baud_box.currentText()))

    def _assemble_now(self):
        words = assemble(self.editor.toPlainText().splitlines())
        self.mcode.setPlainText("\n".join(f"[{i:2d}] {w:08x}" for i,w in enumerate(words)))
        return words

    def _assemble_preview(self):
        try:
            n = len(self._assemble_now())
            self.statusBar().showMessage(f"assembled {n} instruction(s).", 4000)
        except Exception as e:
            self.mcode.setPlainText(f"; error: {e}")

    def _run(self):
        try:
            words = self._assemble_now()
        except Exception as e:
            QMessageBox.warning(self, "Assembler error", str(e)); return
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
            self.mem_table.setItem(i,0,QTableWidgetItem(f"0x{a:08x}"))
            self.mem_table.setItem(i,1,QTableWidgetItem("…"))
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

    # ---------- worker callbacks ----------
    @Slot(str, str)
    def _on_log(self, d, text):
        self.log.appendPlainText(f"{d} {text}")
        self.log.moveCursor(QTextCursor.End)

    @Slot(bool, str)
    def _on_connected(self, ok, msg):
        self.connected = ok
        self._set_online(ok)
        if ok:
            self.lbl_conn.setText(msg); self.lbl_conn.setStyleSheet("color:#27ae60;")
            self.periph_mode = "direct" if "direct" in msg else "probe"
            self.btn_probe.setText("Refresh (live)" if self.periph_mode=="direct" else "Probe (micro-program)")
            self.reqReadRegs.emit()
        else:
            self.lbl_conn.setText(msg if msg else "offline"); self.lbl_conn.setStyleSheet("color:#c0392b;")
            self.poll_timer.stop()

    @Slot(dict)
    def _on_regs(self, regs):
        self._last_regs = dict(self.prev_regs)
        self.prev_regs = {n: regs.get(n, 0) for n in range(32)}
        self._redraw_regs()

    def _redraw_regs(self):
        signed = self.chk_signed.isChecked()
        for n in range(32):
            v = self.prev_regs.get(n, 0)
            self.reg_table.item(n,1).setText(f"0x{v:08x}")
            dec = v - (1<<32) if (signed and v & 0x80000000) else v
            self.reg_table.item(n,2).setText(str(dec))
            changed = self._last_regs.get(n,0) != v
            color = QColor("#fff3b0") if changed else QColor(Qt.white)
            for c in range(3):
                self.reg_table.item(n,c).setBackground(color)
                self.reg_table.item(n,c).setForeground(QColor("#111"))

    @Slot(int, int)
    def _on_mem(self, addr, val):
        i = self._mem_rows.get(addr)
        if i is not None:
            self.mem_table.setItem(i,1,QTableWidgetItem(f"0x{val:08x}"))

    @Slot(int, int, int, str)
    def _on_periph(self, led, sw, btn, mode):
        for i in range(4): self.led_dots[i].set(bool((led>>i)&1))
        for i in range(4): self.sw_dots[i].set(bool((sw>>i)&1))
        for i in range(4): self.btn_dots[i].set(bool((btn>>i)&1))
        self.statusBar().showMessage(
            f"peripherals ({mode}): LED={led:#06b} SW={sw:#06b} BTN={btn:#06b}".replace("0b",""), 4000)

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

    def closeEvent(self, e):
        try:
            self.poll_timer.stop()
            self.reqDisconnect.emit()
            self.thread.quit(); self.thread.wait(800)
        except Exception:
            pass
        super().closeEvent(e)


def main():
    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    win = MainWindow()
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
