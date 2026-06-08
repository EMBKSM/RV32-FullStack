# ALU 검증 리포트 (ATDD / Shift-Left, 30 iteration + counter-example)

대상: `ip_workspace/2_EX/alu.vhd` (RV32I EX ALU)
방법: Shift-Left ATDD — 수용 테스트(AT-01~30) 선정의 → TB/RTL 구현 → 30회 검증 + 결함주입 반례.
결과: **클린 30/30 PASS. 결함 주입 시 반례 검출 정상(테스트 유효성 입증).**

## 1. 산출물
- `ip_workspace/2_EX/alu_acceptance_tests.md` — 수용 테스트 명세(작성 선행).
- `ip_workspace/2_EX/alu.vhd` — VHDL RTL.
- `ip_workspace/2_EX/tb_alu.sv` — SystemVerilog 자기검증 TB(Vivado xsim/Questa용, AT-01~30 + 10만 랜덤).
- `verification/run_alu_at.py` — 샌드박스 실행 골든모델 하네스(동일 AT + 결함주입 반례).

## 2. ATDD 절차(Shift-Left)
1. 수용 기준 AC-1~6 및 케이스 AT-01~30을 **RTL보다 먼저** 확정.
2. 동일 케이스를 SystemVerilog TB와 Python 하네스로 구현(독립 기대값).
3. 통과하도록 `alu.vhd` 구현 → 클린 30/30.

## 3. 실행 결과 (Python 하네스)
- **클린: 30/30 PASS** (directed AT-01~29 독립 기대값 + AT-30 랜덤 10만 벡터 골든 일치).
- **Counter-example(결함 주입) 검출:**
  - `--bug sra`(SRA→논리시프트): 27/30 → AT-15·AT-17·AT-30 반례 검출.
  - `--bug slt`(SLT→무부호): 27/30 → AT-18·AT-19·AT-30 반례 검출.
  - `--bug shamt`(시프트 마스킹 누락): 28/30 → AT-12·AT-30 반례 검출.
  - → 명세 §4 결함주입 표와 정확히 일치. 테스트가 실제로 버그를 잡음을 입증.

## 4. 시뮬레이터 주: 실 RTL 시뮬레이션
샌드박스에 HDL 시뮬레이터(ghdl/verilator/xsim)가 없어 실행은 Python 골든모델로 수행했다. **실 RTL 검증은 사용자 Vivado에서 `tb_alu.sv`로 수행**:
```
xvhdl ip_workspace/2_EX/alu.vhd
xvlog -sv ip_workspace/2_EX/tb_alu.sv
xelab tb_alu -R     # 또는 Questa: vcom/vlog/vsim
```
SV TB와 Python 하네스는 동일한 AT-01~30·골든 로직을 공유한다.

## 5. 다음 모듈(권고)
ALU Control(`alu_op×funct3×funct7[5]→alu_ctrl`), Immediate Generator, Register File, BCU, Forwarding/Hazard Unit 순으로 동일 ATDD 적용.
