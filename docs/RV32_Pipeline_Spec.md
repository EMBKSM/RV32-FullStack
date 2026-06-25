# RV32-FullStack — RV32I 5단계 파이프라인 컴포넌트 명세서

> 프로젝트: RV32-FullStack (RISC-V RV32I 파이프라인 CPU)
> 대상 범위: 5단계 파이프라인 **IF · ID · EX · MEM · WB** 전체와 4개 경계 레지스터(IF/ID, ID/EX, EX/MEM, MEM/WB).
> 작성 기준:
> - **IF 스테이지**는 리포지토리에 구현된 실제 RTL(`ip_workspace/0_IF/`)을 기준으로 기술한다(active-high `reset`, 실제 FSM 상태명 포함).
> - **MEM 스테이지**는 브라우저 데이터패스 다이어그램(Data Cache + AXI4 Master) 기준이다.
> - **ID·EX 스테이지와 4개 파이프라인 레지스터**는 RTL이 아직 없어 표준 RV32I 관례에 따라 본 문서에서 보충한다(*보충* 표기).

---

## 0. 문서 개요

본 문서는 RV32I 5단계 파이프라인(IF·ID·EX·MEM·WB)의 각 하드웨어 블록에 대해 **포트(I/O) 목록**과 **동작(operation)** 을 RTL 구현이 가능한 수준으로 기술한다. 다이어그램상 Data Cache는 직접 사상(Direct-Mapped) 구조로 그려져 있으며(Tag Array·Comparator 각 1개), 미스(Miss) 발생 시 AXI4 Master 인터페이스(AW/W/AR/R)를 통해 Zynq PS 영역의 DDR3L 메모리로 라인을 갱신(Refill)/후기록(Write-back)한다.

### 0.1 설계 파라미터 (가정값)

이하 파라미터는 **확정값**이다. 캐시 기하구조는 구현된 `addr_aligner.vhd`의 비트 분할(tag[31:12]/idx[11:4]/offset[3:0])에서 역산된 값으로, 임의 가정이 아니라 RTL이 강제하는 값이다. 자세한 근거는 `Movement.md` §1(확정 설계 파라미터)와 일치한다.

| 파라미터 | 값 | 설명 |
|---|---|---|
| `XLEN` | 32 | 데이터/레지스터 폭 (RV32I) |
| `ADDR_WIDTH` | 32 | 물리 주소 폭 |
| `CACHE_SIZE` | 4 KB | 데이터 캐시 총 용량 |
| `LINE_BYTES` | 16 | 캐시 라인 크기 (4 word) |
| `NUM_LINES` | 256 | 라인 수 (`CACHE_SIZE / LINE_BYTES`) |
| `TAG_WIDTH` | 20 | 태그 폭 |
| `INDEX_WIDTH` | 8 | 인덱스 폭 |
| `OFFSET_WIDTH` | 4 | 라인 내 오프셋 폭 |
| 사상 방식 | Direct-Mapped | Tag Array/Comparator 각 1개 (IF I-Cache·MEM D-Cache 공통 구조) |
| 쓰기 정책 | Write-Back + Write-Allocate | Dirty 비트 사용 |

### 0.2 주소 비트 필드 분해

`ALU Result`(접근 주소) 32비트는 Address Aligner에서 다음과 같이 분해된다.

```
 31                12 11        4 3   2 1   0
+--------------------+-----------+-----+-----+
|       Tag (20)     | Index (8) | WO  | BO  |
+--------------------+-----------+-----+-----+
  [31:12]              [11:4]      [3:2] [1:0]
```

- **Tag** `[31:12]` : Tag Array에 저장/비교되는 식별자
- **Index** `[11:4]` : Tag Array·Data Array의 라인 선택 인덱스
- **WO (Word Offset)** `[3:2]` : 라인 내 4개 워드 중 1개 선택 (Read MUX/Aligner)
- **BO (Byte Offset)** `[1:0]` : 워드 내 바이트 위치 (LB/LH/SB/SH 정렬에 사용)

### 0.3 신호 표기 규칙

- 방향: `In`(입력) / `Out`(출력) / `I/O`(양방향 없음, 본 설계는 단방향만 사용)
- 비트폭은 `[MSB:LSB]` 또는 비트 수로 표기, 단일 비트는 `1`
- AXI4 신호는 AMBA AXI4 표준 접두어(`AW/W/B/AR/R`)를 따른다.
- 리셋: 프로젝트 RTL 관례에 맞춰 **active-high `reset`** 을 사용한다(모든 `.vhd` 모듈이 `reset='1'` 기준). 비동기 리셋으로 가정.

---

## 1. 파이프라인 전체 개요

```
       IF             ID             EX            MEM            WB
 ┌────────────┐ ┌───────────┐ ┌───────────┐ ┌────────────┐ ┌──────────┐
 │ PC / I-Cache│▶│ Decode/RF │▶│ ALU/Branch│▶│ D-Cache/AXI│▶│ MemtoReg │
 └────────────┘ └───────────┘ └───────────┘ └────────────┘ └──────────┘
       │ IF/ID       │ ID/EX      │ EX/MEM       │ MEM/WB       │
   ▲ pc_src/target_addr (EX→IF 분기 리다이렉트)   ▼ WriteData/rd (WB→ID 기록)
```

| 스테이지 | 핵심 기능 | 주요 컴포넌트 | 출력 경계 레지스터 |
|---|---|---|---|
| IF | 명령어 인출 | PC Reg, PC Adder, Next-PC MUX, I-Cache(Addr Aligner·Tag Array·Comparator·Cache Controller·AXI AR/R) | IF/ID |
| ID | 해독·레지스터 읽기·즉치 생성 | Control Unit, Register File, Immediate Generator, **CSR File**, 불법명령 검출 | ID/EX |
| EX | 연산·분기 판정·해저드 해소·예외 검출 | ALU, ALU Control, ALUSrc MUX, **BCU**, **Forwarding Unit**, **Hazard Unit**, **Trap/Exception Unit** | EX/MEM |
| MEM | 데이터 메모리 접근 | Data Cache, AXI4 Master(AW/W/AR/R/B) | MEM/WB |
| WB | 결과 레지스터 기록·트랩 커밋 | WB Result MUX, Register File 쓰기 포트, **Trap 커밋(MRET/예외)** | — |

제어/데이터 해저드는 §12에 요약한다. 분기는 EX 스테이지에서 해소되는 것으로 가정한다(§13).

---

## 2. IF (Instruction Fetch) 스테이지  *(실제 RTL 기준)*

PC를 관리하고 명령어 캐시에서 명령어를 인출한다. PC 유닛과 캐시 프론트엔드는 실제 VHDL(`ip_workspace/0_IF/`)과 포트가 일치한다. 명령어 데이터 어레이·AXI 마스터 배선은 아직 RTL에 없어 *보충*으로 표기한다.

### 2.1 PC Register (`pc_reg`, `program_counter.vhd`)

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `clk` | In | 1 | 클럭 |
| `reset` | In | 1 | 비동기 리셋(active-high) → PC=`RESET_ADDR` |
| `stall` | In | 1 | 1이면 PC 유지(미스 등 동결) |
| `next_pc` | In | 32 | 다음 PC (Next-PC MUX) |
| `pc` | Out | 32 | 현재 PC → PC Adder, I-Cache 주소 |

Generic `RESET_ADDR := x"00000000"`. **동작:** `reset=1`→`RESET_ADDR`; 그 외 상승 엣지에 `stall=0`일 때만 `pc<=next_pc`.

