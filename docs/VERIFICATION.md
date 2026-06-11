# RV32-FullStack — 통합 검증 문서 (Verification Dossier)

이 문서는 프로젝트 전체의 **검증 과정·방법론·결과**를 하나로 정리한 것이다. (이전의
`VERIFICATION_REPORT*.md`, `RTL_IMPLEMENTATION_REPORT.md`, `VERIFICATION_REPORT_ALU.md`
등 단계별 산출물을 통합·대체한다.)

대상 설계: **RV32I + Zicsr + 트랩 + Zifencei** 5-stage 파이프라인 CPU + I$/D$ + AXI4 메모리,
그리고 이를 Zynq PS가 AXI-Lite로 제어하는 호스트제어 SoC 플랫폼.

---

## 1. 검증 철학 / 방법론

- **Shift-Left / ATDD**: 각 블록·통합 단계마다 *수용 테스트(acceptance test)를 먼저 정의*하고
  (`ip_workspace/*/**_acceptance_tests.md`), 그 기준으로 RTL을 검증.
- **이중 독립 모델 교차검증**: 동일 프로그램을 (a) **사이클 정확 파이프라인 모델**과
  (b) **독립 ISS(명령 단위 골든)** 으로 각각 실행해 최종 아키텍처 상태(레지스터/메모리)를
  비트 단위 비교. 두 모델이 독립이라 공통 오류가 상쇄되지 않는다.
- **반례 랜덤 스윕(counter-example)**: 수천~수만 개의 랜덤 RV32I 프로그램을 생성해 모델 vs ISS
  비교 — 손으로 못 짚는 코너케이스를 잡는다.
- **결함 주입(fault injection)**: 의도적으로 버그(포워딩 무력화 등)를 주입해 *검증 스위트가
  실제로 그 버그를 잡는지* 증명 → "거짓 통과"가 아님을 보장.
- **3-포인트 경계값 분석(BVA)**: 모든 조합 블록 단위 TB에 경계−1/경계/경계+1 케이스.
- **타이밍 케이스**: 순차/FSM 블록 TB에 stall/flush/리셋/핸드셰이크 타이밍 케이스.
- **HDL 사인오프**: 최종 검증은 Vivado xsim(SystemVerilog TB)에서 수행.

도구:
- Python 모델(`verification/*.py`): 로직/프로토콜 차원의 모델 기반 회귀.
- SystemVerilog TB(`tb_*.sv`): 실 RTL(xsim) 검증.

---

## 2. 검증 계층(아래에서 위로)

### 2.1 블록 단위 TB (SystemVerilog, xsim)
32개 RTL 엔티티 각각에 단위 TB(`tb_<block>.sv`)를 두고, 자가검증 + BVA(+순차 블록 타이밍)
포함. 단위 TB가 없는 유일한 예외는 `cache_unit`(D$ 래퍼 — SoC 통합으로 검증).

| 그룹 | 블록 |
|---|---|
| IF | pc_reg, pc_adder, next_pc_mux, addr_aligner, comparator, tag_array, cache_controller, icache_data_array, icache_axi_adapter |
| ID | control_unit, imm_gen, register_file, hazard_unit, csr_file |
| EX | alu, alu_control, bcu, forwarding_unit, trap_unit |
| MEM | read_aligner, write_strobe_gen, dtag_array, ddata_array, dcache_controller, axi_master |
| WB/공통 | result_mux, pipeline_reg |

### 2.2 조합 모듈 ATDD (Python)
- `run_alu_at.py` — ALU 수용 테스트 **30/30 PASS**, 결함 주입(sra/slt/shamt) 전건 검출.
- `run_id_wb_at.py` — ID/EX/MEM/WB 조합 모듈 **54/54 PASS**.

### 2.3 IF~WB 데이터패스 통합
- `run_ifwb_core.py` — 사이클정확 파이프라인 모델 vs ISS.
  - Directed AT-01..AT-29: **29/29 PASS**
  - AT-30 랜덤 반례 스윕: **수천 프로그램, 0 mismatch (ALL GREEN)**
  - **결함 주입 검출(증명)**: forward / hazard / branch / x0 전건 CAUGHT.
- `tb_rv32_core_if_wb.sv` — 같은 AT-01..AT-30을 실 RTL(xsim)로 사인오프, ALL PASS.

### 2.4 풀 SoC 통합 (`tb_rv32_soc.sv`, xsim)
코어 + I$ + D$ + AXI4 거동 메모리(Harvard)를 함께 검증.
- Directed: ALU/포워딩, D$ load/store(미스→리필→라이트백), 2-라인 라이트백,
  eviction→writeback→re-read, 분기/JAL/루프.
- **CSR/Trap** T1~T6: CSRRW/RS/RC(+I), ECALL(mcause=11·mepc·younger squash), MRET 복귀,
  illegal(mcause=2).
- **FENCE.I** T7: 배리어가 데이터 흐름을 손상시키지 않음 + I$ 무효화 동작.
- **AT-30 랜덤**: 본문 24 + NOP 패드 + 메모리 readback(x16..x23) → 32-레지스터 전체를 ISS와
  비트단위 비교(데이터메모리 store 경로/바이트·하프 레인까지 종단 검증). ALL PASS.

### 2.5 I-캐시 재구성 검증
IF-라인 부품(addr_aligner/tag_array/comparator/cache_controller) + 신규(icache_data_array/
icache_axi_adapter)로 재구성한 read-only I$.
- `tb_icache_data_array.sv`, `tb_icache_axi_adapter.sv`(인라인 AXI slave 모델), `tb_icache_unit.sv`
  (콜드미스 리필→정확한 워드, 같은 라인 HIT 0-stall, 인덱스 충돌 evict→재미스, FENCE.I 무효화).
  모두 ALL PASS.

