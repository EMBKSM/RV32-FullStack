# Phase 3 — 데이터플로우 & 아키텍처 확정 (RV32-FullStack Core)

> 의의: 본 단계가 아키텍처의 약 70%를 결정하며, 실제 코딩보다 훨씬 많은 시간을 요구한다. "입력이 언제 들어오고 나가야 하는가", "내부 버퍼/파이프라인이 필요한가"를 정밀하게 확정한다.
> 범위: 명세/문서/검증 단계. **RTL 코딩은 수행하지 않는다.** 신호/블록 정의는 `RV32_Pipeline_Spec.md`·`Movement.md`를 단일 출처로 삼는다.
> 확정 파라미터(요약): 32-bit 데이터패스/AXI, Direct-Mapped 4 KB 캐시, 16 B 라인, 256 라인, 100 MHz 목표, 분기 EX 해소(2-bubble). 상세 근거는 `Movement.md` §1.

---

## 1. 목적과 산출물

본 문서의 목적은 코드 작성 이전에 **구조적 아키텍처와 타이밍 제약을 스케치·확정**하는 것이다. 산출물은 (1) 블록 간 연결성 매트릭스, (2) 데이터플로우 타이밍 규약, (3) 블록 다이어그램, (4) 타이밍 다이어그램, (5) 구조 결정 근거다.

## 2. 연결성 매트릭스 (Producer → Consumer)

각 신호의 생산 블록(Producer)·소비 블록(Consumer)·방향·지연 유형을 확정한다.

| 신호 | Producer | Consumer | 폭 | 지연 |
|---|---|---|---|---|
| pc | PC Register | PC Adder, Addr Aligner | 32 | seq |
| pc_plus_4 | PC Adder | Next-PC MUX, IF/ID | 32 | comb |
| next_pc | Next-PC MUX | PC Register | 32 | comb |
| tag/idx/offset | Addr Aligner | Tag/Data Array, Comparator | 20/8/4 | comb |
| hit | Comparator | Cache Controller, 인출 게이트 | 1 | comb |
| stall | Cache Controller | PC, IF/ID, ID/EX, EX/MEM | 1 | comb |
| wake_up | Cache Controller | 파이프라인 재개 | 1 | seq |
| instr | I-Cache Data Array | IF/ID (Decoder/ImmGen/RF) | 32 | comb |
| rs1_data | Register File | EX Operand MUX | 32 | comb |
| Data2 (rs2_data) | Register File | EX, MEM 스토어 | 32 | comb |
| imm | Immediate Generator | EX Operand MUX, Branch | 32 | comb |
| ALU Result | ALU | EX/MEM, MEM 주소, WB MUX | 32 | comb |
| pc_src/target_addr | Branch Unit | Next-PC MUX (EX→IF) | 1/32 | comb |
| Read Data | Read MUX/Aligner | MEM/WB, WB MUX | 32 | comb |
| WriteData/rd | MemtoReg MUX / WB | Register File 쓰기 (WB→ID) | 32/5 | comb |
| forward_a/forward_b | Forwarding Unit | EX Forwarding MUX, BCU | 2/2 | comb |
| EX/MEM.alu_result (bypass) | EX/MEM | EX Forwarding MUX | 32 | seq→comb |
| MEM/WB.write_data (bypass) | MEM/WB | EX Forwarding MUX | 32 | seq→comb |
| branch_taken/pc_src | BCU | Next-PC MUX (EX→IF) | 1/1 | comb |
| stall (load-use) | Hazard Unit | PC, IF/ID | 1 | comb |
| csr_rdata | CSR File | WB Result MUX | 32 | comb |
| 예외 플래그(illegal/misalign/ecall/ebreak) | 디코더·MEM·EX | Trap Unit | n | comb→seq |
| trap_taken / trap_target | Trap Unit | PC(IF), 전 파이프라인 flush | 1/32 | comb |
| fence_i / ext_inv | 디코더(FENCE.I) / 호스트 적재 | Cache Controller | 1 | comb |
| inv / iflush | Cache Controller | Tag Array(I-Cache) / 파이프라인 | 1 | comb |

> 역방향 경로는 두 가지뿐이다: **EX→IF(분기 리다이렉트)** 와 **WB→ID(레지스터 기록)**. 나머지는 좌→우 전방 흐름이다.

## 3. 데이터플로우 타이밍 규약 (입력 진입/이탈, 버퍼 판단)

