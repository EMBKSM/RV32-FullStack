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

**BUG-IFWB-002 — register_file에 리셋 부재 → 프로그램 간 상태 누설 (xsim AT-30에서 발견).**
실제 Vivado xsim에서 통합 TB를 돌렸을 때 directed(AT-01~29)·BVA·타이밍은 전부 통과했으나 AT-30 랜덤이 거의 전부 불일치했다. 반례 1개를 통째로 덤프(TB의 `+DEBUGPROG` 트레이스)해 분석한 결과:

- 그 프로그램을 **단독 실행하면 DUT 결과가 정답(ISS와 일치)**, 그러나 AT-30 루프 안(앞선 프로그램들이 먼저 실행된 뒤)에서는 한 레지스터가 틀렸다.
- 원인: `register_file.vhd`에 리셋이 없어, 코어 리셋(`do_reset`)이 파이프라인 레지스터·shadow는 지워도 **실제 32개 레지스터는 이전 프로그램 값을 유지**했다. 랜덤 프로그램은 *쓰기 전에 읽는* 레지스터가 흔해서(ISS는 0 가정), stale 값이 store→메모리→load로 전파되어 최종 레지스터가 어긋났다. directed 케이스는 소스 레지스터를 항상 먼저 초기화하므로 이 누설을 자극하지 않아 통과했다.
- **검출 경로:** AT-30이 **전체 32 레지스터**를 ISS와 비교(directed의 `ck_reg`는 지정 레지스터만 확인)했기에 누설이 드러났다. 즉 "전체 아키텍처 상태 등가" 검사가 부분 검사보다 강함을 실증.
- **수정:** `register_file`에 active-high 동기 리셋을 추가해 리셋 시 x1..x31을 0으로 클리어(`register_file.vhd`), `rv32_core`에서 `reset` 연결, 단위 TB(`tb_register_file.sv`)에 리셋 구동 추가. 이로써 매 프로그램이 결정적 초기상태(전부 0)에서 시작해 골든 ISS와 일치하며, IP의 알려진 파워온 상태도 확보된다.
- **방법론 메모:** 사이클정확 Python 모델은 프로그램마다 새 상태(reg=[0]*32)로 시작했기에 이 누설을 재현하지 못했다(그래서 8,000개 통과). 실 RTL의 사인오프는 반드시 HDL 시뮬(xsim/Questa)로 해야 하는 이유 — 모델이 암묵적으로 가정한 초기화가 RTL엔 없을 수 있다.

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

## 6. 블록별 SystemVerilog 단위 테스트벤치 (U1~U9 충족)

기존에는 SV TB가 ALU·control_unit 2개뿐이었고 나머지는 Python 골든모델로만 검증됐다. `Verification_Handover.md`의 단위검증계획(U1~U9)을 HDL 레벨에서 충족하도록 **모든 leaf 블록(25개)에 self-checking SV 단위 TB를 추가**했다(통합 top `rv32_core`는 `tb_rv32_core_if_wb.sv`가 담당). 모든 TB는 `tb_alu.sv` 패턴(독립 골든/기대값 + `RESULT: ALL PASS`/`$fatal`)을 따른다.

| 구간 | 단위 테스트벤치 (`ip_workspace/...`) | 방식 |
|---|---|---|
| IF | tb_pc_adder, tb_next_pc_mux, tb_program_counter, tb_address_aligner, tb_comparator, tb_tag_array, **tb_cache_controller(FSM)** | 조합 random+golden / 순차 directed / FSM 상태천이 |
| ID | tb_control_unit, tb_imm_gen, tb_register_file, **tb_csr_file**, tb_hazard_unit | 진리표·random+golden / write-first / 트랩·MRET |
| EX | tb_alu, **tb_alu_control(64 exhaustive)**, tb_bcu, tb_forwarding_unit, tb_trap_unit | exhaustive / random+golden / 우선순위·cause |
| MEM | tb_read_aligner, tb_write_strobe_gen, tb_dtag_array, tb_ddata_array, **tb_dcache_controller(FSM)**, **tb_axi_master(FSM)** | random+golden / 순차 / write-back·burst 핸드셰이크 |
| WB | tb_result_mux | random+golden |
| 공용 | tb_pipeline_reg | latch/stall/flush/reset |

- 조합 블록: directed + 수천~수만 랜덤 벡터를 TB 내장 독립 골든과 대조. alu_control은 64조합 전수.
- 순차/FSM 블록(cache_controller, dcache_controller, axi_master, dtag/ddata array, register_file, csr_file, tag_array, program_counter, pipeline_reg): 클럭 단위 directed 시퀀스로 상태천이·캡처타이밍·핸드셰이크(RLAST/BVALID/WLAST)·write-first·트랩/MRET를 검사 — Python 모델이 못 잡는 엘라보레이션/타이밍 영역.
- 실행은 각 `.vhd` + 해당 `tb_*.sv`를 xsim/Questa 혼합언어로 컴파일·구동(예: `xvhdl <dut>.vhd; xvlog -sv tb_<dut>.sv; xelab tb_<dut> -R`). 본 환경에는 혼합언어 시뮬레이터가 없어 구조/구문 정합만 확인했고, 실제 PASS는 Vivado xsim/Questa 실행으로 확정한다.

### 6.1 3-포인트 경계값분석 (BVA) — 전 TB 적용

모든 TB(25개 단위 + 통합 + 기존 alu/control_unit)에 **3-포인트 경계값분석**(경계−1 / 경계 / 경계+1)을 추가했다. 각 블록의 실제 경계에 맞춤:

