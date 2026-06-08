# Phase 6 — 검증 & 문서 핸드오버 (RV32-FullStack)

> 의의: 작은 서브유닛을 점증적으로 시뮬레이션하며 파이프라인 타이밍 정합을 지속 검증하고, 기초 검증 구조를 세워 검증팀에 매끄럽게 인계한다.
> 범위: 명세/문서/검증 단계.
> 확정 파라미터(요약): 32-bit 데이터/AXI, Direct-Mapped 4 KB 캐시, 16 B 라인, 256 라인, 100 MHz 목표, 분기 EX 해소(2-bubble). 근거는 `Movement.md` §1.

---

## 1. 목적

본 단계의 목적은 (1) 블록별 유닛 검증 계획 수립, (2) 파이프라인 타이밍 정합 검증, (3) 검증팀 인계를 위한 문서·하네스 구조 정리다.

## 2. 유닛 검증 계획 (점증적)

작은 서브유닛부터 위로 쌓는 bottom-up 순서로 검증한다.

| 단계 | 검증 대상 | 핵심 testbench 항목 |
|---|---|---|
| U1 | PC 유닛(pc_reg/pc_adder/next_pc_mux) | reset 벡터, +4 순차, stall 동결, pc_src 리다이렉트 |
| U2 | 캐시 프론트엔드(addr_aligner/tag_array/comparator) | 주소 분해, valid 게이팅, hit/miss 판정 |
| U3 | 캐시 컨트롤러 FSM | 미스→리필 천이, we=rvalid 캡처 타이밍, stall 연속성 |
| U4 | AXI Read/Write Master | 버스트 핸드셰이크, RLAST/BVALID 완료, wake_up |
| U5 | ID(디코더/레지스터파일/즉치) | 제어 신호표, x0=0, I/S/B/U/J 즉치 |
| U6 | EX(ALU/ALU control/BCU) | 연산표, BCU 분기 funct3 6종, target_addr, branch_taken |
| U6b | Forwarding Unit / Hazard Unit | forward_a/b 우선순위(EX/MEM>MEM/WB>RF), load-use stall/flush |
| U7 | 통합 파이프라인 | 5단 진행, 해저드/포워딩, 분기 2-bubble |
| U8 | CSR/Trap(머신모드) | SYSTEM/FENCE 디코드, 불법명령 트랩, ECALL/EBREAK, CSRRW/RS/RC, MRET, mepc/mcause |
| U9 | I-Cache 무효화(B1) | fence_i/ext_inv→inv 전 Valid 클리어, 적재 후 재페치로 갱신 코드, FENCE.I iflush |

## 3. 파이프라인 타이밍 정합 검증

다음 시나리오를 사이클 단위로 검증한다(타이밍 다이어그램 Phase 3 §5 기준).

| 시나리오 | 합격 기준 |
|---|---|
| 인출 Hit | 1 IPC, stall=0 유지 |
| 인출 Miss 리필 | stall이 미스 구간에만 연속, RLAST에서 wake_up 1회, 재시도 hit |
| 로드-유즈(Hazard+Forwarding) | 1-bubble 후 MEM/WB→EX 포워딩으로 정확한 값 |
| 분기 성립(BCU) | IF/ID·ID/EX flush, 2-bubble, 타겟 인출, pc_src/target_addr |
| 스토어 Hit | Data Array 바이트 기록, Dirty=1, WB 미기록 |
| 트랩(불법/ECALL) | PC←mtvec, flush_all, mepc/mcause 정확, 부작용 squash |
| I-Cache 무효화 | inv로 전 Valid 클리어, 적재 후 동일 PC가 miss→갱신 코드 리필(스테일 차단) |

기존 검증 하네스 연계:
- `verification/test_rv32.py` — IF 블록 RTL의 사이클 정확 참조 모델(10 iteration). 본 단계의 U1~U4 자동 검증 기반.
- `verification/verify_spec.py` — `RV32_Pipeline_Spec.md` 문서 정합(10 iteration).
- `verification/verify_docs.py` — 본 단계 산출 문서(Movement/Phase3~6) 문서 검증(문서당 20 iteration).

## 4. 검증 매트릭스 (블록 × 항목 × 방법)

| 블록 | 검증 항목 | 방법 |
|---|---|---|
| PC 유닛 | reset/+4/stall/redirect | 사이클 참조 모델 + 시뮬레이션 |
| 캐시 프론트엔드 | hit/miss/valid | 디렉티드 + 랜덤 |
| 캐시 컨트롤러 | FSM 천이/캡처 타이밍 | 상태 커버리지 + 불변식 |
| AXI 마스터 | 버스트/완료 | 핸드셰이크 시퀀스 |
| ID/EX | 인코딩/연산 | 진리표 대조 |
| BCU | 분기 조건/pc_src/target | 진리표 + 분기 시나리오 |
| Forwarding Unit | forward_a/b 우선순위 | 의존 패턴 전수 |
| Hazard Unit | load-use stall/flush | 코너 케이스 |
| CSR File | CSRRW/RS/RC 읽기·쓰기·부작용 억제 | 진리표 + zimm 변형 |
| Trap Unit | 예외 원인/mepc/mtvec 리다이렉트/MRET | 예외별 시나리오 + 정밀성 |
| I-Cache 무효화 | fence_i/ext_inv→inv, 스테일 라인 차단 | 적재-실행 시나리오 |
| 통합 | 해저드/타이밍 | 시나리오 시뮬레이션 |

## 5. 회귀 & 커버리지 전략

- **회귀:** 각 블록 수정 시 해당 유닛 testbench + 통합 시나리오를 재실행한다. 문서 변경 시 `verify_docs.py`/`verify_spec.py` 재실행.
- **커버리지:** FSM 상태·천이 100%, 분기 funct3 6종, 로드/스토어 funct3 전수, 해저드 경로(포워딩/스톨/플러시) 전수.
- **사인오프 권고:** 본 검증은 사이클/논리 정합 중심이므로, 최종 사인오프는 GHDL 또는 Vivado xsim 테스트벤치 1회로 보강한다.

## 6. 문서 핸드오버 구조 (검증팀 인계)

검증팀이 즉시 착수할 수 있도록 다음 자료를 한 묶음으로 인계한다.

| 분류 | 산출물 |
|---|---|
| 아키텍처 명세 | RV32_Pipeline_Spec.md (IF~WB 포트), Movement.md (동작·데이터 이동) |
| 데이터플로우/타이밍 | Dataflow_Architecture.md (블록·타이밍 다이어그램) |
| 인터페이스 계약 | Interface_LockIn.md (AXI/UART/흐름제어 락 테이블) |
| 구조/FSM | RTL_FSM_Placement.md (FSM 상태·천이·실행 시퀀스) |
| 검증 자산 | verification/ 하네스(test_rv32.py, verify_spec.py, verify_docs.py) + 리포트 |

## 7. 체크리스트 및 결론

- [x] 블록별 유닛 검증 항목 정의(U1~U7)
- [x] 파이프라인 타이밍 정합 시나리오 정의
- [x] 검증 매트릭스·커버리지·회귀 전략 수립
- [x] 검증팀 핸드오버 문서 묶음 정의

명세·데이터플로우·인터페이스·구조·검증 계획이 모두 문서화되어, 이후 RTL 구현과 검증을 같은 기준 위에서 진행할 수 있다.
