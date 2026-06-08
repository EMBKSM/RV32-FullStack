# RV32I 파이프라인 RTL 구현 리포트 (ID~WB 전 구간)

방법: VHDL RTL + SystemVerilog TB + ATDD/Shift-Left. 검증은 샌드박스 실행(Python 골든모델 수용 테스트) + 구조 점검, 실 RTL 시뮬은 Vivado xsim/Questa.

## 1. 작성된 RTL (25개 .vhd)
- **IF**(기존): pc_adder, next_pc_mux, program_counter, address_aligner, comparator, tag_array, cache_controller(+B1 무효화)
- **ID**: control_unit(디코더, SYSTEM/FENCE/illegal 포함), imm_gen(I/S/B/U/J), register_file(2R/1W, x0=0, write-first), csr_file(Zicsr+트랩), hazard_unit(load-use)
- **EX**: alu, alu_control, bcu(분기비교+타겟+pc_src), forwarding_unit, trap_unit(예외/트랩 커밋)
- **MEM**: read_aligner(로드 정렬·확장), write_strobe_gen(SB/SH/SW), dtag_array(tag+valid+dirty), ddata_array(256×128b, 라인 in/out), dcache_controller(write-back FSM), axi_master(4-beat INCR R/W 버스트)
- **WB**: result_mux(ALU/MEM/PC4/CSR)
- **공용**: pipeline_reg(IF/ID·ID/EX·EX/MEM·MEM/WB 범용, flush=control bubble)

## 2. 검증 결과
- **조합 모듈 수용 테스트(ATDD): 54/54 PASS** — control_unit, imm_gen, alu_control(64 exhaustive), bcu, forwarding_unit, hazard_unit, read_aligner, write_strobe_gen, result_mux. (`verification/run_id_wb_at.py`)
- **ALU: 30/30** + 결함주입 counter-example 검출(`verification/run_alu_at.py`).
- **구조 점검: 25/25 파일 균형** (entity/architecture/process/case 정합, 0 불일치).
- 발견·수정: imm_gen S-타입 테스트의 기대값 오류(부호확장 누락) 정정 — RTL은 정상.

## 3. SystemVerilog 테스트벤치
- `ip_workspace/2_EX/tb_alu.sv` — ALU(AT-01~30 + 10만 랜덤).
- `ip_workspace/1_ID/tb_control_unit.sv` — 디코더(대표 ID TB).
- 나머지 모듈도 동일 패턴으로 생성 가능. 혼합언어 실행: `xvhdl *.vhd; xvlog -sv tb_*.sv; xelab tb_* -R`.

## 4. Vivado 사인오프 필요 항목(샌드박스 시뮬 불가)
순차/FSM 모듈: register_file, csr_file, dtag_array, ddata_array, dcache_controller, axi_master, pipeline_reg, trap_unit↔csr_file 결합. 구조·로직은 명세 정합하나 타이밍/엘라보레이션은 xsim 권장.

## 5. 다음 단계
스테이지 데이터패스 top(필드 패킹/배선) 통합 + 코어 top + 통합 테스트벤치(명령어 시퀀스) 작성.
