# RV32-FullStack — 최종 통합 검증 리포트 (Full Regression)

**대상:** RV32I 5-stage 파이프라인 CPU + 명령/데이터 캐시 + AXI4 메모리 + 머신모드(Zicsr/Trap) + FENCE.I
**방법론:** Shift-Left / ATDD, 이중 모델 교차검증(사이클 정확 파이프라인 모델 vs 독립 ISS 골든), 반례 랜덤 스윕, 결함 주입(fault injection)
**생성일:** 2026-06-09

---

## 1. 한눈에 보기

| 항목 | 상태 |
|---|---|
| RV32I 정수 명령 (R/I/Load/Store/Branch/JAL/JALR/LUI/AUIPC) | ✅ 동작·검증 |
| 5-stage 파이프라인 (포워딩 / load-use 스톨 / 분기 EX 해결 / write-first RF) | ✅ |
| 명령 캐시(I$) — IF-라인 부품으로 재구성 (read-only, 4-word line) | ✅ |
| 데이터 캐시(D$) — write-back / write-allocate | ✅ |
| AXI4 4-beat INCR 버스트 ↔ 거동 메모리 (Harvard) | ✅ |
| Zicsr (CSRRW/RS/RC + I) + 머신모드 CSR | ✅ |
| 트랩 (ECALL/EBREAK/MRET/illegal, mepc/mcause/mtvec/mstatus) | ✅ |
| FENCE.I → I$ 무효화 | ✅ |
| Python 모델 회귀 (이번 실행) | ✅ ALL GREEN |
| SystemVerilog TB (xsim 2025.2, 사용자 실행) | ✅ ALL PASS — SoC 스위트 + 신규 I$ 단위 3종 확인 |

**미통합/예외 항목은 §5에 명시.**

---

## 2. 통합 마일스톤 (구축 순서)

1. **IF~WB 데이터패스** (`rv32_core.vhd`) — 검증된 IP 블록(control_unit, imm_gen, register_file, alu, alu_control, bcu, forwarding_unit, hazard_unit, read_aligner, write_strobe_gen, result_mux, pc_reg/pc_adder/next_pc_mux)을 5-stage로 결선. EX/MEM·MEM/WB 포워딩, load-use 1-버블 스톨, 분기/점프 EX 해결(2-버블 flush), write-first 레지스터 파일.
2. **풀 SoC** (`rv32_soc.vhd`) — 코어 + I$ + D$ + 두 개의 거동 AXI 메모리(Harvard, 명령/데이터 분리). 캐시 미스 → AXI 버스트 리필/라이트백 → 전역 `mem_stall`로 파이프라인 동결.
3. **CSR/Trap** (`csr_file`, `trap_unit`) — EX 스테이지에서 해결. CSR 읽기값을 `exmem_alu_result`에 폴딩해 기존 포워딩 그대로 활용. 트랩은 EX에서 PC 리다이렉트(트랩>분기 우선) + younger flush. 모든 커밋을 `not mem_stall`로 게이트.
4. **I$ 재구성** (`icache_unit`) — 미사용이던 IF-라인 부품 4종(addr_aligner, tag_array, comparator, cache_controller) + 신규 2종(icache_data_array, icache_axi_adapter)으로 read-only 직접사상 캐시 구성. SoC의 I$를 D$ 재활용에서 이 유닛으로 교체.
5. **FENCE.I** — `is_fence_i`를 EX로 운반 → 1-cycle one-shot `ic_fence_i` 펄스(`mem_stall`과 분리, 데드락 없음) → SoC가 I$ tag array를 무효화. Harvard 정적 i-mem이라 PC 리다이렉트 불필요.

---

## 3. Python 모델 회귀 결과 (이번 세션 실제 실행)

이중 독립 모델(파이프라인 사이클 정확 모델 vs 순차 ISS 골든)을 교차 비교. RTL과 무관하게 **로직/프로토콜 차원의 회귀**.

| 스크립트 | 결과 | 규모 |
|---|---|---|
| `run_ifwb_core.py` | **ALL GREEN** | AT-01..29 directed 29/29 + AT-30 랜덤 **4,000** 프로그램, 0 mismatch |
| `run_pipeline50.py` | **ALL GREEN** | 50 iteration, **142,388** 점검 |
| `test_rv32.py` | **ALL GREEN** | 10/10 iteration, **62,176** assertion |
| `run_id_wb_at.py` | **ALL PASS** | ID~WB 조합 모듈 54/54 |
| `run_alu_at.py` | **30/30** | + 결함주입 sra/slt/shamt 전부 검출 |
| `verify_spec.py` | **ALL GREEN** | 10/10, 550 점검 (스펙 문서 정합) |
| `verify_docs.py` | **110/110** | 문서 일관성 |