### 2.2 PC Adder (`pc_adder`)

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `pc_in` | In | 32 | 현재 PC |
| `pc_out` | Out | 32 | `pc_in + 4` → Next-PC MUX, IF/ID 링크값 |

### 2.3 Next-PC MUX (`next_pc_mux`)

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `pc_plus_4` | In | 32 | 순차 주소 |
| `target_addr` | In | 32 | 분기/점프 타겟 (EX) |
| `pc_src` | In | 1 | 1이면 타겟 선택 |
| `next_pc` | Out | 32 | `pc_src ? target_addr : pc_plus_4` |

### 2.4 Instruction Cache (I-Cache)

Direct-Mapped **읽기 전용** 명령어 캐시. 미스 시 AXI4 `AR/R`로 리필(쓰기/Dirty/Write-Back 없음). 주소 분해는 §0.2와 동일.

#### 2.4.1 Address Aligner (`addr_aligner`)

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `address` | In | 32 | 접근 주소(=PC) |
| `tag` | Out | 20 | `address[31:12]` |
| `idx` | Out | 8 | `address[11:4]` |
| `offset` | Out | 4 | `address[3:0]` |

#### 2.4.2 Tag Array (`tag_array`)

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `clk` | In | 1 | 클럭 |
| `reset` | In | 1 | active-high → 전 라인 Valid 0 클리어 |
| `we` | In | 1 | 리필 태그/Valid 기록 enable |
| `inv` | In | 1 | **I-Cache 무효화**: 전 라인 Valid 단일 사이클 클리어(`we`보다 우선) |
| `idx` | In | 8 | 라인 선택 |
| `tag_in` | In | 20 | 리필 태그 |
| `tag_out` | Out | 20 | 저장 태그 → Comparator |
| `valid_out` | Out | 1 | 유효 비트 → Comparator |

**동작:** 비동기 읽기/동기 쓰기. `inv=1`이면 상승 엣지에 전 라인 Valid를 0으로 클리어(코드 적재/`FENCE.I` 일관성, B1). I-Cache이므로 Dirty 없음.

#### 2.4.3 Comparator (`comparator`)

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `addr_tag` | In | 20 | 요청 태그 |
| `cache_tag` | In | 20 | 저장 태그 |
| `valid_bit` | In | 1 | 라인 Valid |
| `hit` | Out | 1 | `valid_bit and (addr_tag = cache_tag)` |

**동작:** 유효성·태그 일치를 한 블록에서 결합(MEM의 Comparator+AND 분리 구조와 달리 RTL은 통합형).

#### 2.4.4 Cache Controller (`cache_controller`, FSM)

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `clk`, `reset` | In | 1 | 클럭/리셋 |
| `miss` | In | 1 | `fetch and not hit` |
| `fence_i` | In | 1 | `FENCE.I` 무효화 요청(1-cycle 펄스) |
| `ext_inv` | In | 1 | 호스트 코드적재 무효화 요청(1-cycle 펄스) |
| `stall` | Out | 1 | 미스/무효화 동안 PC/IF/ID 동결 |
| `wake_up` | Out | 1 | 리필 완료·재개 펄스 |
| `we` | Out | 1 | Tag/Data Array 쓰기 enable |
| `inv` | Out | 1 | Tag Array 무효화(전 Valid 클리어) |
| `iflush` | Out | 1 | `FENCE.I` 시 파이프라인 flush |
| `arready` | In | 1 | 읽기 주소 수락 |
| `rvalid` | In | 1 | 읽기 데이터 유효 |
| `arvalid` | Out | 1 | 읽기 주소 발행 |
| `rready` | Out | 1 | 읽기 데이터 수신 준비 |

**FSM 상태(실제 RTL):**

| 상태 | 설명 | 전이 |
|---|---|---|
| `S_IDLE` | Hit 대기 | `miss=1` → `S_SEND_AR` |
| `S_SEND_AR` | 읽기 주소 전송 | `arready=1` → `S_WAIT_R` |
| `S_WAIT_R` | 읽기 데이터 대기 | `rvalid=1` → `S_UPDATE_CACHE` |
| `S_UPDATE_CACHE` | SRAM 기록 | → `S_WAKE_UP` |
| `S_WAKE_UP` | `Stall` 해제 | → `S_IDLE` |

**동작:** 미스 동안 `stall=1`. `we`는 데이터가 유효한 `S_WAIT_R`의 `rvalid` 비트에 맞춰 구동(검증으로 적용된 캡처 타이밍).

#### 2.4.5 Instruction Data Array (SRAM) *(보충 — RTL 미구현)*

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `clk` | In | 1 | 클럭 |
| `idx` | In | 8 | 라인 선택 |
| `offset` | In | 4 | 라인 내 워드 |
| `we`, `line_fill` | In | 1 | 리필 enable/버스트 |
| `refill_data` | In | 32 | R Master 데이터 |
| `instr_out` | Out | 32 | 인출 명령어 → IF/ID |

#### 2.4.6 AXI4 AR/R Master (읽기 전용) *(보충 — RTL 미구현)*

읽기 주소(`ARADDR/ARLEN/ARSIZE/ARBURST/ARVALID/ARREADY`)·읽기 데이터(`RDATA/RRESP/RLAST/RVALID/RREADY`) 채널로 라인을 인출한다. 신호 정의는 §8.9.1/8.9.2의 AR/R과 동일.

---

## 3. IF/ID 파이프라인 레지스터  *(보충)*

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `clk`, `reset` | In | 1 | 클럭/리셋 |
| `stall` | In | 1 | 동결(미스/로드-유즈) |
| `flush` | In | 1 | 분기 성립 시 무효화(버블) |
| `pc_i` / `pc_o` | In/Out | 32 | PC 통과(분기 타겟 계산용) |
| `pc_plus4_i` / `pc_plus4_o` | In/Out | 32 | PC+4(JAL/JALR 링크값) |
| `instr_i` / `instr_o` | In/Out | 32 | 인출 명령어 → ID |

**동작:** 상승 엣지 래치. `stall`=유지, `flush`=`instr_o`를 NOP(`0x00000013`)로 치환.

---

## 4. ID (Instruction Decode) 스테이지  *(보충)*

명령어를 해독해 제어 신호를 만들고, 레지스터 두 소스를 읽으며, 즉치를 추출한다.

### 4.1 명령어 필드 추출 (조합)

| 필드 | 비트 | 용도 |
|---|---|---|
| `opcode` | `instr[6:0]` | 명령어 클래스 |
| `rd` | `instr[11:7]` | 목적지 |
| `funct3` | `instr[14:12]` | 연산/분기/접근 종류 |
| `rs1` | `instr[19:15]` | 소스1 번호 |
| `rs2` | `instr[24:20]` | 소스2 번호 |
| `funct7` | `instr[31:25]` | R-type 구분(특히 `funct7[5]`) |

### 4.2 Control Unit (Decoder)

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `opcode` | In | 7 | `instr[6:0]` |
| `reg_write` | Out | 1 | 레지스터 기록(→WB) |
| `mem_read` | Out | 1 | 로드 |
| `mem_write` | Out | 1 | 스토어 |
| `mem_to_reg` | Out | 1 | WB 소스(1=메모리) |
| `alu_src` | Out | 1 | ALU B(1=즉치) |
| `branch` | Out | 1 | 조건 분기 |
| `jump` | Out | 1 | 점프(JAL/JALR) |
| `alu_op` | Out | 2 | ALU Control 1차 코드 |

