# IF~WB 50-iteration 재검증 리포트

대상: RV32I 파이프라인 전 구간 RTL (IF·ID·EX·MEM·WB).
하네스: `verification/run_pipeline50.py` (test_rv32/IF, run_alu_at/ALU, run_id_wb_at/조합 재사용 + 순차·FSM 모델 추가).
결과: **50/50 iteration ALL GREEN, 총 142,388 sub-check.**

## 1. 구성 (50 iteration)

| 구간 | iter | 내용 |
|---|---|---|
| IF | 01~10 | RTL 정적 sanity, addr_aligner, comparator, PC, tag_array+무효화, 캐시 FSM 천이/출력+B1, 리필 통합, BUG-001, 리그레션 |
| ID | 11~20 | 디코더(R/I/L/S, 분기/점프/LUI/AUIPC, SYSTEM, FENCE/illegal), imm_gen(I/S/B/U/J), register_file(x0/write-first), csr_file(CSRRW/RS/RC, 트랩/MRET), hazard_unit |
| EX | 21~32 | ALU(산술/논리/시프트/SLT·SLTU/Bpass) + 50k 랜덤 + 결함주입 검출, alu_control 64-exhaustive, BCU(조건/타겟/20k 랜덤), forwarding, trap_unit |
| MEM | 33~44 | read_aligner, write_strobe, dtag/ddata array, dcache_controller FSM 천이/출력, axi_master 읽기/쓰기 버스트, 캐시 통합(load-miss clean / store-miss dirty→writeback) |
| WB | 45~48 | result_mux(+10k 랜덤), pipeline_reg(latch/stall/flush/reset) |
| 통합 | 49~50 | 포워딩 바이패스, load-use 버블+MEM/WB 포워딩 |

## 2. 검증 강도
- 결정적 directed + 대량 랜덤 counter-example: ALU 50k, BCU 20k, result_mux 10k, addr/comparator 6만(IF 재사용).
- 결함주입 회귀: ALU(sra/slt/shamt) 반례 검출 정상 → 테스트 유효성 입증.
- 누적 sub-check 142,388건 전부 통과.

## 3. 한계 / Vivado 사인오프
순차·FSM 모듈은 사이클 정확 Python 모델로 검증했다. 타이밍/엘라보레이션 사인오프는 Vivado xsim에서 `tb_alu.sv`·`tb_control_unit.sv` 패턴으로 재확인 권장.

## 4. 재현
```
python3 verification/run_pipeline50.py     # 50/50
python3 verification/run_id_wb_at.py       # 54 조합 수용 테스트
python3 verification/run_alu_at.py         # ALU 30 + 결함주입
python3 verification/test_rv32.py          # IF 10
```
