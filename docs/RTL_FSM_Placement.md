# Phase 5 — RTL 구조 / FSM 배치 설계 (RV32-FullStack)

> 의의: 구조와 인터페이스가 잠기면, 코딩은 순수 "타이핑/구현 작업"으로 취급된다. 본 문서는 **그 구현 직전의 구조·FSM·실행 시퀀스**를 확정한다.
> 범위: 명세/문서/검증 단계.
> 확정 파라미터(요약): 32-bit 데이터/AXI, Direct-Mapped 4 KB 캐시, 16 B 라인, 256 라인, 100 MHz 목표, 분기 EX 해소(2-bubble). 근거는 `Movement.md` §1.

---

## 1. 설계 원칙

- **FSM은 시작점이 아니라 결과물(outcome)이다.** 먼저 구조적 동작·I/O 신호·실행 시퀀스를 정의하면, FSM은 그로부터 도출된다.
- **코딩 스타일은 부차적이다.** 2-process FSM 등 특정 기술 방식은 잘 정의된 구조 위에서 표준 제어 로직으로 쉽게 구현된다. 본 문서는 스타일이 아니라 상태·천이·출력·시퀀스에 집중한다.
- 성능과 전력에 최적화된 **구조적 거동, FSM 상태, I/O 신호, 실행 순서**를 정의한다.

## 2. FSM 인벤토리

코어/주변에 필요한 FSM과 그 역할을 확정한다. (Cache Controller는 이미 RTL이 존재한다.)

| FSM | 모듈 | 상태 수 | 상태 | 비고 |
|---|---|---|---|---|
| 캐시 컨트롤러 | cache_controller | 5 | S_IDLE, S_SEND_AR, S_WAIT_R, S_UPDATE_CACHE, S_WAKE_UP | 구현됨(읽기 리필) |
| AXI Read Master | axi_rd_master | 4 | R_IDLE, R_ADDR, R_DATA, R_DONE | 라인 4-beat 수신 |
| AXI Write Master | axi_wr_master | 5 | W_IDLE, W_ADDR, W_DATA, W_RESP, W_DONE | 후기록 + B 응답 |
| UART RX 패킷 | uart_rx_fsm | 7 | U_IDLE, U_STX, U_CMD, U_ADDR, U_DATA, U_ETX, U_CKSUM | TLV 무결성 검증 |

### 2.1 캐시 컨트롤러 FSM (확정·구현됨)

| 상태 | 출력(요지) | 천이 조건 |
|---|---|---|
| S_IDLE | miss 시 stall=1 | miss=1 → S_SEND_AR |
| S_SEND_AR | arvalid=1, stall=1 | arready=1 → S_WAIT_R |
| S_WAIT_R | rready=1, stall=1, we=rvalid | rvalid=1 → S_UPDATE_CACHE |
| S_UPDATE_CACHE | stall=1 | → S_WAKE_UP |
| S_WAKE_UP | wake_up=1, stall=0 | → S_IDLE |
| S_IDLE + fence_i/ext_inv | inv=1, stall=1, iflush=fence_i | → S_IDLE (무효화 1사이클) |

### 2.2 AXI Read Master FSM (확정)

| 상태 | 출력(요지) | 천이 조건 |
|---|---|---|
| R_IDLE | 대기 | 리필 요청 → R_ADDR |
| R_ADDR | ARVALID, ARLEN=3, ARSIZE=010 | ARREADY=1 → R_DATA |
| R_DATA | RREADY, beat 카운터++ | RLAST=1 → R_DONE |
| R_DONE | 완료 펄스(→wake_up) | → R_IDLE |

### 2.3 AXI Write Master FSM (확정)

| 상태 | 출력(요지) | 천이 조건 |
|---|---|---|
| W_IDLE | 대기 | 후기록 요청 → W_ADDR |
| W_ADDR | AWVALID, AWLEN=3 | AWREADY=1 → W_DATA |
| W_DATA | WVALID, WSTRB, beat++ | WLAST 송출 → W_RESP |
| W_RESP | BREADY | BVALID=1 → W_DONE |
| W_DONE | 완료 펄스(→wake_up) | → W_IDLE |

### 2.4 UART RX 패킷 FSM (확정)

| 상태 | 출력(요지) | 천이 조건 |
|---|---|---|
| U_IDLE | 대기 | STX(0x53) 수신 → U_STX |
| U_STX | 헤더 시작 | → U_CMD |
| U_CMD | 커맨드 래치 | → U_ADDR |
| U_ADDR | 주소 4B 누적 | 4바이트 완료 → U_DATA |
| U_DATA | 페이로드 누적 | 길이 완료 → U_ETX |
| U_ETX | ETX(0x50) 확인 | → U_CKSUM |
| U_CKSUM | XOR 체크섬 비교 | 일치=수락 / 불일치=폐기 → U_IDLE |

