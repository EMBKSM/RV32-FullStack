# Phase 4 — 인터페이스 확정 & 락인 (RV32-FullStack)

> 의의: 아키텍처 청사진이 준비되면, 외부 블록과의 통신 프로토콜을 완전히 "락인(lock-in)" 하여 이후 RTL 작성을 단순화한다.
> 범위: 명세/문서/검증 단계. 인터페이스 신호는 `RV32_Pipeline_Spec.md`·`Movement.md`와 일치시킨다.
> 확정 파라미터(요약): 32-bit 데이터/AXI, Direct-Mapped 4 KB 캐시, 16 B 라인, 256 라인, 100 MHz 목표. 근거는 `Movement.md` §1.

---

## 1. 목적과 산출물

본 단계의 목적은 코어가 접하는 모든 인터페이스의 **프로토콜·신호·핸드셰이크·속도 합의**를 확정(lock)하는 것이다. 한번 잠그면 후속 단계에서 변경하지 않는 것을 원칙으로 한다.

## 2. 인터페이스 인벤토리

코어가 가지는 인터페이스는 세 부류다.

| 인터페이스 | 위치 | 상대 | 성격 |
|---|---|---|---|
| 내부 파이프라인 제어 | 스테이지 경계 | 자기 자신 | stall/flush/wake_up 기반 흐름 제어 |
| 메모리 버스 (AXI4) | PL 캐시 ↔ PS HP 포트 | Zynq PS / DDR3L | 표준 AXI4, 32-bit |
| 호스트 통신 (UART TLV) | UART RX/TX FSM ↔ PC IDE | C++ Qt IDE | 자체 TLV 패킷, 직렬 |
| EX 데이터패스 내부 | BCU·Forwarding Unit·Hazard Unit ↔ 파이프라인 | 자기 자신 | 조합 제어 인터페이스 |
| 머신모드 제어 | CSR File·Trap Unit ↔ 파이프라인 | 자기 자신 | CSR 접근·트랩 리다이렉트 |

## 3. 프로토콜 정의 및 확정 (AXI / OCP / Custom Ready-Valid)

각 인터페이스의 프로토콜을 명시적으로 확정한다.

| 인터페이스 | 후보 | **확정** | 근거 |
|---|---|---|---|
| 메모리 버스 | AXI4 / OCP / 커스텀 | **AXI4 (32-bit)** | Zynq PS HP 포트가 AXI 표준, 산업 호환·검증 IP 풍부 |
| 파이프라인 흐름제어 | 커스텀 Ready/Valid / 크레딧 | **커스텀 Ready/Valid (stall/wake_up)** | 단방향 인접 단 제어로 충분, 경량 |
| 호스트 통신 | AXI / 커스텀 TLV | **커스텀 TLV over UART** | 저핀·범용성, 무결성 체크섬 내장(프로젝트 정의) |

AXI4 채널은 read(`AR/R`)·write(`AW/W/B`)를 사용하고, 데이터 폭은 32-bit로 고정한다. 폭이 데이터패스(XLEN=32)와 동일하므로 폭 변환 FIFO가 불필요하다.

## 4. 인터페이스 락 테이블 (신호 레벨 계약)

### 4.1 AXI4 메모리 버스 (32-bit, 확정)

| 채널 | 핵심 신호 | 방향(마스터 기준) | 비고 |
|---|---|---|---|
| AR | ARADDR, ARLEN, ARSIZE, ARBURST, ARVALID / ARREADY | Out / In | 라인 16 B = ARLEN 3, ARSIZE 010, INCR |
| R | RDATA, RRESP, RLAST, RVALID / RREADY | In / Out | 32-bit, 4 beat, RLAST=완료 |
| AW | AWADDR, AWLEN, AWSIZE, AWBURST, AWVALID / AWREADY | Out / In | 후기록(D-Cache) |
| W | WDATA, WSTRB, WLAST, WVALID / WREADY | Out / In | 32-bit, WSTRB 4 |
| B | BRESP, BVALID / BREADY | In / Out | 쓰기 응답, BVALID=완료 |