- **전방 조합 체인:** 한 스테이지 내 조합 블록은 같은 사이클에 입력→출력 전파된다. 따라서 각 단의 결과는 그 사이클 말 경계 레지스터에 래치된다("입력은 사이클 시작에 유효, 출력은 사이클 말에 캡처").
- **버퍼 필요 판단:**
  - 상태가 필요한 곳에만 버퍼를 둔다: PC, Tag/Data Array(SRAM), Register File, 캐시 FSM 상태, 4개 경계 레지스터.
  - 그 외 연산(ALU, 비교, 정렬, MUX, 디코드, 즉치)은 **버퍼 없이 조합**으로 둔다 → 면적/지연 최소화.
- **파이프라인 필요 판단:** 단일 사이클 임계경로가 목표 주기(10 ns)를 초과하면 해당 스테이지를 분할(예: 캐시 접근을 별도 사이클로)한다. 본 설계는 hit 경로를 1 사이클로 두되, 임계경로 초과 시 "캐시 접근 1단 추가" 옵션을 §7에 남긴다.
- **리필 중 진입/이탈:** 미스 동안 stall로 입력(주소)을 고정 유지하고, R 데이터가 유효한(RLAST 직전까지) 사이클에만 라인에 캡처한다 → 데이터가 버스에서 유효한 순간과 캡처 순간을 일치시킨다.

## 4. 블록 다이어그램 (전체 데이터패스)

```
        IF                    ID                    EX                  MEM            WB
 ┌──────────────┐     ┌──────────────┐     ┌──────────────────┐  ┌────────────┐  ┌──────────┐
 PC─▶[Addr Aligner]   [Decoder]──ctrl────▶  [Fwd MUX a]─┐         [Addr Aligner] [Result MUX]
 │   [Tag][Data SRAM] [Reg File]─rs1/rs2─▶  [Fwd MUX b]─┴▶[ALU]─Result─▶[Tag][Data]─▶[MUX]─WriteData
 │   [Comparator]─hit [Imm Gen]──imm───────────────────────▶[BCU]─pc_src        [Read MUX/Align]│
 │   [Cache Ctrl FSM]      ▲                   ▲   │  └─target_addr──────────────────────┐       │
 └─[Next-PC MUX]◀─pc_src/target_addr◀──────────┼───┘                                     │       │
        ▲             [Hazard Unit]─stall/flush┘   ▲                                      │       │
        │             [Forwarding Unit]─forward_a/b┘  (EX/MEM.result, MEM/WB.write_data 우회)       │
        └──────────────────── WriteData/rd (WB→Reg File) ◀───────────────────────────────┴───────┘
   AXI4: I-Cache(AR/R)        D-Cache(AW/W/B/AR/R) → Zynq PS HP → DDR3L (32-bit)
   경계 레지스터: IF/ID · ID/EX · EX/MEM · MEM/WB
   바이패스: EX/MEM.alu_result, MEM/WB.write_data → Forwarding MUX → ALU·BCU 입력
```

## 5. 타이밍 다이어그램 (주요 시나리오)

클럭 주기 = 10 ns(100 MHz). 한 칸 = 1 사이클.

```
(가) 인출 Hit (정상 흐름, 1 IPC)
 cyc :  0    1    2    3
 IF  : I0   I1   I2   I3
 ID  :      I0   I1   I2
 EX  :           I0   I1
 MEM :                I0
 stall: 0    0    0    0

(나) 인출 Miss → 리필 (단일 라인, READ 버스트 4 beat)
 cyc :  0     1        2       3       4       5      6
 FSM : IDLE  SEND_AR  WAIT_R  WAIT_R  WAIT_R  WAIT_R  WAKE
 AXI :        ARVALID  R0      R1      R2      R3(LAST)
 we  :  0     0        1       1       1       1      0
 stall: 1     1        1       1       1       1      0   (PC=A 유지)

(다) 분기 성립 (EX 해소, 2-bubble)
 cyc :  0    1    2     3    4
 IF  : Br   T?   T?    Tt   Tt+1     (T? = 무효화될 not-taken 인출)
 ID  :      Br   bub   bub  Tt
 EX  :           Br→taken          → pc_src=1
 flush:          IF/ID, ID/EX

(라) 로드-유즈 해저드 (1-bubble + 포워딩)
 cyc :  0    1    2     3
 ID  : LW   USE  USE'  ...   (USE 1회 stall 후 재발행)
 EX  :      LW   bub   USE   (EX/MEM→EX 포워딩)
 stall:     1    0
```

## 6. I/O 인터페이스 속도 관점 (요약)

| 도메인 | 처리율(이론) | 비고 |
|---|---|---|
| 코어 내부 | 100 MHz × 1 IPC | 32-bit 데이터패스 |
| 메모리 AXI | 32-bit @ 100 MHz = 400 MB/s | 라인(16 B) 리필 = AR 1 + R 4 beat |
| 호스트 UART | 1 Mbps급 직렬 | 코어/메모리 대비 수백 배 느림(대량 적재 병목) |

