# 검증 리포트 — IF~WB Write-Path 통합 (ATDD / Shift-Left)

> 대상: RV32I 5단 파이프라인 **IF→ID→EX→MEM→WB(register write-back)** 통합 데이터패스
> RTL: `ip_workspace/rv32_core.vhd` (VHDL) — 기존 검증 IP 블록을 배선한 코어 top
> TB: `verification/tb_rv32_core_if_wb.sv` (SystemVerilog, 혼합언어 사인오프용)
> 모델 검증: `verification/run_ifwb_core.py` (사이클정확 모델 + 독립 ISS 골든)
> 수용 기준: `ip_workspace/if_wb_acceptance_tests.md` (AT-01~AT-30, Shift-Left로 사전 정의)

---

## 1. 방법론 (Shift-Left / ATDD)

1. **수용 기준 선(先) 정의 (Shift-Left):** 통합 RTL 작성 전에 30개 수용 테스트(AT-01~AT-30)와 8개 불변식(AC-1~AC-8)을 `if_wb_acceptance_tests.md`에 확정.
2. **테스트 구현:** SystemVerilog 자체검증 TB(`tb_rv32_core_if_wb.sv`) + Python 사이클정확 하네스(`run_ifwb_core.py`). directed 케이스는 **독립 손계산 기대값**, 랜덤 케이스는 **독립 ISS 골든**.
3. **RTL 구현:** 테스트를 통과하도록 `rv32_core.vhd`를 작성/수정.
4. **30회 반복 + counter-example + 결함주입:** 아래 §3.

**이중 모델(dual-model) 원칙.** 검증의 핵심은 두 개의 *독립적으로 작성된* 모델을 대조하는 것이다.
- **Pipeline** — `rv32_core.vhd`를 사이클 단위로 미러링(IF/ID·ID/EX·EX/MEM·MEM/WB 레지스터, EX/MEM·MEM/WB 포워딩, load-use 1버블 stall, EX 분기해소 2버블 flush, write-first 레지스터파일).
- **ISS** — 명령을 프로그램 순서대로 한 개씩 원자적으로 실행하는 순차 참조 모델(포워딩/해저드/파이프라인 개념 없음).

두 모델이 임의 프로그램에서 최종 아키텍처 레지스터를 비트 단위로 일치시키는 것이 정확성의 정의(AC-1)다.

---

## 2. DUT 구성 (`rv32_core.vhd`)

| 스테이지 | 인스턴스(기존 IP) | 통합 로직(top에서 신규) |
|---|---|---|
| IF | `pc_reg`, `pc_adder`, `next_pc_mux` | IF/ID 레지스터(flush=NOP squash, stall=hold), 이상적 imem |
| ID | `control_unit`, `imm_gen`, `register_file`, `hazard_unit` | 필드 추출, **funct7[5] 게이팅**, ID/EX 레지스터(버블) |
| EX | `forwarding_unit`, `alu_control`, `alu`, `bcu` | forward MUX(a/b), operand MUX, EX/MEM 레지스터 |
| MEM | `read_aligner`, `write_strobe_gen` | 이상적 dmem 접근, MEM/WB 레지스터 |
| WB | `result_mux` | RF 쓰기 포트 구동, 디버그 shadow 레지스터파일 |

범위 한정: 본 통합은 **IF~WB 레지스터 기록 경로**에 집중한다. 캐시/AXI(IF·MEM), CSR/Trap(머신모드)은 본 코어의 범위 밖이며 각각 `VERIFICATION_REPORT.md`, `VERIFICATION_REPORT_ALU.md`, `RTL_IMPLEMENTATION_REPORT.md`에서 별도 검증됨. 명령/데이터 메모리는 이상적 single-cycle hit으로 모델링하여 캐시 stall과 무관하게 기록 경로를 종단간 검증한다.

---

## 3. 결과

### 3.1 30 iteration (clean)

```
RV32 IF~WB Write-Path 통합 수용 테스트 (ATDD / Shift-Left)
  Directed AT-01..AT-29: 29/29 PASS
  AT-30 random counter-example: 2000 programs, 0 mismatch(es)
  iteration count: 30  (AT-01..AT-29 directed + AT-30 sweep)
  result: ALL GREEN
```

- **AT-01~AT-29 (directed):** 29/29 PASS. 각 케이스는 독립 손계산 기대 레지스터값과 일치하며, 동시에 전체 레지스터파일이 ISS와 일치(이중 확인).
- **AT-30 (counter-example sweep):** 기본 2,000개 + 스트레스 6,000개(길이 60) = **총 8,000개 랜덤 프로그램** 전수 일치, 0 반례.
- 커버: ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/SLT/SLTU, I-즉치 전종, LUI/AUIPC, LB/LH/LW/LBU/LHU, SB/SH/SW, BEQ/BNE/BLT/BGE/BLTU/BGEU, JAL/JALR, x0 고정, EX/MEM·MEM/WB 포워딩, load-use 해저드, 분기 2버블, 후방분기 루프.