핸드셰이크 규약: 모든 채널은 VALID·READY 동시 1인 사이클에 1 전송. `RLAST`/`BVALID`가 트랜잭션 완료를 알리며 캐시 컨트롤러 `wake_up` 소스가 된다.

### 4.2 파이프라인 흐름제어 (Ready/Valid 류)

| 신호 | 의미 | 전파 대상 |
|---|---|---|
| stall | 상류 동결 요청 | PC, IF/ID, ID/EX, EX/MEM |
| flush | 단 무효화(버블) | IF/ID, ID/EX |
| wake_up | 리필 완료 재개 | 캐시 컨트롤러 → 파이프라인 |

### 4.3 호스트 UART TLV 프레임 (확정)

프레임: `STX(0x53) + Command + Address(4B) + Data(가변) + ETX(0x50) + XOR Checksum`. 단일 쓰기와 버스트 쓰기 커맨드, 그리고 **I-Cache 무효화(INVALIDATE) 커맨드**를 정의한다(적재 직후 `ext_inv` 펄스 트리거). 헤더 반복 오버헤드를 줄인다.

### 4.4 EX 데이터패스 내부 인터페이스 (BCU / Forwarding Unit / Hazard Unit) — 락

분기 해소·바이패스·해저드 제어는 외부 버스가 아니지만, EX 단의 핵심 내부 인터페이스이므로 동일하게 신호를 잠근다.

**BCU (Branch Comparison Unit) 인터페이스:**

| 신호 | 방향 | 폭 | 의미 |
|---|---|---|---|
| a_fwd / b_fwd | In | 32 | 포워딩된 비교 피연산자 |
| funct3 | In | 3 | 분기 조건 |
| branch / jump / is_jalr | In | 1 | 분기/점프/JALR 제어 |
| pc / imm / rs1_fwd | In | 32 | 타겟 계산 입력 |
| branch_taken | Out | 1 | 조건 성립 |
| pc_src | Out | 1 | Next-PC MUX 선택(EX→IF) |
| target_addr | Out | 32 | 분기/점프 타겟(EX→IF) |

**Forwarding Unit 인터페이스:**

| 신호 | 방향 | 폭 | 의미 |
|---|---|---|---|
| id_ex_rs1 / id_ex_rs2 | In | 5 | EX 소스 번호 |
| ex_mem_rd / ex_mem_reg_write | In | 5/1 | EX/MEM 목적지/기록 |
| mem_wb_rd / mem_wb_reg_write | In | 5/1 | MEM/WB 목적지/기록 |
| forward_a / forward_b | Out | 2 | 00=RF, 10=EX/MEM, 01=MEM/WB |

**Hazard Unit 인터페이스:**

| 신호 | 방향 | 폭 | 의미 |
|---|---|---|---|
| id_ex_mem_read / id_ex_rd | In | 1/5 | 로드 여부/목적지 |
| if_id_rs1 / if_id_rs2 | In | 5 | ID 소스 |
| stall / flush | Out | 1 | 1-bubble 정지/버블 |

락 규약: 위 세 유닛은 모두 **조합(comb)** 이며, BCU의 `pc_src`/`target_addr`는 같은 EX 사이클에 IF로 도달해야 한다(역경로 타이밍 제약, Phase 3 §9). Forwarding/Hazard 출력도 같은 사이클에 유효하다.

### 4.5 CSR File / Trap Unit 인터페이스 (Machine-mode) — 락

표준 RV32I 머신모드를 위해 CSR 접근·트랩 인터페이스를 잠근다(상세 동작 `Movement.md` §4.5·§7.3, 스펙 §4.6·§6.7).

**CSR File 인터페이스:**

| 신호 | 방향 | 폭 | 의미 |
|---|---|---|---|
| csr_addr | In | 12 | instr[31:20] |
| csr_cmd | In | 2 | 00 none, 01 RW, 10 RS, 11 RC |
| csr_wdata | In | 32 | rs1_data 또는 zimm |
| csr_we | In | 1 | 부작용 규칙 반영 쓰기 enable |
| csr_rdata | Out | 32 | CSR 읽기 → WB |
| mstatus / mtvec / mepc | Out | 32 | Trap Unit로 |