**제어 신호 표(주요 opcode, 인코딩 예시):**

| 클래스 | opcode | reg_write | alu_src | mem_read | mem_write | mem_to_reg | branch | jump | alu_op |
|---|---|---|---|---|---|---|---|---|---|
| R-type | `0110011` | 1 | 0 | 0 | 0 | 0 | 0 | 0 | `10` |
| I-ALU | `0010011` | 1 | 1 | 0 | 0 | 0 | 0 | 0 | `10` |
| Load | `0000011` | 1 | 1 | 1 | 0 | 1 | 0 | 0 | `00` |
| Store | `0100011` | 0 | 1 | 0 | 1 | 0 | 0 | 0 | `00` |
| Branch | `1100011` | 0 | 0 | 0 | 0 | 0 | 1 | 0 | `01` |
| JAL | `1101111` | 1 | 0 | 0 | 0 | 0 | 0 | 1 | `00` |
| JALR | `1100111` | 1 | 1 | 0 | 0 | 0 | 0 | 1 | `00` |
| LUI | `0110111` | 1 | 1 | 0 | 0 | 0 | 0 | 0 | `11` |
| AUIPC | `0010111` | 1 | 1 | 0 | 0 | 0 | 0 | 0 | `00` |
| SYSTEM-CSR | `1110011` | 1 | 0 | 0 | 0 | 0 | 0 | 0 | `00` |
| SYSTEM-Trap | `1110011` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | `00` |
| FENCE | `0001111` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | `00` |
| (default) Illegal | 그 외 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | `00` |

> `alu_op`(`00`=ADD, `01`=SUB/비교, `10`=funct 디코드, `11`=B 패스)은 설계 정의값이며 §6.2와 짝을 이룬다. JAL/LUI/AUIPC의 WB 값 경로(PC+4 / imm / PC+imm)는 §6·§10에서 처리.

#### 4.2.1 SYSTEM / FENCE 디코드 및 신규 제어 신호

`SYSTEM`(`1110011`)은 `funct3`로, `FENCE`(`0001111`)는 `funct3`로 세분된다. 추가 제어 신호: `csr_to_reg`, `csr_we`, `csr_cmd[1:0]`, `csr_use_imm`, `is_ecall`, `is_ebreak`, `is_mret`, `is_fence_i`, `illegal_instr`.

| funct3 | 식별자 | 명령 | 동작(요지) |
|---|---|---|---|
| `000` | imm=`0x000` | ECALL | 예외 발생(cause 11, M-mode 환경호출) |
| `000` | imm=`0x001` | EBREAK | 예외 발생(cause 3, 브레이크포인트) |
| `000` | `0x302`(funct7=0011000,rs2=2) | MRET | `mstatus` 복원, PC←`mepc` |
| `000` | `0x105` | WFI | (옵션) NOP/대기 |
| `001` | csr=instr[31:20] | CSRRW | `csr ↔ rs1_data` |
| `010` | csr | CSRRS | `csr = csr OR rs1_data` (set) |
| `011` | csr | CSRRC | `csr = csr AND NOT rs1_data` (clear) |
| `101` | csr | CSRRWI | `csr ↔ zimm(rs1 필드 5b 0확장)` |
| `110` | csr | CSRRSI | set, zimm |
| `111` | csr | CSRRCI | clear, zimm |

| opcode/funct3 | 명령 | 동작 |
|---|---|---|
| `0001111`/`000` | FENCE | 메모리 순서(단순 인오더 코어는 NOP, 단 디코드는 필수) |
| `0001111`/`001` | FENCE.I | I-Cache 무효화(코드 적재 일관성, B1) |

**불법 명령(Illegal) 검출:** 위 유효 인코딩에 매칭되지 않는 모든 opcode/`funct3`/`funct7` 조합은 `illegal_instr=1` 로 디코드되어 트랩(§6.7, cause 2)을 발생시킨다.

### 4.3 Register File

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `clk` | In | 1 | 클럭 |
| `reg_write` | In | 1 | 기록 enable(WB) |
| `rs1` | In | 5 | 소스1 주소 |
| `rs2` | In | 5 | 소스2 주소 |
| `rd` | In | 5 | 기록 주소(WB) |
| `wd` (`WriteData`) | In | 32 | 기록 데이터(WB) |
| `rs1_data` | Out | 32 | 소스1 값 → ID/EX |
| `rs2_data` (`Data2`) | Out | 32 | 소스2 값 → ID/EX(스토어 데이터) |

**동작:** 32×32b, `x0`=0(기록 무시). 쓰기는 WB, 읽기는 ID 조합. 동시 RAW는 write-first 또는 EX 포워딩으로 해소(§12).

### 4.4 Immediate Generator

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `instr` | In | 32 | 명령어 |
| `imm_sel` | In | 3 | 포맷 선택(opcode 파생) |
| `imm` | Out | 32 | 부호확장 즉치 → ID/EX |

**포맷별 즉치(부호확장 `instr[31]` 기준):**

| 포맷 | 사용 명령 | 즉치 구성 |
|---|---|---|
| I | I-ALU, Load, JALR | `instr[31:20]` |
| S | Store | `instr[31:25]` + `instr[11:7]` |
| B | Branch | `instr[31]`,`instr[7]`,`instr[30:25]`,`instr[11:8]`,`0` |
| U | LUI, AUIPC | `instr[31:12]` + 하위 `0` 12b |
| J | JAL | `instr[31]`,`instr[19:12]`,`instr[20]`,`instr[30:21]`,`0` |

### 4.5 (옵션) Load-Use 해저드 검출

`ID/EX.mem_read`와 ID의 `rs1/rs2` 일치 시 1 사이클 버블이 필요하다. Hazard Unit이 `stall`(PC·IF/ID 유지)+`ID/EX flush`를 발생시킨다. 상세 §12. *(RTL 미구현)*

---

### 4.6 CSR File (Machine-mode, Zicsr)

머신모드 제어·상태 레지스터 파일. CSR 읽기는 조합(레지스터 파일처럼), 쓰기·부작용은 WB 커밋에서 반영. 트랩 시 Trap Unit이 `mepc/mcause/mtval/mstatus`를 갱신한다.

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `clk`, `reset` | In | 1 | 클럭/리셋(리셋 시 `mstatus.MIE=0` 등 안전값) |
| `csr_addr` | In | 12 | `instr[31:20]` |
| `csr_cmd` | In | 2 | `00`=none, `01`=RW, `10`=RS, `11`=RC |
| `csr_wdata` | In | 32 | `rs1_data` 또는 `zimm` |
| `csr_we` | In | 1 | CSR 쓰기 enable(부작용 억제 규칙 반영) |
| `csr_rdata` | Out | 32 | 읽은 CSR → WB(`csr_to_reg`) |
| `trap_we`(mepc/mcause/mtval/mstatus) | In | — | Trap Unit가 트랩/MRET 시 갱신 |
| `mstatus`, `mtvec`, `mepc` | Out | 32 | Trap Unit로 공급 |

**최소 머신모드 CSR 집합:**

