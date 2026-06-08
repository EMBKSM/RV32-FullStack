#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
RV32-FullStack — RV32_Pipeline_Spec.md 문서 검증 (10 iterations).

5단계 파이프라인(IF·ID·EX·MEM·WB) 명세를 기계적으로 재검증한다:
표 무결성, 주소 산술, RV32I funct3(로드+분기), AXI4 상수, 신호 폭,
컴포넌트/opcode/즉치 커버리지, 리셋 관례/포트, 통과표 일관성, 상호참조/오타.

Usage:  python3 verification/verify_spec.py    (exit 0 = all green)
"""
import os
import re
import sys
import math

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(ROOT, "RV32_Pipeline_Spec.md")
TEXT = open(SPEC, encoding="utf-8").read()
LINES = TEXT.splitlines()
DASH = "—"


class Check:
    def __init__(self, name):
        self.name, self.n, self.fails, self.notes = name, 0, [], []

    def ok(self, cond, msg):
        self.n += 1
        if not cond:
            self.fails.append(msg)

    def note(self, msg):
        self.notes.append(msg)

    @property
    def passed(self):
        return not self.fails


def split_cells(row):
    s = row.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|"):
        s = s[:-1]
    return s.split("|")


def iter_tables():
    in_code = False
    block, start = [], None
    for i, ln in enumerate(LINES, 1):
        if ln.strip().startswith("```"):
            in_code = not in_code
            continue
        if in_code:
            continue
        if ln.lstrip().startswith("|"):
            if not block:
                start = i
            block.append((i, ln))
        else:
            if block:
                yield start, block
            block = []
    if block:
        yield start, block


def gsection(title):
    """Slice from a heading line until the next heading of any level (## ~ ####)."""
    idx = TEXT.find(title)
    if idx < 0:
        return ""
    after = idx + len(title)
    m = re.search(r"\n#{2,4} ", TEXT[after:])
    end = after + m.start() if m else len(TEXT)
    return TEXT[idx:end]


def iter01_table_integrity():
    c = Check("Iter 01 · 마크다운 표 무결성")
    ntables = 0
    for start, block in iter_tables():
        rows = [(i, r) for i, r in block if not re.match(r"\s*\|[\s:|-]+\|?\s*$", r)]
        if not rows:
            continue
        ntables += 1
        h = len(split_cells(rows[0][1]))
        for i, r in rows:
            c.ok(len(split_cells(r)) == h,
                 f"line {i}: 열 수 {len(split_cells(r))} != 헤더 {h}  ->  {r.strip()[:60]}")
    c.note(f"검사한 표 개수: {ntables}")
    return c


def iter02_addr_arithmetic():
    c = Check("Iter 02 · 캐시 주소 필드 산술")
    cache, line, nlines, tag, index, offset = 4096, 16, 256, 20, 8, 4
    c.ok(cache // line == nlines, "CACHE_SIZE/LINE_BYTES != NUM_LINES")
    c.ok(index == int(math.log2(nlines)), "INDEX != log2(NUM_LINES)")
    c.ok(offset == int(math.log2(line)), "OFFSET != log2(LINE_BYTES)")
    c.ok(tag + index + offset == 32, "TAG+INDEX+OFFSET != 32")
    for kv in ["`CACHE_SIZE` | 4 KB", "`LINE_BYTES` | 16", "`NUM_LINES` | 256",
               "`TAG_WIDTH` | 20", "`INDEX_WIDTH` | 8", "`OFFSET_WIDTH` | 4"]:
        c.ok(kv in TEXT, f"파라미터 표 '{kv}' 누락")
    for bits in ["[31:12]", "[11:4]", "[3:2]", "[1:0]"]:
        c.ok(bits in TEXT, f"주소 분해도 {bits} 누락")
    return c


def iter03_funct3():
    c = Check("Iter 03 · RV32I funct3 (로드 + 분기)")
    loads = {"000": "LB", "001": "LH", "010": "LW", "100": "LBU", "101": "LHU"}
    for code, mn in loads.items():
        c.ok(re.search(rf"`{code}`\s*\|\s*{mn}\b", TEXT), f"로드 funct3 {code}->{mn} 불일치")
    branches = {"000": "BEQ", "001": "BNE", "100": "BLT",
                "101": "BGE", "110": "BLTU", "111": "BGEU"}
    for code, mn in branches.items():
        c.ok(re.search(rf"`{code}`\s*\|\s*{mn}\b", TEXT), f"분기 funct3 {code}->{mn} 불일치")
    return c


def iter04_axi_constants():
    c = Check("Iter 04 · AXI4 프로토콜 상수")
    c.ok("`01`=INCR" in TEXT, "INCR=01 누락")
    c.ok("`010`" in TEXT, "AxSIZE 010 누락")
    c.ok(re.search(r"4워드\s*-\s*1\s*=\s*3", TEXT) or "= 3, 즉 4-beat" in TEXT, "AxLEN=3 누락")
    c.ok("`00`=OKAY" in TEXT, "RESP OKAY=00 누락")
    c.ok("`wstrb` | In | 4" in TEXT or re.search(r"WSTRB`?\s*\|\s*Out\s*\|\s*4", TEXT),
         "WSTRB 폭 4 누락")
    c.ok("`00`=INCR" not in TEXT and "`10`=INCR" not in TEXT, "INCR 코드 오표기")
    return c


def iter05_width_consistency():
    c = Check("Iter 05 · 신호 비트폭 일관성")
    pats = {
        "Tag 20-bit": r"tag.*?\|\s*(?:In|Out)\s*\|\s*20",
        "Index 8-bit": r"(?:index|idx).*?\|\s*(?:In|Out)\s*\|\s*8",
        "rd 5-bit": r"rd_[io]`?\s*\|\s*(?:In|Out)\s*\|\s*5",
        "funct3 3-bit": r"funct3.*?\|\s*(?:In|Out)\s*\|\s*3",
        "cache line 128-bit": r"\|\s*Out\s*\|\s*128",
        "opcode 7-bit": r"opcode`?\s*\|\s*In\s*\|\s*7",
        "ALU ctrl 4-bit": r"alu_ctrl`?\s*\|\s*In\s*\|\s*4",
    }
    for desc, pat in pats.items():
        c.ok(re.search(pat, TEXT), f"{desc} 누락/불일치")
    return c


def iter06_coverage():
    c = Check("Iter 06 · 컴포넌트 / opcode / 즉치 커버리지")
    comps = ["IF (Instruction Fetch)", "ID (Instruction Decode)", "EX (Execute)",
             "PC Register", "PC Adder", "Next-PC MUX", "Address Aligner", "Tag Array",
             "Comparator", "Cache Controller", "Control Unit", "Register File",
             "Immediate Generator", "ALU Control", "BCU", "Forwarding Unit", "Hazard Unit", "CSR File", "Trap & Exception Unit", "MemtoReg MUX",
             "IF/ID 파이프라인", "ID/EX 파이프라인", "EX/MEM 파이프라인",
             "MEM/WB 파이프라인", "Read MUX / Aligner", "AR Master", "AW Master"]
    for x in comps:
        c.ok(x in TEXT, f"컴포넌트 섹션 누락: {x}")
    for op in ["0110011", "0010011", "0000011", "0100011", "1100011",
               "1101111", "1100111", "0110111", "0010111", "1110011", "0001111"]:
        c.ok(f"`{op}`" in TEXT, f"opcode {op} 누락")
    for slc in ["instr[31:20]", "instr[19:12]", "instr[11:8]"]:  # I, J, B 특징 비트
        c.ok(slc in TEXT, f"즉치 비트 {slc} 누락")
    return c


def iter07_reset_convention():
    c = Check("Iter 07 · 리셋 극성 관례 (active-high `reset`)")
    c.ok("rst_n" not in TEXT, "`rst_n` 잔존")
    c.ok("active-low" not in TEXT, "'active-low' 잔존")
    c.ok("active-high" in TEXT and "reset" in TEXT, "active-high `reset` 표기 누락")
    return c


def sec_level(title):
    """Slice from a heading until the next heading of the same or higher level."""
    idx = TEXT.find(title)
    if idx < 0:
        return ""
    after = idx + len(title)
    lvl = len(title) - len(title.lstrip("#"))
    best = len(TEXT)
    for L in range(2, lvl + 1):
        m = re.search(r"\n#{%d} " % L, TEXT[after:])
        if m:
            best = min(best, after + m.start())
    return TEXT[idx:best]


def iter08_reset_ports():
    c = Check("Iter 08 · 상태 보유 블록 reset 포트")
    titles = ["## 3. IF/ID", "## 5. ID/EX", "## 7. EX/MEM", "## 9. MEM/WB",
              "### 2.1 PC Register", "#### 2.4.2 Tag Array", "#### 2.4.4 Cache Controller"]
    for t in titles:
        body = sec_level(t)
        c.ok(("reset" in body) or ("rst" in body), f"{t} 포트에 reset 누락")
    return c


def iter09_passthrough_table():
    c = Check("Iter 09 · 통과(Pass-through) 표 일관성 (§12.1, 5열)")
    seg = gsection("### 12.1")
    table = {}
    for line in seg.splitlines():
        m = re.match(r"\s*\|\s*`([^`]+)`\s*\|(.+)\|\s*$", line)
        if m:
            cells = [x.strip() for x in m.group(2).split("|")]
            if len(cells) == 5:               # IF, ID, EX, MEM, WB
                table[m.group(1)] = cells
    c.ok("instr" in table and table["instr"][2] == DASH and table["instr"][3] == DASH
         and table["instr"][4] == DASH, "instr 는 EX/MEM/WB 로 전달되면 안 됨")
    c.ok("ALU Result" in table and table["ALU Result"][0] == DASH
         and table["ALU Result"][1] == DASH, "ALU Result 는 IF/ID 에 없어야 함")
    c.ok("Read Data" in table and table["Read Data"][0] == DASH
         and table["Read Data"][1] == DASH and table["Read Data"][2] == DASH,
         "Read Data 는 IF/ID/EX 에 없어야 함 (MEM 생성)")
    c.note(f"§12.1 행 파싱: {len(table)}개 신호")
    return c


def iter10_xref_typo():
    c = Check("Iter 10 · 상호참조 & 오타 스캔")
    c.ok("Reasult" not in TEXT, "오타 'Reasult' 잔존")
    c.ok("WriteData = MemtoReg ? ReadData : ALU_Result" in TEXT, "MemtoReg MUX 식 누락")
    c.ok("MemtoReg=1일 때 선택" in TEXT, "MemtoReg=1->메모리 설명 불일치")
    c.ok("mem_read|mem_write" not in TEXT, "표 셀 내 미이스케이프 파이프 잔존")
    # 단계 번호 연속성: ## 1 ~ ## 13 모두 존재
    for n in range(1, 14):
        c.ok(re.search(rf"(?m)^## {n}\. ", TEXT), f"## {n}. 섹션 누락")
    return c


def main():
    iters = [iter01_table_integrity, iter02_addr_arithmetic, iter03_funct3,
             iter04_axi_constants, iter05_width_consistency, iter06_coverage,
             iter07_reset_convention, iter08_reset_ports, iter09_passthrough_table,
             iter10_xref_typo]
    print("=" * 70)
    print("RV32_Pipeline_Spec.md — 문서 검증 (10 iterations)")
    print("=" * 70)
    npass = total = 0
    for fn in iters:
        r = fn()
        total += r.n
        npass += 1 if r.passed else 0
        print(f"[{'PASS' if r.passed else 'FAIL'}] {r.name}  ({r.n} checks)")
        for nt in r.notes:
            print(f"         · {nt}")
        for f in r.fails[:10]:
            print(f"         X {f}")
    print("-" * 70)
    print(f"통과: {npass}/{len(iters)} 반복,  총 점검 {total}건")
    print("결과:", "ALL GREEN" if npass == len(iters) else "FAILURES PRESENT")
    print("=" * 70)
    return 0 if npass == len(iters) else 1


if __name__ == "__main__":
    sys.exit(main())