상세 I/O 속도 정합은 Phase 4에서 확정한다.

## 7. 구조 결정 (Computation vs I/O Speed Balance)

- **임계경로 후보:** IF 단의 `Addr Aligner→Tag/Data SRAM 읽기→Comparator→(인출 게이트)` 조합 체인과 EX 단의 `Op MUX→ALU→Branch 비교` 체인. 둘 중 긴 쪽이 최대 주파수를 결정한다.
- **결정 1 (캐시 접근 단):** hit 경로를 우선 1 사이클로 둔다. 합성 타이밍에서 10 ns 미달 시, Tag/Data SRAM 읽기를 별도 사이클로 분리(IF를 2단으로)하는 대안을 보유한다.
- **결정 2 (버퍼 최소화):** 연산 블록은 전부 조합 → 경계 레지스터에서만 등록. 불필요한 내부 FIFO를 두지 않아 면적·전력 절감.
- **결정 3 (역방향 경로 길이):** EX→IF `target_addr`가 한 사이클 내 Next-PC MUX에 도달해야 하므로, Branch Unit 가산기는 ALU와 병렬(별도 가산기)로 둔다 → 분기 임계경로 단축.
- **결정 4 (I/O 정합):** 느린 UART는 코어 실행과 비동기로 분리하고, 대량 적재는 AXI 버스트로 흡수(버스트 쓰기). 세부는 Phase 4의 속도 정합에서 확정.
- **결정 5 (분기 패널티):** EX 해소·정적 not-taken으로 2-bubble 수용. ID 조기 해소는 비교기/포워딩 재설계 비용이 커 현 단계 보류.

### 7.1 구조 결정 요약

| 결정 | 내용 | 근거 |
|---|---|---|
| 캐시 접근 단 | hit 경로 1 사이클, 초과 시 2단 분리 옵션 | 임계경로 vs 10 ns 목표 |
| 버퍼 최소화 | 연산 블록 전부 조합, 경계 레지스터만 등록 | 면적·전력 절감 |
| 분기 가산기 | ALU와 병렬 별도 가산기 | EX→IF 역경로 단축 |
| I/O 분리 | 느린 UART를 코어와 비동기 분리 | 병목 흡수 |
| 분기 패널티 | EX 해소 2-bubble, 정적 not-taken | ID 조기 해소 비용 회피 |

## 8. EX 바이패스(포워딩) 네트워크 데이터플로우

데이터 해저드는 **버퍼 없이 조합 바이패스**로 무중단 해소한다. Forwarding Unit이 선택코드를 만들고, Forwarding MUX가 ALU·BCU 입력 직전에서 소스를 우회한다.

### 8.1 Forwarding Unit 선택 생성 (우선순위 EX/MEM > MEM/WB > RF)

| `forward_a` | 조건 | a 소스 |
|---|---|---|
| `10` | `EX/MEM.reg_write=1 AND EX/MEM.rd≠0 AND EX/MEM.rd=ID/EX.rs1` | EX/MEM.alu_result |
| `01` | 위 불성립 그리고 `MEM/WB.reg_write=1 AND MEM/WB.rd≠0 AND MEM/WB.rd=ID/EX.rs1` | MEM/WB.write_data |
| `00` | 그 외 | rs1_data (RF) |

`forward_b`는 ID/EX.rs2 기준으로 동일. 동일 선택이 ALU 입력과 BCU 비교 입력(`a_fwd`/`b_fwd`)에 함께 적용된다.

### 8.2 바이패스 데이터 경로(언제 들어오고 나가는가)

- **EX/MEM 우회:** 직전 명령의 `ALU Result`는 그 명령이 EX→MEM 경계를 넘은 다음 사이클, EX/MEM 레지스터에서 조합으로 끌어와 현재 EX 입력에 즉시 제공된다(1 사이클 차 의존).
- **MEM/WB 우회:** 두 사이클 차 의존은 MEM/WB.write_data에서 우회. 로드 결과(`Read Data`)도 이 경로로 전달된다.
- **버퍼 불필요:** 우회 경로는 모두 조합이므로 별도 FIFO/레지스터가 없다. 단, 임계경로에 `EX/MEM.result → Fwd MUX → ALU`가 추가되므로 §7의 타이밍 여유에 포함해 분석한다.

### 8.3 포워딩 사이클 예시