| CSR | 주소 | 역할 |
|---|---|---|
| `mstatus` | `0x300` | MIE/MPIE/MPP 등 상태 |
| `misa` | `0x301` | RO, RV32I 식별 |
| `mie` | `0x304` | 인터럽트 enable |
| `mtvec` | `0x305` | 트랩 벡터 base/mode |
| `mscratch` | `0x340` | 임시 저장 |
| `mepc` | `0x341` | 예외 복귀 PC |
| `mcause` | `0x342` | 트랩 원인 |
| `mtval` | `0x343` | 트랩 부가값(주소/명령) |
| `mip` | `0x344` | 인터럽트 pending |
| `mhartid` | `0xF14` | RO, 0 |

**CSR 접근 부작용 규칙:** CSRRW에서 `rd=x0`이면 읽기 부작용 억제, CSRRS/CSRRC에서 `rs1=x0`(또는 `zimm=0`)이면 쓰기 억제. `csr_we`는 이 규칙을 반영해 생성한다.

## 5. ID/EX 파이프라인 레지스터  *(보충)*

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `clk`, `reset`, `stall`, `flush` | In | 1 | 제어 |
| `pc` / `pc_plus4` | In/Out | 32 | 분기 타겟·링크값 |
| `rs1_data` | In/Out | 32 | ALU A 후보 |
| `rs2_data` (`Data2`) | In/Out | 32 | ALU B 후보/스토어 데이터 |
| `imm` | In/Out | 32 | 즉치 |
| `rs1` / `rs2` | In/Out | 5 | 포워딩 비교용 소스 번호 |
| `rd` | In/Out | 5 | 목적지 |
| `funct3` | In/Out | 3 | ALU/분기/접근 종류 |
| `funct7_5` | In/Out | 1 | `instr[30]` |
| 제어 신호 | In/Out | — | `reg_write, mem_read, mem_write, mem_to_reg, alu_src, branch, jump, alu_op` |

**동작:** 상승 엣지 래치. `flush`=제어 신호 0 클리어(버블).

---

## 6. EX (Execute) 스테이지  *(보충)*

ALU 연산과 분기 판정을 수행하고 결과(`ALU Result`)·스토어 데이터(`Data2`)·분기 신호(`pc_src`/`target_addr`)를 만든다.

### 6.1 ALU

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `a` | In | 32 | 피연산자 A(rs1_data 또는 PC) |
| `b` | In | 32 | 피연산자 B(rs2_data 또는 imm) |
| `alu_ctrl` | In | 4 | 연산 선택 |
| `result` (`ALU Result`) | Out | 32 | 결과 → EX/MEM |
| `zero` | Out | 1 | `result=0` 플래그 |

**연산 표(`alu_ctrl`, 인코딩 예시):**

| `alu_ctrl` | 연산 | `alu_ctrl` | 연산 |
|---|---|---|---|
| `0000` | ADD | `0101` | SLL |
| `0001` | SUB | `0110` | SRL |
| `0010` | AND | `0111` | SRA |
| `0011` | OR | `1000` | SLT (signed) |
| `0100` | XOR | `1001` | SLTU (unsigned) |

### 6.2 ALU Control

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `alu_op` | In | 2 | Control Unit 1차 코드 |
| `funct3` | In | 3 | `instr[14:12]` |
| `funct7_5` | In | 1 | `instr[30]` |
| `alu_ctrl` | Out | 4 | ALU 연산 선택 |

**디코드:** `alu_op=00`→ADD(주소), `01`→SUB(비교), `11`→B 패스(LUI), `10`→`funct3`(+`funct7_5`로 ADD/SUB·SRL/SRA 구분).

### 6.3 Operand MUX

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `src_a_sel` | In | 1 | A 선택(0=rs1_data, 1=PC) |
| `alu_src` | In | 1 | B 선택(0=rs2_data, 1=imm) |
| `a` / `b` | Out | 32 | ALU 입력 |

### 6.4 BCU (Branch Comparison Unit)

EX 스테이지의 **분기 해소 전담 조합 유닛**. 포워딩된 두 피연산자를 `funct3` 조건으로 비교(ALU와 분리된 전용 비교기)하여 분기 성립을 판정하고, 타겟과 `pc_src`를 생성하여 IF로 역전파한다. ALU와 분리함으로써 EX 임계경로를 단축한다.

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `a_fwd` | In | 32 | 포워딩된 rs1_data (비교 피연산자) |
| `b_fwd` | In | 32 | 포워딩된 rs2_data (비교 피연산자) |
| `pc` | In | 32 | 분기 기준 PC |
| `imm` | In | 32 | 분기/점프 오프셋 |
| `rs1_fwd` | In | 32 | JALR 베이스(포워딩된 rs1) |
| `funct3` | In | 3 | 분기 조건 |
| `branch` | In | 1 | 조건 분기 |
| `jump` | In | 1 | 무조건 점프 |
| `is_jalr` | In | 1 | JALR 구분(타겟 하위 비트 클리어) |
| `branch_taken` (`cond_met`) | Out | 1 | 분기 조건 성립 |
| `pc_src` | Out | 1 | `jump OR (branch AND branch_taken)` → IF Next-PC MUX |
| `target_addr` | Out | 32 | `pc+imm` (JALR은 `(rs1_fwd+imm) and not 1`) → IF |

**분기 조건(`funct3`):**

| `funct3` | 분기 | 성립 조건 |
|---|---|---|
| `000` | BEQ | `a_fwd = b_fwd` |
| `001` | BNE | `a_fwd ≠ b_fwd` |
| `100` | BLT | `a_fwd < b_fwd` (signed) |
| `101` | BGE | `a_fwd ≥ b_fwd` (signed) |
| `110` | BLTU | `a_fwd < b_fwd` (unsigned) |
| `111` | BGEU | `a_fwd ≥ b_fwd` (unsigned) |

### 6.5 Forwarding Unit & Forwarding MUX

데이터 해저드를 무중단 해소하는 **EX 바이패스 네트워크**. **Forwarding Unit**(조합)이 후속 스테이지의 목적지와 현재 EX 소스를 비교해 선택코드를 생성하고, **Forwarding MUX**가 ALU·BCU 입력 직전에서 소스를 우회 선택한다.

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `id_ex_rs1` / `id_ex_rs2` | In | 5 | 현재 EX 소스 번호 |
| `ex_mem_rd` | In | 5 | EX/MEM 목적지 |
| `ex_mem_reg_write` | In | 1 | EX/MEM 기록 enable |
| `mem_wb_rd` | In | 5 | MEM/WB 목적지 |
| `mem_wb_reg_write` | In | 1 | MEM/WB 기록 enable |
| `forward_a` / `forward_b` | Out | 2 | `00`=RF, `10`=EX/MEM, `01`=MEM/WB |

**생성 규칙(우선순위 EX/MEM > MEM/WB > RF):**

| `forward_a` | 조건 |
|---|---|
| `10` | `ex_mem_reg_write=1 AND ex_mem_rd≠0 AND ex_mem_rd=id_ex_rs1` |
| `01` | 위 불성립 그리고 `mem_wb_reg_write=1 AND mem_wb_rd≠0 AND mem_wb_rd=id_ex_rs1` |
| `00` | 그 외(레지스터 파일 값) |

`forward_b`는 `id_ex_rs2` 기준으로 동일하게 결정한다. 출력은 BCU 비교 입력(`a_fwd`/`b_fwd`)에도 동일하게 적용된다.

### 6.6 Hazard Unit (Load-Use 검출)

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `id_ex_mem_read` | In | 1 | 직전 명령이 로드 |
| `id_ex_rd` | In | 5 | 로드 목적지 |
| `if_id_rs1` / `if_id_rs2` | In | 5 | 현재 ID 소스 |
| `stall` | Out | 1 | PC·IF/ID 동결(1-bubble) |
| `flush` | Out | 1 | ID/EX 버블 |