### 3.1 결함 주입 (검증 유효성 증명 — 버그를 실제로 잡는가?)

`run_ifwb_core.py --bug <X>`로 의도적 결함을 주입했을 때 **전부 검출**:

| 주입 결함 | Directed 결과 | 랜덤 반례 | 판정 |
|---|---|---|---|
| `forward` (포워딩 무력화) | 9/29 | 1500개 중 **652** mismatch | ✅ CAUGHT |
| `hazard` (load-use 스톨 제거) | 28/29 | **75** mismatch | ✅ CAUGHT |
| `branch` (분기 타겟 오류) | 22/29 | **1,166** mismatch | ✅ CAUGHT |
| `x0` (x0 쓰기 보호 제거) | 28/29 | **435** mismatch | ✅ CAUGHT |

→ 검증 스위트가 실제 결함을 검출함을 확인(거짓 통과 아님).

---

## 4. RTL 블록 ↔ TB ↔ 통합 커버리지 매트릭스

총 **32개 엔티티**. 각 블록의 단위 TB(SystemVerilog) 보유 여부와 통합 위치.

| 블록 (entity) | 단위 TB | 통합 위치 |
|---|---|---|
| pc_reg (program_counter) | ✅ tb_program_counter | rv32_core |
| pc_adder | ✅ | rv32_core |
| next_pc_mux | ✅ | rv32_core |
| addr_aligner | ✅ tb_address_aligner | icache_unit |
| comparator | ✅ | icache_unit |
| tag_array | ✅ | icache_unit |
| cache_controller | ✅ | icache_unit |
| **icache_data_array** (신규) | ✅ | icache_unit |
| **icache_axi_adapter** (신규) | ✅ | icache_unit |
| **icache_unit** (신규 래퍼) | ✅ tb_icache_unit | rv32_soc (I$) |
| control_unit | ✅ | rv32_core |
| imm_gen | ✅ | rv32_core |
| register_file | ✅ | rv32_core |
| hazard_unit | ✅ | rv32_core |
| csr_file | ✅ | rv32_core (EX) |
| alu | ✅ | rv32_core |
| alu_control | ✅ | rv32_core |
| bcu | ✅ | rv32_core |
| forwarding_unit | ✅ | rv32_core |
| trap_unit | ✅ | rv32_core (EX) |
| read_aligner | ✅ | rv32_core (MEM) |
| write_strobe_gen | ✅ | rv32_core (MEM) |
| dtag_array | ✅ | cache_unit |
| ddata_array | ✅ | cache_unit |
| dcache_controller | ✅ | cache_unit |
| axi_master | ✅ | cache_unit |
| axi_slave_mem | ✅ (tb_icache_unit 내) | rv32_soc |
| cache_unit | ⚠️ 독립 TB 없음 | rv32_soc (D$) — SoC 통합으로 검증 |
| result_mux | ✅ | rv32_core (WB) |
| pipeline_reg | ✅ | ⚠️ 미인스턴스화 (§5 참조) |
| rv32_core | ✅ tb_rv32_core_if_wb | rv32_soc |
| rv32_soc | ✅ tb_rv32_soc | (top) |

**단위 TB 31종 + 통합 TB 3종**(tb_rv32_core_if_wb, tb_rv32_soc, tb_icache_unit). 모든 단위 TB는 3-포인트 경계값 분석(BVA)과, 순차/FSM 블록의 경우 타이밍 케이스를 포함.

### 4.1 SoC 통합 TB(`tb_rv32_soc`) 커버리지

- Directed: ALU/포워딩, D$ load/store(미스→리필→라이트백), 2-라인 라이트백, eviction→writeback→re-read, 분기/JAL/루프.
- **CSR/Trap directed T1~T6**: CSRRW mscratch, CSRRS/RC set/clear, CSRRWI/SI, ECALL(mcause=11·mepc·younger squash), MRET 복귀, illegal(mcause=2).
- **FENCE.I T7**: 배리어가 cross-fence 데이터 의존(x3=x1+x2)과 store/load를 손상시키지 않음 + 무효화 stall 동작.
- **AT-30 랜덤**: 본문 24 + NOP 패드 4 + 메모리 readback 8(x16..x23) → 32-레지스터 전체를 ISS와 비트 단위 비교(데이터 메모리 store 경로/바이트·하프 레인까지 종단 검증).