```
(연속 의존 ALU, EX/MEM 우회로 무버블)
 cyc :  0     1     2
 I0=add x1,..  : EX    MEM   WB
 I1=sub x2,x1,.:       EX    MEM     ← forward_a=10 (EX/MEM.result)
 stall : 0     0

(로드-유즈: 1 버블 + MEM/WB 우회)
 cyc :  0     1     2     3
 LW  x1 : EX    MEM   WB
 USE x1 :       ID    bub   EX        ← stall 1회, 이후 forward=01 (MEM/WB)
 stall :        1     0
```

---

## 9. 분기 해소 데이터플로우 (BCU)

BCU(Branch Comparison Unit)는 EX에서 분기를 해소하는 전담 조합 유닛이다(ALU와 분리 → 임계경로 단축).

### 9.1 BCU 입출력 경로

- **입력:** 포워딩된 `a_fwd`/`b_fwd`(비교 피연산자), `funct3`(조건), `branch`/`jump`/`is_jalr`, `pc`, `imm`, `rs1_fwd`(JALR 베이스).
- **출력:** `branch_taken`(조건 성립), `pc_src=jump OR (branch AND branch_taken)`, `target_addr=pc+imm`(JALR은 `(rs1_fwd+imm) and not 1`).
- **역경로:** `pc_src`/`target_addr`는 같은 EX 사이클에 IF Next-PC MUX로 역전파된다(EX→IF). 따라서 BCU 비교+가산+pc_src 생성은 한 사이클 내에 끝나야 한다.

### 9.2 분기 타이밍(2-bubble)

```
 cyc :  0    1     2      3     4
 IF  : Br   T?    T?     Tt    Tt+1   (T? = not-taken 추측 인출, flush 대상)
 ID  :      Br    bub    bub   Tt
 EX  :            Br→BCU(taken)        → pc_src=1, target_addr
 flush:           IF/ID, ID/EX (2 버블)
```

BCU 비교 입력에도 포워딩이 적용되므로, 분기 직전 명령 결과 의존도 무버블로 해소된다(로드-분기 의존만 1 버블).

---

## 10. 해저드 제어 전파 데이터플로우 (stall / flush)

흐름제어 신호의 **발생원 → 전파 대상 → 우선순위**를 확정한다.

| 신호 | 발생원 | 전파 대상 | 효과 |
|---|---|---|---|
| stall | Cache Controller(miss), Hazard Unit(load-use) | PC, IF/ID, ID/EX, EX/MEM | 값 유지(동결) |
| flush | BCU(분기 성립), Hazard Unit(load-use) | IF/ID, ID/EX | 제어 0 클리어(버블) |
| wake_up | Cache Controller | 파이프라인 재개 | stall 해제 |
| trap_redirect / flush_all | Trap Unit(예외/MRET) | PC, IF/ID, ID/EX, EX/MEM | PC←mtvec(MRET은 mepc), 전단 무효화 |

우선순위(경계 레지스터): `reset > trap > flush(분기) > stall > load`. 미스 stall은 상류 4개 레지스터를 동시 동결하고 MEM/WB로 버블을 주입한다. 분기 flush는 IF/ID·ID/EX를 무효화한다(2-bubble).

**트랩 데이터플로우(정밀 예외):** 예외 플래그(불법명령·정렬오류·ECALL/EBREAK)는 검출 단에서 생성되어 파이프라인 레지스터로 전달되고, WB 커밋에서 Trap Unit이 `trap_taken=1`을 확정한다. 그 사이클에 PC←`mtvec`(MRET은 `mepc`)로 리다이렉트하고 `flush_all`로 IF/ID·ID/EX·EX/MEM을 모두 비우며, 해당 명령의 부작용(RegWrite/mem_write)은 squash된다. 따라서 트랩은 분기·해저드보다 우선한다.

**I-Cache 일관성 데이터플로우(B1):** 호스트가 UART로 새 코드를 DDR에 적재하면, 적재 완료 신호가 Cache Controller의 `ext_inv`(또는 `FENCE.I`의 `fence_i`)를 1사이클 펄스로 구동한다. 그 사이클에 `inv`가 Tag Array의 전 Valid를 클리어하고 `stall`로 페치를 멈춘다. 다음 사이클 동일 PC는 miss가 되어 DDR의 **갱신된 코드**를 리필한다 → 스테일(이전 프로그램) 명령어 페치를 원천 차단. FENCE.I는 `iflush`로 이미 인출된 후속 명령까지 비운다.

---

## 11. 결론 및 다음 단계

데이터플로우·버퍼·임계경로·역방향 경로가 확정되었다. 다음 단계(Phase 4)에서 외부 블록과의 통신 프로토콜과 I/O 속도 정합을 잠근다.