조건: `id_ex_mem_read=1 AND id_ex_rd≠0 AND (id_ex_rd=if_id_rs1 OR id_ex_rd=if_id_rs2)` → `stall=1`, `flush=1`.

EX 종료 시 결과·제어는 §7 EX/MEM 레지스터로 래치된다.

---

### 6.7 Trap & Exception Unit (Machine-mode)

예외를 검출하고 정밀(precise) 트랩을 일으키는 유닛. 예외 플래그는 검출 단에서 생성되어 파이프라인 레지스터로 전달되고, **WB 커밋 시점**에 트랩이 확정되어 후속 단을 모두 flush 한다(정밀 예외 보장). `MRET`은 복귀를 수행한다.

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `illegal_instr` | In | 1 | 불법 명령(디코더) |
| `instr_misalign` | In | 1 | 명령 주소 정렬오류(타겟 4B 위반) |
| `load_misalign` / `store_misalign` | In | 1 | 데이터 주소 정렬오류 |
| `is_ecall` / `is_ebreak` | In | 1 | 환경호출/브레이크 |
| `is_mret` | In | 1 | 트랩 복귀 |
| `instr_pc` | In | 32 | 예외 명령 PC(→`mepc`) |
| `fault_addr` | In | 32 | `mtval`용 주소/명령 |
| `mstatus`, `mtvec`, `mepc` | In | 32 | CSR 현재값 |
| `trap_taken` | Out | 1 | 트랩 진입 |
| `trap_target` | Out | 32 | `mtvec`(예외) 또는 `mepc`(MRET) |
| `flush_all` | Out | 1 | IF/ID·ID/EX·EX/MEM 비움 |
| CSR 갱신(mepc/mcause/mtval/mstatus) | Out | — | CSR File로 |

**예외 원인(`mcause`) 표:**

| cause | 예외 |
|---|---|
| `0` | 명령 주소 정렬오류 |
| `2` | 불법 명령 |
| `3` | 브레이크포인트(EBREAK) |
| `4` | 로드 주소 정렬오류 |
| `6` | 스토어 주소 정렬오류 |
| `11` | 환경호출 ECALL(M-mode) |
| MSB=1 | 인터럽트(예: `7`=머신 타이머) |

**트랩 진입 시퀀스:** `mepc←instr_pc`, `mcause←cause`, `mtval←fault_addr`, `mstatus.MPIE←MIE`, `mstatus.MIE←0`, `mstatus.MPP←11`, `PC←mtvec.BASE`, `flush_all=1`.
**MRET:** `mstatus.MIE←MPIE`, `MPIE←1`, `MPP←00`, `PC←mepc`, `flush_all=1`.

## 7. EX/MEM 파이프라인 레지스터  *(다이어그램 외 — 본 문서 보충)*

EX 스테이지 종료 시점의 연산 결과와 제어 신호를 한 클럭 래치하여 MEM 스테이지로 전달한다. 클럭 상승 엣지 동기, `flush` 시 제어 신호를 0(NOP)으로 클리어, `stall` 시 값을 유지(freeze)한다.

### 7.1 포트 목록

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `clk` | In | 1 | 클럭 |
| `reset` | In | 1 | 비동기 리셋 (active-high, 프로젝트 관례) |
| `stall` | In | 1 | 1이면 현재 값 유지 (Cache Controller의 `Stall`과 연결) |
| `flush` | In | 1 | 1이면 제어 신호를 NOP으로 클리어 (버블 삽입) |
| **데이터 입력 (EX단)** | | | |
| `alu_result_i` | In | 32 | ALU 연산 결과 = 메모리 접근 주소 |
| `data2_i` | In | 32 | rs2 레지스터 값 = 스토어 저장 데이터 |
| `rd_i` | In | 5 | 목적지 레지스터 번호 |
| `funct3_i` | In | 3 | 로드/스토어 종류 (LB/LH/LW/LBU/LHU, SB/SH/SW) |
| **제어 입력 (EX단)** | | | |
| `mem_read_i` | In | 1 | 메모리 읽기 (로드) |
| `mem_write_i` | In | 1 | 메모리 쓰기 (스토어) |
| `reg_write_i` | In | 1 | 레지스터 파일 기록 enable |
| `mem_to_reg_i` | In | 1 | WB 데이터 소스 선택 (1=메모리, 0=ALU) |
| **출력 (MEM단으로)** | | | |
| `alu_result_o` | Out | 32 | → Address Aligner, MemtoReg MUX(In2) |
| `data2_o` | Out | 32 | → Data Cache 쓰기 데이터 / W Master |
| `rd_o` | Out | 5 | → MEM/WB 레지스터 |
| `funct3_o` | Out | 3 | → Read MUX/Aligner, 쓰기 스트로브 생성 |
| `mem_read_o` | Out | 1 | → Cache Controller (`MemRead`) |
| `mem_write_o` | Out | 1 | → Cache Controller (`MemWrite`) |
| `reg_write_o` | Out | 1 | → MEM/WB 레지스터 |
| `mem_to_reg_o` | Out | 1 | → MEM/WB 레지스터 |

### 7.2 동작