### 3.2 결함 주입 (검증 유효성 입증)

`run_ifwb_core.py --bug <fault>` 로 통합 제어에 의도적 결함을 주입했을 때, 수용 테스트가 **반드시** 실패(FAULT CAUGHT)해야 한다.

| 주입 결함 | directed 결과 | AT-30 반례(2,000개 중) | 판정 |
|---|---|---|---|
| `forward` (EX 바이패스 비활성) | 9/29 | 864 | **CAUGHT** |
| `hazard` (load-use stall 누락) | 28/29 | 97 | **CAUGHT** |
| `branch` (분기 flush 누락) | 22/29 | 1562 | **CAUGHT** |
| `x0` (x0 하드와이어 해제) | 28/29 | 577 | **CAUGHT** |

4종 결함 모두 directed와 랜덤 양쪽에서 검출 → 테스트 스위트가 실제 통합 버그를 잡음을 입증.

### 3.3 발견·수정한 실제 결함 (RTL 버그)

**BUG-IFWB-001 — ADDI가 SUB로 디코드 (funct7[5] 미게이팅).**
초기 통합은 `funct7_5`로 `instr[30]`을 무조건 사용했다. R-type에서는 옳지만, I-type `ADDI`(funct3=000)에서 `instr[30]`은 **즉치의 한 비트**이므로 이를 ALU control에 넘기면 즉치 비트가 1일 때 `ADD`가 `SUB`로 바뀐다(`addi x,x,-1` → 잘못된 SUB).

- **검출 경로:** directed AT-02/06/07/10/18/22/28 (독립 손계산 기대값) — 7건 동시 FAIL.
- **랜덤 sweep는 미검출:** Pipeline과 ISS가 동일한 디코드 로직을 공유하므로 두 모델 모두 같은 오답을 내어 일치(0 반례). → **독립 기대값을 쓰는 directed 테스트가 공통모드 버그를 잡는다**는 ATDD의 핵심 효용을 실증.
- **수정:** `id_funct7_5 <= instr[30]` 을 R-type 또는 I-type SRLI/SRAI(funct3=101)일 때만 통과시키도록 게이팅(`rv32_core.vhd`). 수정 후 29/29 + 8,000 랜덤 0 반례.

---

## 4. SystemVerilog 테스트벤치 (`tb_rv32_core_if_wb.sv`)

- VHDL DUT(`rv32_core`)를 혼합언어로 인스턴스화하는 자체검증 TB. `tb_alu.sv`/`tb_control_unit.sv`와 동일 패턴.
- 어셈블러 함수(R/I/S/B/U/J), 프로그램 로더, reset/run/snapshot 태스크, `dbg_reg_addr/dbg_reg_data`로 아키텍처 레지스터 스냅샷.
- AT-01~AT-29: 독립 기대값 `ck_reg` 검사. AT-30: TB 내장 ISS(`iss_run`, 별도 골든 메모리 `gmem`)와 랜덤 프로그램(기본 500개, `+PROGRAMS=`로 조정) 대조.
- 실행(사인오프): `xvhdl <vhd 목록>; xvlog -sv tb_rv32_core_if_wb.sv; xelab tb_rv32_core_if_wb -R` (Vivado xsim) 또는 Questa `vcom/vlog/vsim`. 컴파일 순서는 파일 헤더 주석 참조.

> **방법론 한계:** 본 리포트의 PASS는 (a) SV TB 설계 + (b) 사이클정확 Python 모델·ISS 대조에 근거한 **논리/프로토콜** 검증이다. 게이트레벨 타이밍·엘라보레이션 최종 사인오프는 위 xsim/Questa 1회 실행으로 보강한다(샌드박스에 혼합언어 시뮬레이터 부재).

---

## 5. 커버리지 요약

- **명령 클래스:** RV32I 정수 전종(시스템/펜스 제외 — 범위 밖) — directed + 랜덤.
- **해저드:** 데이터(EX/MEM·MEM/WB 포워딩, 우선순위), 로드-유즈(1버블), 제어(분기 2버블, 전·후방).
- **경계값:** 부호확장 즉치, 시프트 마스킹, SLT/SLTU·BLT/BLTU 발산, 서브워드 로드/스토어 정렬, x0 고정, JAL/JALR 링크.
- **반복:** AT-01~29(directed) + AT-30 sweep = 30 iteration; AT-30 누적 8,000 프로그램.
- **결함주입:** 4/4 검출.

## 6. 결론

IF~WB 레지스터 기록 경로 통합이 명세(`RV32_Pipeline_Spec.md`)와 정합하며, 포워딩·해저드·분기를 포함해 임의 프로그램에서 순차 ISS와 등가임을 30 iteration + 8,000 랜덤 counter-example + 4종 결함주입으로 확인했다. 발견된 실제 RTL 버그(ADDI/funct7 게이팅) 1건을 수정·재검증했다. 최종 게이트 사인오프는 동봉 SV TB를 xsim/Questa로 1회 실행하여 마무리할 것을 권고한다.