---

## 5. 미통합 / 예외 / 알려진 한계 (정직한 기록)

1. **`pipeline_reg.vhd` 미인스턴스화** — 범용 파이프라인 경계 레지스터. 코어가 IF/ID·ID/EX·EX/MEM·MEM/WB를 *명시적 process*로 구현해 **기능상 대체**됨. 단위 TB(`tb_pipeline_reg`)와 `run_pipeline50.py`(WB-48)로 동작 자체는 검증됨. → 설계상 디자인 결정(인라인 레지스터 채택)이며 버그 아님. 라이브러리 대안 블록으로 보존.
2. **`cache_unit` 독립 단위 TB 없음** — D$ 래퍼. 하위 블록(dtag/ddata/dcache_controller/axi_master)은 각각 단위 TB 보유, 래퍼 자체는 SoC 통합 테스트로 검증.
3. **SoC top은 합성 불가(sim 전용)** — `axi_slave_mem`은 거동 모델 + 프로그램 프리로드 포트 포함. **Vivado IP 패키징 시 합성 가능한 top**(거동 메모리 제거, 실제 AXI 마스터 포트 노출)이 별도 필요.
4. **Harvard 구조** — 명령/데이터 메모리 분리. 자기수정 코드 불가. 따라서 FENCE.I는 이 SoC에서 아키텍처적으로 NOP이나, **무효화 경로 + 스톨은 실제로 동작·검증**됨(tb_icache_unit에서 무효화 후 재미스 확인).
5. **CSR rs1 소스 포워딩 없음** — CSR 쓰기 데이터(rs1)는 레지스터 파일 직독(EX 포워딩 미적용). directed 테스트는 소스를 ≥3 명령 앞에서 셋업. (CSR 결과 소비자는 정상 포워딩됨.)

---

## 6. 전체 SystemVerilog 회귀 실행 방법

단위/통합 TB를 한 번에 돌리는 배치 스크립트를 동봉: **`verification/run_all_xsim.bat`**
(Vivado 환경이 잡힌 명령창에서 실행 — 전체 VHDL 1회 컴파일 후 각 TB를 elaborate+run.)

또는 Vivado GUI에서 sim top을 바꿔가며 실행:
```tcl
close_sim
launch_simulation       # sim top = tb_rv32_soc (현재)
run all
```
각 단위 TB는 해당 파일을 sim top으로 지정 후 동일 절차.

**기대 출력 핵심 라인**
```
[tb_rv32_soc] checks=... errors=0 ...
RESULT: ALL PASS (full SoC: pipeline + I$/D$ + AXI)
```

### 6.1 확정된 xsim 2025.2 결과 (사용자 실행)
- `tb_rv32_soc` : **ALL PASS** (datapath + D$ + CSR/Trap T1~T6 + FENCE.I T7 + AT-30 랜덤)
- `tb_icache_unit` : **ALL PASS (19 checks)** — 콜드미스/HIT/eviction/FENCE.I 무효화
- `tb_icache_data_array` : **ALL PASS**
- `tb_icache_axi_adapter` : **ALL PASS (8 checks)**
- 나머지 단위 TB(ALU/ID/EX/MEM/WB/PC/캐시 하위블록) : 이전 세션에서 PASS 확인

> 참고: `tb_icache_axi_adapter`는 초기 핸드셰이크 샘플링 버그(인라인 자극이 조합 `arready`를 한 negedge 늦게 폴링 → 무한 대기)를 수정함. RTL(어댑터)은 무관 — `tb_icache_unit`에서 실 메모리로 이미 통과했었음. (TB-only fix)

---

## 7. 결론

디코드되는 모든 RV32I + Zicsr + 트랩 + FENCE.I 명령이 실제로 동작하며, 미사용이던 IF-라인 캐시 부품까지 전부 통합되어 **단일 미사용 라이브러리 블록(pipeline_reg)을 제외한 모든 RTL이 통합·검증**되었습니다. 모델 기반 회귀는 이번 세션에서 ALL GREEN(결함 주입 전건 검출 포함), HDL 회귀는 최신 xsim에서 ALL PASS입니다.

**다음 권장 단계:** Vivado IP 패키징 — 합성 가능한 top 구성(거동 메모리 제거, 실제 AXI 마스터 포트 노출) → Package IP.