- 매 클럭 상승 엣지에 입력을 출력 래치한다.
- `stall=1` (캐시 미스 등): 모든 필드 값을 그대로 유지하여 진행 중인 메모리 트랜잭션이 깨지지 않도록 한다.
- `flush=1`: `mem_read_o/mem_write_o/reg_write_o/mem_to_reg_o` 등 제어 신호를 0으로 클리어하여 부작용 없는 버블을 만든다(데이터 필드는 don't-care).

---

## 8. Memory Access (MEM) 스테이지

다이어그램의 MEM 영역은 (a) **Data Cache** 서브시스템과 (b) **AXI4 Master** 인터페이스로 구성된다.

### 8.1 Data Cache (최상위 그룹)

Direct-Mapped, Write-Back/Write-Allocate 데이터 캐시. 내부에 Address Aligner, Tag Array, Data Array(SRAM), Comparator, Hit 판정 게이트, Cache Controller, Read MUX/Aligner를 포함한다.

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `clk`, `reset` | In | 1 | 클럭/리셋 |
| `addr` (`ALU Result`) | In | 32 | 접근 주소 |
| `wdata` (`Data2`) | In | 32 | 스토어 데이터 |
| `funct3` | In | 3 | 접근 크기/부호 |
| `mem_read` (`MemRead`) | In | 1 | 로드 요청 |
| `mem_write` (`MemWrite`) | In | 1 | 스토어 요청 |
| `read_data` (`Read Data`) | Out | 32 | 정렬·부호확장된 로드 결과 → MEM/WB |
| `hit` (`Hit`) | Out | 1 | 캐시 히트 여부 |
| `stall` (`Stall`) | Out | 1 | 미스 시 파이프라인 동결 요청 |
| **AXI4 Master 측** | | | (8.9 참조) |

이하 8.2~8.9에서 내부 블록을 개별 명세한다.

### 8.2 Address Aligner

접근 주소를 캐시 인덱싱용 필드(Tag/Index/Offset)로 분해한다. (이름이 동일한 "Read MUX/Aligner"와 역할이 다름에 유의: 이쪽은 *주소 분해*, 그쪽은 *데이터 정렬*.)

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `addr_i` (`ALU Result`) | In | 32 | 접근 주소 |
| `tag_o` (`Tag`) | Out | 20 | `addr_i[31:12]` → Comparator |
| `index_o` (`Idx`) | Out | 8 | `addr_i[11:4]` → Tag/Data Array |
| `word_off_o` | Out | 2 | `addr_i[3:2]` → Read MUX/Aligner |
| `byte_off_o` | Out | 2 | `addr_i[1:0]` → 바이트 정렬/스트로브 |

**동작:** 순수 조합 논리(배선 슬라이싱). 비정렬 접근 검출이 필요하면 `funct3` 와 `byte_off` 를 비교하여 misalign 예외 플래그를 추가 출력할 수 있다(옵션).

### 8.3 Tag Array

각 라인의 태그와 상태 비트(Valid/Dirty)를 저장하는 SRAM/레지스터 배열.

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `clk` | In | 1 | 클럭 |
| `reset` | In | 1 | 비동기 리셋 — 전 라인 Valid 비트를 0으로 클리어 |
| `index` (`Idx`) | In | 8 | 라인 선택 |
| `tag_in` | In | 20 | Refill 시 기록할 태그 (Cache Controller) |
| `valid_in` | In | 1 | Refill 시 Valid 설정 |
| `dirty_in` | In | 1 | 스토어/후기록 시 Dirty 갱신 |
| `we` | In | 1 | 태그/상태 기록 enable (Controller) |
| `tag_out` (`Tag`) | Out | 20 | 선택 라인의 저장 태그 → Comparator |
| `valid_out` | Out | 1 | 선택 라인 유효 비트 → Hit 게이트 |
| `dirty_out` | Out | 1 | 선택 라인 Dirty 비트 → Controller(후기록 판단) |

**동작:** `reset=1` 시 전 라인 Valid 를 0으로 클리어한다. 평상시 `index` 로 한 라인을 읽어 `tag_out/valid_out/dirty_out` 을 제공. 미스 처리(Refill) 시 Controller가 `we` 로 새 태그/Valid/Dirty를 기록한다.

### 8.4 Data Array (SRAM)

실제 캐시 데이터(라인당 16바이트 = 4워드)를 저장하는 SRAM 블록.

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `clk` | In | 1 | 클럭 |
| `index` (`Idx`) | In | 8 | 라인 선택 |
| `word_off` | In | 2 | 라인 내 워드 선택 |
| `wdata` (`Data2`) | In | 32 | 스토어/Refill 기록 데이터 |
| `wstrb` | In | 4 | 바이트 단위 쓰기 스트로브 (SB/SH/SW) |
| `we` | In | 1 | 쓰기 enable (스토어 hit 또는 Refill) |
| `line_fill` | In | 1 | 1이면 라인 전체(버스트) 기록 모드 |
| `rdata` | Out | 128 | (Refill/라인 단위 접근 시) 선택 라인 전체 4워드 |
| `word_out` | Out | 32 | (로드 시) `word_off` 로 선택된 1워드 → Read MUX/Aligner |

**동작:**
- **로드:** `index`+`word_off` 로 해당 워드를 읽어 `word_out` 으로 출력.
- **스토어(hit):** `wstrb` 로 지정된 바이트만 갱신, 해당 라인 Dirty=1.
- **Refill:** R Master가 가져온 버스트 데이터를 `line_fill` 모드로 라인 전체에 채운다.

### 8.5 Comparator (태그 비교기)

Address Aligner의 요청 태그와 Tag Array의 저장 태그를 비교한다.

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `tag_req` (`Tag`) | In | 20 | 요청 주소의 태그 |
| `tag_stored` | In | 20 | Tag Array가 출력한 저장 태그 |
| `match_o` | Out | 1 | `tag_req == tag_stored` 일 때 1 |

**동작:** 조합 논리 등가 비교(`==`). 결과 `match_o` 는 Hit 판정 AND 게이트로 전달된다.

### 8.6 Hit 판정 게이트 (AND)

태그 일치와 라인 유효성을 결합하여 최종 `Hit` 를 만든다.

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `match` | In | 1 | Comparator 결과 |
| `valid` | In | 1 | Tag Array의 Valid 비트 |
| `hit_o` (`Hit`) | Out | 1 | `match & valid` |

**동작:** `Hit = match & valid`. Cache Controller와 Read MUX/Aligner, MEM/WB 경로 제어에 사용.

### 8.7 Cache Controller (FSM)

캐시의 핵심 제어기. Hit/Miss 판정에 따라 SRAM 직접 접근 또는 AXI 버스트 트랜잭션을 오케스트레이션하고, 미스 동안 파이프라인을 `Stall` 시킨다.

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `clk`, `reset` | In | 1 | 클럭/리셋 |
| `mem_read` (`MemRead`) | In | 1 | 로드 요청 |
| `mem_write` (`MemWrite`) | In | 1 | 스토어 요청 |
| `hit` (`Hit`) | In | 1 | 히트 여부 |
| `dirty` | In | 1 | 대상 라인 Dirty (후기록 필요 판단) |
| `wake_up` (`Wake up`) | In | 1 | AXI Master가 버스트 완료를 통지 (트랜잭션 종료 신호) |
| `stall` (`Stall`) | Out | 1 | 미스 처리 동안 파이프라인 동결 |
| `data_we` | Out | 1 | Data Array 쓰기 enable |
| `tag_we` | Out | 1 | Tag Array 쓰기 enable |
| `line_fill` | Out | 1 | Refill(버스트 기록) 모드 |
| `ar_start` | Out | 1 | AR Master 기동 (읽기 주소 발행) |
| `aw_start` | Out | 1 | AW Master 기동 (쓰기 주소 발행, 후기록) |
| `w_start` | Out | 1 | W Master 기동 (쓰기 데이터 버스트) |

**FSM 상태:**

| 상태 | 설명 | 전이 |
|---|---|---|
| `IDLE` | 요청 대기 | `mem_read` 또는 `mem_write` → `COMPARE` |
| `COMPARE` | 태그 비교/Hit 판정 (1 cycle) | `Hit` → `IDLE`(접근 완료) / `Miss & dirty` → `WRITE_BACK` / `Miss & !dirty` → `ALLOCATE` |
| `WRITE_BACK` | Dirty 라인을 DDR로 후기록 (AW+W 버스트) | `wake_up` → `ALLOCATE` |
| `ALLOCATE` | 새 라인을 DDR에서 읽어옴 (AR+R 버스트) | `wake_up` → `REFILL` |
| `REFILL` | 받은 데이터로 Data/Tag Array 갱신, Valid=1 | → `COMPARE`(재시도) |

**동작 요약:** Hit이면 단일 사이클에 SRAM에 접근하고 `Stall=0`. Miss이면 `Stall=1` 을 유지하며 (필요 시) 후기록 후 라인을 채우고, `wake_up` 으로 버스트 완료를 확인하면 Refill 후 접근을 재시도한다. Refill 완료 시점에 `Stall` 을 해제하여 상위 파이프라인을 "깨운다". 스토어 hit 의 경우 `COMPARE` 에서 `tag_we`+`dirty_in=1` 로 해당 라인의 Dirty 비트를 세팅한 뒤 `IDLE` 로 복귀한다.

> **`Wake up` 신호 해석:** 다이어그램상 AXI Master 블록과 Cache Controller 사이에 위치하며, 외부 메모리(PS/DDR) 트랜잭션이 완료되어 Controller가 멈춤 상태에서 진행을 재개해야 함을 알리는 핸드셰이크 신호로 해석하였다.

### 8.8 Read MUX / Aligner

Data Array에서 읽은 라인/워드에서 요청 워드를 선택하고, `funct3` 에 따라 바이트/하프워드를 추출·부호확장하여 최종 로드 결과를 만든다.

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `line_in` / `word_in` | In | 128 / 32 | Data Array 출력 |
| `word_off` | In | 2 | 라인 내 워드 선택 |
| `byte_off` | In | 2 | 워드 내 바이트 위치 |
| `funct3` | In | 3 | LB/LH/LW/LBU/LHU 구분 |
| `hit` | In | 1 | 히트 시에만 유효 |
| `read_data_o` (`Read Data`) | Out | 32 | 정렬·부호확장된 로드 결과 → MEM/WB |

**동작 (funct3 기준):**

| funct3 | 명령 | 처리 |
|---|---|---|
| `000` | LB | 바이트 추출 후 부호확장(sign-extend) |
| `001` | LH | 하프워드 추출 후 부호확장 |
| `010` | LW | 워드 그대로 |
| `100` | LBU | 바이트 추출 후 0확장(zero-extend) |
| `101` | LHU | 하프워드 추출 후 0확장 |

먼저 `word_off` 로 4워드 중 하나를 선택(워드 MUX)한 뒤, `byte_off` 로 바이트/하프워드를 정렬하고 부호/0 확장을 적용한다.

> **스토어 측 정렬:** SB/SH/SW의 바이트 스트로브(`wstrb`)는 `funct3` 와 `byte_off` 로 생성되어 Data Array(`wstrb`)와 W Master(`WSTRB`)에 공급된다. 다이어그램에서 `Data2`(저장 데이터)가 Data Array와 AXI W 경로로 동시에 분기되는 부분이 이에 해당한다.

### 8.9 AXI4 Master 인터페이스

캐시 미스/후기록 시 Zynq PS의 HP 포트를 통해 DDR3L에 접근하는 AXI4 마스터. 다이어그램에는 **AW Master, W Master, AR Master, R Master** 4개 채널 블록이 그려져 있다. (AXI4 표준의 B(쓰기 응답) 채널은 다이어그램에 명시되지 않았으나 후기록 완료 확인을 위해 구현 필요 — 아래에 보충.)

#### 8.9.1 AR Master (Read Address 채널) — 라인 Allocate

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `ARADDR` | Out | 32 | 라인 시작 주소 (`{tag,index,0}`, 16B 정렬) |
| `ARLEN` | Out | 8 | 버스트 길이 (4워드 - 1 = 3, 즉 4-beat) |
| `ARSIZE` | Out | 3 | 비트 크기 (`010`=4B/beat) |
| `ARBURST` | Out | 2 | `01`=INCR |
| `ARVALID` | Out | 1 | 주소 유효 |
| `ARREADY` | In | 1 | 슬레이브 수락 |

#### 8.9.2 R Master (Read Data 채널) — Refill 데이터 수신

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `RDATA` | In | 32 | DDR 읽기 데이터 (Data Array로 라인 채움). **데이터 폭 32-bit 확정**(`ARSIZE=010`) |
| `RRESP` | In | 2 | 응답 상태 (`00`=OKAY) |
| `RLAST` | In | 1 | 버스트 마지막 beat → `wake_up` 생성 |
| `RVALID` | In | 1 | 데이터 유효 |
| `RREADY` | Out | 1 | 마스터 수신 준비 |

#### 8.9.3 AW Master (Write Address 채널) — Dirty 라인 후기록

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `AWADDR` | Out | 32 | 후기록 대상 라인 주소 |
| `AWLEN` | Out | 8 | 버스트 길이 (3 = 4-beat) |
| `AWSIZE` | Out | 3 | `010`=4B/beat |
| `AWBURST` | Out | 2 | `01`=INCR |
| `AWVALID` | Out | 1 | 주소 유효 |
| `AWREADY` | In | 1 | 슬레이브 수락 |

#### 8.9.4 W Master (Write Data 채널) — 후기록 데이터 송출

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `WDATA` (`Data2`/라인) | Out | 32 | 후기록 데이터 (Dirty 라인 워드). **데이터 폭 32-bit 확정**(`AWSIZE=010`) |
| `WSTRB` | Out | 4 | 바이트 스트로브 |
| `WLAST` | Out | 1 | 버스트 마지막 beat |
| `WVALID` | Out | 1 | 데이터 유효 |
| `WREADY` | In | 1 | 슬레이브 수신 준비 |

#### 8.9.5 B 채널 (보충 — 쓰기 응답)

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `BRESP` | In | 2 | 후기록 결과 (`00`=OKAY) |
| `BVALID` | In | 1 | 응답 유효 → `wake_up`(write) |
| `BREADY` | Out | 1 | 마스터 응답 수락 |

**동작:** Refill은 `AR→R` 채널로 라인을 INCR 버스트 읽기하고, `RLAST` 로 완료(`wake_up`)를 알린다. 후기록은 `AW→W→B` 순으로 Dirty 라인을 INCR 버스트 쓰기하고 `BVALID` 로 완료를 확인한다. 두 경로 모두 Cache Controller FSM의 `WRITE_BACK`/`ALLOCATE` 상태에서 기동된다.

---

## 9. MEM/WB 파이프라인 레지스터  *(다이어그램의 세로 블록 — 필드 보충)*

다이어그램에는 "MEM/WB Pipeline Reg" 세로 블록과 통과 신호(`rd`, `RegWrite`, `Read Data`, `MemtoReg`, `ALU Result`)만 표기되어 있어, 아래와 같이 필드를 정식 명세한다. 미스 동안 `stall` 로 동결된다.

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `clk`, `reset` | In | 1 | 클럭/리셋 |
| `stall` | In | 1 | 동결 (Cache `Stall`과 연결) |
| `flush` | In | 1 | 제어 NOP 클리어 |
| **입력 (MEM단)** | | | |
| `read_data_i` (`Read Data`) | In | 32 | 캐시 로드 결과 |
| `alu_result_i` (`ALU Result`) | In | 32 | EX 연산 결과 통과 |
| `rd_i` (`rd`) | In | 5 | 목적지 레지스터 |
| `reg_write_i` (`RegWrite`) | In | 1 | 레지스터 기록 enable |
| `mem_to_reg_i` (`MemtoReg`) | In | 1 | WB 소스 선택 |
| **출력 (WB단으로)** | | | |
| `read_data_o` (`ReadData`) | Out | 32 | → MemtoReg MUX (In1) |
| `alu_result_o` (`ALU Result`) | Out | 32 | → MemtoReg MUX (In2) |
| `rd_o` (`rd`) | Out | 5 | → Register File 쓰기 주소 |
| `reg_write_o` (`RegWrite`) | Out | 1 | → Register File 쓰기 enable |
| `mem_to_reg_o` (`MemtoReg`) | Out | 1 | → MemtoReg MUX select |

**동작:** MEM 결과를 한 클럭 래치하여 WB로 전달. `stall=1` 시 값 유지, `flush=1` 시 `reg_write_o=0` 으로 클리어.

---

## 10. Write Back (WB) 스테이지

### 10.1 MemtoReg MUX

로드 데이터(`ReadData`)와 ALU 결과(`ALU Result`) 중 하나를 선택하여 레지스터 파일에 기록할 값을 결정한다.

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `in1` (`ReadData`) | In | 32 | 메모리 로드 결과 (MemtoReg=1일 때 선택) |
| `in2` (`ALU Result`) | In | 32 | ALU 연산 결과 (MemtoReg=0일 때 선택) |
| `sel` (`MemtoReg`) | In | 1 | 선택 신호(로드 경로) |
| `in3` (`csr_rdata`) | In | 32 | CSR 읽기 결과 (`csr_to_reg=1`일 때 선택) |
| `csr_to_reg` | In | 1 | CSR 결과 우선 선택 |
| `write_data_o` (`WriteData`) | Out | 32 | 레지스터 파일 기록 데이터 |

**동작:** `WriteData = MemtoReg ? ReadData : ALU_Result`. 순수 2:1 MUX.

### 10.2 Register File 쓰기 포트 (WB 대상)

WB 스테이지가 구동하는 레지스터 파일 쓰기 인터페이스(레지스터 파일 본체는 ID 스테이지 소속).

| 신호명 | 방향 | 비트폭 | 설명 |
|---|---|---|---|
| `rd` | Out | 5 | 쓰기 대상 레지스터 (x0 기록 무시) |
| `write_data` (`WriteData`) | Out | 32 | MemtoReg MUX 결과 |
| `reg_write` (`RegWrite`) | Out | 1 | 쓰기 enable |

**동작:** `RegWrite=1` 이고 `rd≠x0` 일 때 클럭 상승 엣지에 `WriteData` 를 `rd` 에 기록한다.

---

### 10.3 Trap 커밋 & MRET (WB)

WB 커밋 시점에서 Trap Unit(§6.7)의 결정이 확정된다. 예외가 있으면 `RegWrite`/`mem_write` 등 부작용을 취소(squash)하고, `trap_taken=1`로 PC를 `mtvec`로 리다이렉트하며 CSR(`mepc/mcause/mtval/mstatus`)을 갱신한다. `MRET`은 `mstatus` 복원 후 PC를 `mepc`로 되돌린다. 두 경우 모두 `flush_all`로 후속 명령을 무효화한다.

## 11. 데이터 흐름 시나리오 (전체 파이프라인)

**R-type (`add rd,rs1,rs2`)** — IF 인출 → ID 해독/레지스터 읽기 → EX `ALU Result=rs1+rs2` → MEM 통과 → WB(`MemtoReg=0`) `rd` 기록.

**Load (`lw rd,imm(rs1)`)** — ID `mem_read=1, mem_to_reg=1` → EX 주소`=rs1+imm` → MEM D-Cache 읽기·정렬(`Read Data`) → WB(`MemtoReg=1`) `rd` 기록.

**Store (`sw rs2,imm(rs1)`)** — ID `mem_write=1, reg_write=0`, `Data2=rs2` → EX 주소`=rs1+imm` → MEM D-Cache 기록(`wstrb`)·Dirty=1. WB 없음.

**Branch (`beq`)** — ID `branch=1, alu_op=01` → EX 비교 성립 시 `pc_src=1`,`target_addr=pc+imm`로 IF 리다이렉트, `IF/ID`·`ID/EX` flush(버블).

**JAL (`jal rd,off`)** — EX `target_addr=pc+imm`,`pc_src=1`, 링크값`=pc+4` → WB `rd`에 `pc+4` 기록.

---

## 12. 통과 신호 & 해저드 요약

### 12.1 스테이지 통과(Pass-through) 신호

| 신호 | IF | ID | EX | MEM | WB |
|---|---|---|---|---|---|
| `instr` | 생성 | 해독 | — | — | — |
| `rd` | — | 추출 | 통과 | 통과 | RF 주소 |
| `funct3` | — | 추출 | 사용 | 정렬 | — |
| `Data2` | — | 읽기 | 통과 | 스토어 | — |
| `imm` | — | 생성 | 사용 | — | — |
| `ALU Result` | — | — | 생성 | 통과 | MUX In2 |
| `Read Data` | — | — | — | 생성 | MUX In1 |

### 12.2 해저드 처리(요약 — RTL 보충 대상)

- **데이터 해저드:** Forwarding Unit이 `EX/MEM`·`MEM/WB` 결과를 EX 입력으로 우회(§6.5).
- **로드-유즈 해저드:** Hazard Unit이 `stall`+`ID/EX flush`로 1사이클 정지(§4.5).
- **제어 해저드:** 우선순위 **트랩(Trap Unit) > 분기(BCU) > load-use(Hazard Unit)**. 트랩 확정 시 PC←`mtvec`(MRET은 `mepc`)로 리다이렉트하고 후속 단 전체 flush. 분기 성립 시 `IF/ID`·`ID/EX` flush(2버블), 정적 not-taken 예측.
- **구조 해저드:** I-Cache·D-Cache 분리로 메모리 포트 경합 없음.

---

## 13. 파라미터 확정 및 잔여 항목

> 아래 결정값의 상세 근거는 **`Movement.md` §1 확정 설계 파라미터**와 동일하며, 후속 단계 문서(`Dataflow_Architecture.md` ~ `Verification_Handover.md`)가 이를 공유한다.

### 13.1 확정된 결정 (Locked)

| 항목 | 확정값 | 근거 |
|---|---|---|
| AXI 데이터 폭 | **32-bit** (`xSIZE=010`, 4B/beat) | 32-bit CPU 설계(사용자 결정), XLEN=32 정합 |
| 캐시 사상/용량/라인 | Direct-Mapped / 4 KB / 16 B(4워드) / 256라인 | `addr_aligner.vhd` 비트 분할에서 역산(임의값 아님) |
| 라인 리필 | 4-beat INCR 버스트(`ARLEN=3`) | 단일 비트 → 라인 버스트 확장(노트 권고 반영) |
| `Wake up` 출처 | 읽기=`RLAST`, 쓰기=`BVALID`의 채널별 완료 OR | AXI 표준 완료 마커, 별도 통합 done 불필요 |
| 분기 해소 | EX 스테이지, 2-bubble, 정적 not-taken | 노트 결정 |
| D-Cache 쓰기 정책 | Write-Back + Write-Allocate(Dirty 1b/line), B 채널 필수(§8.9.5) | MEM 다이어그램 정책 |
| `RESET_ADDR` | `0x0000_0000` | `pc_reg` generic 기본값, 베어메탈 부트벡터 |
| 목표 클럭 | 100 MHz(10 ns) *(계획 가정)* | Zybo Z7 PL 동작점, 타이밍 다이어그램 기준 |

### 13.1.1 Category A 반영(표준 RV32I 필수) — 확정

| 항목 | 반영 위치 |
|---|---|
| `SYSTEM`(ECALL/EBREAK/MRET) 디코드 | §4.2 / §4.2.1 |
| `FENCE`/`FENCE.I` 디코드 | §4.2.1 (FENCE.I=I-Cache 무효화) |
| CSR File + Zicsr(CSRRW/RS/RC[I]) | §4.6 |
| Trap/Exception Unit(`mtvec/mepc/mcause/mstatus`, MRET) | §6.7 / §10.3 |
| 불법 명령 검출(디코더 default) | §4.2.1 |

### 13.2 잔여(향후 RTL 단계) 항목

- **ID·EX·4개 파이프라인 레지스터, 포워딩/해저드 유닛, I-Cache 데이터 어레이·AXI 마스터**는 본 문서/후속 문서에서 동작·구조까지 확정하되 RTL 구현은 Phase 5 이후로 미룬다(본 작업 범위 외).