### 2.5 비-FSM 조합 제어 유닛 (BCU / Forwarding Unit / Hazard Unit)

상태가 없는 순수 조합 제어 유닛은 FSM이 아니라 **진리표로 완전히 정의**된다(상세 표 `Movement.md` §5, 메인 스펙 §6.4~6.6). 이들은 "FSM은 결과물" 원칙의 반례가 아니라, 구조가 곧 조합 논리로 사상되는 대표 예다.

| 유닛 | 입력 | 출력 | 성격 |
|---|---|---|---|
| BCU (Branch Comparison Unit) | a_fwd, b_fwd, funct3, branch, jump, is_jalr, pc, imm | branch_taken, pc_src, target_addr | 조합, EX→IF 역경로 |
| Forwarding Unit | ID/EX.rs1/rs2, EX/MEM.rd/reg_write, MEM/WB.rd/reg_write | forward_a, forward_b | 조합, 우선순위 선택 |
| Hazard Unit | ID/EX.mem_read/rd, IF/ID.rs1/rs2 | stall, flush | 조합, load-use 검출 |

BCU의 `pc_src`/`target_addr`는 같은 EX 사이클 내 IF 도달 제약을 가지므로, 합성 시 이 조합 경로를 임계경로 후보로 명시 관리한다.

**머신모드 추가 구조(Category A):** Decoder는 `SYSTEM`(`1110011`)·`FENCE`(`0001111`)를 디코드하고 미매칭은 `illegal_instr`로 처리한다. **CSR File**(머신모드 레지스터 파일, 읽기 comb·쓰기 WB 커밋)과 **Trap & Exception Unit**(조합 검출 + WB 커밋 시 PC←`mtvec`/`mepc` 리다이렉트, 정밀 예외)을 추가한다. 이들은 FSM이 아니라 레지스터 파일+조합 제어로 사상되며, `MRET`은 트랩 복귀 명령이다. 상세는 `Movement.md` §4.5/§4.6/§7.3.

## 3. 모듈 I/O 신호 정리

각 모듈의 포트는 `RV32_Pipeline_Spec.md`(IF/ID/EX/MEM/WB 포트 표)와 `Movement.md`(동작·데이터 이동)를 단일 출처로 한다. 본 문서는 FSM 상태·천이·출력만 추가 정의한다. 핵심 흐름제어 신호는 stall, flush, wake_up, we, pc_src, forward_a/b 이며 데이터 신호는 ALU Result, Data2, Read Data, WriteData, target_addr 이다. BCU·Forwarding Unit·Hazard Unit은 조합 유닛으로 §2.5에 정의한다.

## 4. 실행 시퀀스 (성능·전력 최적화)

- **인출/실행 1 IPC:** hit·비분기·비로드-유즈 흐름은 1 사이클/명령.
- **미스 패널티 최소화:** 리필 중 stall을 정확히 미스 구간에만 유지하고, S_WAKE_UP에서 즉시 해제하여 불필요한 정지 사이클을 없앤다.
- **분기 패널티:** EX 해소 2-bubble. 정적 not-taken으로 비분기 다수 경로를 최적화.
- **전력(클럭 게이팅 포인트):** 캐시 미스 동안 유휴인 EX/MEM 연산 블록, 후기록 미발생 시 Write Master, 비통신 구간의 UART FSM은 클럭 게이팅 후보다.
- **스톨 최소화:** 로드-유즈는 포워딩으로 대부분 흡수하고 불가피한 1-bubble만 남긴다.

## 5. 구조 → 제어 로직 매핑 가이드

- 각 FSM은 (상태 레지스터 process) + (다음상태 조합 process) + (출력 조합 process) 의 표준 구조로 사상된다. 2-process/3-process 여부는 구현 편의 문제일 뿐, 위 상태·천이·출력 표가 동일 거동을 보장한다.
- 출력은 가능한 Moore 형으로 두되, 데이터 캡처처럼 입력 핸드셰이크와 정렬이 필요한 신호(예: we=rvalid)는 Mealy 형으로 둔다(캐시 컨트롤러 검증 반영).

## 6. 성능·전력 요약 지표

| 지표 | 목표/근거 |
|---|---|
| 목표 IPC | 1.0 (정상 흐름) |
| 분기 패널티 | 2 사이클(EX 해소) |
| 로드-유즈 패널티 | 1 사이클(포워딩 후) |
| 미스 패널티 | AR 1 + R 4 + FSM 오버헤드 |
| 전력 절감 | 유휴 블록 클럭 게이팅 |

## 7. 다음 단계

구조·FSM·실행 시퀀스가 확정되었다. 다음 단계(Phase 6)에서 유닛 검증과 문서 핸드오버 구조를 정의한다. 실제 HDL 코딩은 본 청사진을 "타이핑"하는 후속 작업으로 분리한다.