### 2.6 회귀 캠페인 (Python)
- `run_pipeline50.py` — 50 iteration, **142,388 점검, ALL GREEN**.
- `test_rv32.py` — 10 iteration, **62,176 assertion, ALL GREEN**.
- `verify_spec.py` — 스펙 문서 정합 10/10 (550 점검).
- `verify_docs.py` — 문서 일관성 110/110.

### 2.7 호스트제어 플랫폼 (`tb_rv32_platform.sv`, xsim)
AXI-Lite BFM이 PS 역할: 프로그램 적재 → run → 레지스터/MMIO 상태 읽기.
- 적재 → 실행 → x1=7/x2=11/x3=18/x4=LED base 레지스터 읽기, **MMIO LED=2**, halted 감지.
- 단일스텝 sanity(스텝 시 커밋 진행). **ALL PASS.**
- (브링업 진단: `tb_plat_diag*.sv`로 AXI 핸드셰이크/리셋 desync를 격리 — 일회용, 정리 단계에서 제거.)

### 2.8 구현(Implementation) 사인오프 — Zynq / Zybo Z7-20
- BD: Zynq7 PS(보드 프리셋) + `rv32_platform` IP + AXI SmartConnect(@`0x4000_0000`) + GPIO 외부.
- 합성/구현/비트스트림 **성공**: BRAM 12/140, LUT ~47%, **타이밍 만족(WHS>0), Failed Routes 0**.
- axi_slave_mem을 동기(prefetch-registered) 읽기 + 통일 바이트쓰기로 바꿔 **BRAM 추론**(외부 AXI
  타이밍 불변, 캐시 동작 동일).

---

## 3. 결과 요약

| 검증 축 | 결과 |
|---|---|
| 블록 단위 TB (31종) + BVA + 타이밍 | PASS |
| ALU ATDD 30/30, ID~WB 54/54 | PASS (+결함 검출) |
| IF~WB 모델: directed 29/29 + 랜덤 수천 0 mismatch | ALL GREEN |
| 결함 주입(forward/hazard/branch/x0, ALU sra/slt/shamt) | 전건 CAUGHT |
| SoC 통합(datapath+D$+CSR/Trap+FENCE.I+AT-30) | ALL PASS |
| I$ 재구성 단위/통합 | ALL PASS |
| pipeline50 (142,388 점검) / test_rv32 (62,176 assert) | ALL GREEN |
| spec/docs 정합 | PASS |
| 플랫폼(load/run/step/MMIO) | ALL PASS |
| 합성·구현·비트스트림 (Zybo Z7-20) | 성공, 타이밍 OK |

---

## 4. 블록 ↔ TB ↔ 통합 커버리지

32개 엔티티 모두 어딘가에 통합·검증됨. 예외 기록:
- **`pipeline_reg`**: 코어가 인라인 경계 레지스터를 채택해 *미인스턴스화*(기능 대체). 단위 TB +
  `run_pipeline50`(WB-48)로 동작 자체는 검증. (BD 손배선용으로는 별도 IP로 활용 가능.)
- **`cache_unit`**: 독립 단위 TB 없음 — 하위 블록은 각각 TB 보유, 래퍼는 SoC 통합으로 검증.

---

## 5. 알려진 한계 / 설계 메모

1. **Harvard 구조**(명령/데이터 메모리 분리) — 자기수정 코드 불가. FENCE.I는 이 SoC에서
   아키텍처적으로 NOP이나 *무효화 경로+스톨은 실제로 동작·검증*됨.
2. **파이프라인 정밀 단일스텝**: 5-stage가 꽉 차면 "1커밋 정지"가 한 명령 더 흘려보낼 수 있음
   (off-by-one). 실제 per-instruction UX는 "명령+halt 적재 → run → 읽기"로 동일 효과를 낸다.
   (정밀 스텝은 프론트엔드 게이팅 별도 작업.)
3. **CSR rs1 소스 포워딩 없음**: CSR 쓰기 데이터는 레지스터파일 직독(directed 테스트는 소스를
   ≥3 명령 앞에서 셋업). CSR 결과 소비자는 정상 포워딩됨.
4. **시뮬용 메모리**: `axi_slave_mem`은 프로그램 프리로드 포트를 가진 거동 메모리이며, 합성
   시 BRAM으로 추론된다(동기 읽기). 큰 외부 DRAM이 필요하면 PS DDR + DMA로 확장.
5. **데이터 덤프(DMEM_RDATA)**: write-back D$ 특성상 더티 라인은 RAM에 아직 없을 수 있어,
   정확한 덤프는 프로그램 halt 후 권장(레지스터 readback이 1차 관찰 경로).

---

## 6. 재현 방법

- **모델 회귀(Python)**: `verification/`에서
  `python run_ifwb_core.py --programs 4000`, `run_pipeline50.py`, `test_rv32.py`,
  `run_alu_at.py`, `run_id_wb_at.py`, `verify_spec.py`, `verify_docs.py`.
  결함 검출 확인: `python run_ifwb_core.py --bug forward|hazard|branch|x0`.
- **HDL 회귀(xsim)**: `scripts/run_all_xsim.bat` (전 VHDL 1회 컴파일 후 모든 SV TB 일괄 실행),
  또는 Vivado에서 sim top을 각 TB로 지정해 실행. SoC: `tb_rv32_soc`, 플랫폼: `tb_rv32_platform`.
- **구현→비트스트림**: `scripts/`의 IP 패키징 → BD 빌드 → 비트스트림 (해당 스크립트 README 참조).