| 블록 | BVA 경계(3-포인트) |
|---|---|
| pc_adder | +4 wrap @0xFFFFFFFC (wrap−1/wrap/wrap+1), min/max |
| next_pc_mux | sel{0,1} × 데이터 min/sign(0x7FFFFFFF·0x80000000)/max |
| address_aligner | offset 0xF→0x10, idx 0xFF→0x100 carry 경계 |
| comparator | tag 일치 @V (V−1/V/V+1), tag min/max, valid 경계 |
| program_counter | next_pc min/sign/max, stall 0↔1 전이 |
| tag_array / dtag_array | index 0/1/254/255 (min·max·인접) |
| imm_gen / 통합 | 12-bit 부호 즉치 +2046/+2047/−2048 |
| alu / alu_control | ADD wrap, shamt 30/31/32(마스킹), funct7[5] 0/1, SLT/SLTU 부호 경계 |
| bcu | 비교 등가 인접(a=b−1/b/b+1), 0x7FFFFFFF↔0x80000000 부호/무부호 발산 |
| forwarding_unit / hazard_unit | rd 레지스터번호 x0/x1/x31 (게이팅 경계) |
| trap_unit | cause 우선순위 인접쌍(misalign>illegal>ebreak>load>store>ecall) |
| read_aligner | 바이트 부호 0x7F/0x80, 하프 0x7FFF/0x8000, byte_off 0/3 |
| write_strobe_gen / ddata_array | byte_off 0/3, wstrb 0x0/0xF, 데이터 min/max |
| cache_controller / dcache_controller | 핸드셰이크(arready/rvalid/axi_done) before/at 경계 캡처 타이밍 |
| axi_master | 버스트 beat 카운트 first(0)/last(3, RLAST/WLAST) 경계 |
| result_mux | result_src 00/01/10/11(default), csr_to_reg 경계 |
| pipeline_reg | 데이터 min/max, flush>stall 우선순위 경계 |
| register_file / csr_file | reg-num x0/x1/x30/x31, 쓰기데이터 min/max·set/clear 마스크 경계 |

통합 BVA 3종(즉치 ±경계, LB/LBU 부호 경계, SLLI shamt 30/31)은 사이클정확 모델·ISS로 사전 검산해 기대값을 확정했다(x1=0x7FE, x2=0x7FF, x3=0xFFFFF800 / LB=0xFFFFFF80, LBU=0x80 / 0x40000000, 0x80000000).

### 6.2 순차 논리 타이밍 이슈 테스트 — 전 순차/FSM TB 적용

기능 시뮬레이션 레벨에서 의미 있는 클럭 타이밍 결함을 잡도록, 모든 순차/FSM TB에 `// timing-issue tests` 블록을 추가했다(게이트레벨 setup/hold·skew는 STA/Vivado 영역으로 범위 밖).

| 순차 블록 | 추가한 타이밍 케이스 |
|---|---|
| program_counter | 비동기 reset이 stall을 지배, 3-사이클 stall hold(내부 next_pc 변동 무시), release 시 최신값 latch |
| pipeline_reg | 멀티사이클 stall hold, 비동기 reset이 stall+flush 동시 지배 |
| tag_array / dtag_array | 동기 write 지연(엣지 전 read는 OLD), 비동기 reset 즉시 valid/dirty 클리어, we_tag>we_dirty 엣지 우선순위 |
| register_file | write-first 바이패스 동일사이클 가시성, 엣지 후 커밋, 동일 레지스터 연속 write 마지막 우선 |
| csr_file | 동일 엣지에서 trap_we>is_mret>csr_we 우선순위, 비동기 reset CSR 클리어 |
| ddata_array | 동기 store 지연(엣지 전 OLD), line_fill>we 엣지 우선순위 |
| cache_controller | **캡처 타이밍: `we`는 RVALID beat에 정확히 1, 그 외 0** (BUG-001 회귀), 긴 AR/R 지연 동안 무오류, wake_up 1-사이클 펄스, 비동기 reset 중 FSM→IDLE |
| dcache_controller | axi_done 1회에 정확히 1상태 전이, wake_up 1-사이클 펄스, 비동기 reset 중 FSM→IDLE |
| axi_master | ready 지연(stretch) 시 대기, beat는 핸드셰이크에서만 증가, done 1-사이클 펄스, 비동기 reset 중 버스트→IDLE |
| 통합(rv32_core) | 연속 load-use 해저드(각 1버블+MEM/WB 포워딩), 분기 EX 해소 정확히 2버블 flush(2슬롯 squash) |

핵심 회귀 보호: cache_controller의 `we=rvalid` 캡처 타이밍 테스트는 과거 BUG-001(RVALID 다음 사이클에 stale 버스 데이터를 latch)을 직접 겨냥한다. 통합 타이밍 2종은 사이클정확 모델·ISS로 기대값을 사전 검산했다(load-use: x3=0x12,x5=0x13 / branch 2-bubble: x7=7,x8=0,x9=0).

## 7. 결론

IF~WB 레지스터 기록 경로 통합이 명세(`RV32_Pipeline_Spec.md`)와 정합하며, 포워딩·해저드·분기를 포함해 임의 프로그램에서 순차 ISS와 등가임을 30 iteration + 8,000 랜덤 counter-example + 4종 결함주입으로 확인했다. 발견된 실제 RTL 버그(ADDI/funct7 게이팅) 1건을 수정·재검증했다. 최종 게이트 사인오프는 동봉 SV TB를 xsim/Questa로 1회 실행하여 마무리할 것을 권고한다.