**Trap Unit 인터페이스:**

| 신호 | 방향 | 폭 | 의미 |
|---|---|---|---|
| illegal_instr / instr_misalign / load_misalign / store_misalign | In | 1 | 예외 플래그 |
| is_ecall / is_ebreak / is_mret | In | 1 | 환경호출/브레이크/복귀 |
| instr_pc / fault_addr | In | 32 | mepc / mtval 소스 |
| trap_taken | Out | 1 | 트랩 진입 |
| trap_target | Out | 32 | mtvec(예외) 또는 mepc(MRET) |
| flush_all | Out | 1 | 전 파이프라인 무효화 |

락 규약: 트랩은 분기·해저드보다 높은 우선순위의 PC 리다이렉트이며, 예외는 WB 커밋에서 정밀하게 확정된다.

### 4.6 I-Cache 무효화 인터페이스 (B1) — 락

UART 코드 적재 ↔ I-Cache 일관성을 위해 무효화 경로를 잠근다(동작 `Movement.md` §3.5/§3.7, 스펙 §2.4.2/§2.4.4).

| 신호 | 방향(컨트롤러 기준) | 폭 | 의미 |
|---|---|---|---|
| fence_i | In | 1 | FENCE.I 무효화 요청(1-cycle 펄스) |
| ext_inv | In | 1 | 호스트 적재 무효화 요청(TLV INVALIDATE → 1-cycle 펄스) |
| inv | Out | 1 | Tag Array 전 Valid 클리어 |
| iflush | Out | 1 | FENCE.I 파이프라인 flush |

락 규약: `fence_i`/`ext_inv`는 **단일 사이클 펄스**로 공급한다(요청 측이 보장). 무효화는 miss보다 높은 우선순위이며, 무효화 직후 재페치로 DDR의 갱신 코드를 가져온다.

## 5. I/O 속도 정합 (Critical — 병목 식별·합의)

| 도메인 | 처리율(이론) | 비고 |
|---|---|---|
| 코어 실행 | 100 MHz × 1 IPC | 32-bit 명령/사이클 |
| AXI 메모리 | 32-bit @ 100 MHz = 400 MB/s | 라인 리필 16 B = 5 beat(AR+R×4) |
| UART 호스트 | 1 Mbps급 = 약 0.125 MB/s | 코어 대비 수천 배 느림 |

**병목·합의:**
- **주 병목은 UART**(대량 바이너리 적재). 합의: 적재는 코어 실행과 **비동기 분리**, TLV **버스트 쓰기**로 헤더 오버헤드 최소화, 보드레이트 상향(1 Mbps+) 목표.
- **AXI ↔ 코어:** 폭이 동일(32-bit)하여 정합 손실 없음. 미스 패널티는 `AR 1 + R 4 + FSM 오버헤드` 사이클로 산정(타이밍 다이어그램 Phase 3 §5).
- **백프레셔 합의:** 메모리 지연은 캐시 `stall`로 코어에 전달되고, UART 지연은 호스트측 핸드셰이크(ACK/체크섬 재전송)로 흡수한다.

## 6. 백프레셔/스톨 전파 규약

- 캐시 미스 → `stall=1` → 상류 4개 경계 레지스터 동시 동결 + MEM/WB 버블.
- AXI READY 지연 → 컨트롤러 FSM이 해당 상태 유지(자연 백프레셔).
- UART RX 지연 → 패킷 FSM이 헤더/페이로드/체크섬 단계에서 대기, 무결성 실패 시 폐기·재전송.

## 7. 락인 체크리스트 및 다음 단계

- [x] 메모리 프로토콜 = AXI4 32-bit 확정
- [x] 파이프라인 흐름제어 = stall/flush/wake_up 확정
- [x] 호스트 = TLV/UART 프레임·체크섬 확정
- [x] I/O 병목(UART) 식별·정합 합의
- [x] 채널 완료 신호(RLAST/BVALID) → wake_up 매핑 확정

인터페이스가 잠겼으므로 다음 단계(Phase 5)에서 구조·FSM 배치를 정의한다(코딩은 이후).
