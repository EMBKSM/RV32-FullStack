# RV32-FullStack — Movement 명세 (IP 블록 동작·제어·내부 데이터 이동, 극상세)

> 목적: `RV32_Pipeline_Spec.md`가 각 블록의 **I/O(포트)** 만 정의한 데 비해, 본 문서는 각 IP 블록의 **모든 동작·조건·제어 경로**와 **내부 데이터 이동**을 빠짐없이 기술한다. 특히 **조합 로직은 모든 조건과 선택 신호를 진리표/선택표로 명시**하고, FSM은 상태·천이조건·출력을 표로 명시한다.
> 기준: 확정 파라미터(§1)는 메인 스펙 §13.1과 동일. IF 블록은 실제 VHDL 동작 기준, 그 외는 보충.
> 범위: 명세/문서/검증 단계.

---

## 1. 확정 설계 파라미터 (Design Parameter Lock)

| 파라미터 | 확정값 | 할당 근거 |
|---|---|---|
| XLEN / 주소폭 | 32 / 32 | RV32I 기본 정수 ISA |
| AXI 데이터 폭 | 32-bit (`xSIZE=010`, 4B/beat) | **사용자 결정**: 32-bit CPU. XLEN=32와 정합되어 폭 변환 불필요 |
| 캐시 사상 방식 | Direct-Mapped (1-way) | 구현 RTL이 Tag Array·Comparator 각 1개 → 직접사상 강제 |
| 캐시 용량 (I/D 각) | 4 KB | `addr_aligner.vhd` 분할에서 256라인 × 16B = 4 KB 로 역산 |
| 라인 크기 | 16 B (4 word) | offset 4-bit = 16 B |
| 라인 수 / 인덱스 폭 | 256 / 8-bit | idx[11:4] = 8-bit = 256 라인 |
| 태그 폭 | 20-bit | tag[31:12] |
| 라인 리필 | 4-beat INCR 버스트 (`ARLEN=3`, `ARSIZE=010`, `ARBURST=01`) | 32-bit × 4 beat = 16 B 라인 |
| D-Cache 쓰기 정책 | Write-Back + Write-Allocate, Dirty 1-bit/line | MEM 정책. I-Cache는 read-only |
| `Wake up` 신호 출처 | 읽기 = `RLAST`, 후기록 = `BVALID`, 두 채널 OR | AXI 표준 완료 마커 |
| 분기 해소 | EX 스테이지, 2-bubble, 정적 not-taken | 노트 결정 |
| `RESET_ADDR` | `0x0000_0000` | `pc_reg` generic, 베어메탈 부트벡터 |
| 목표 클럭 | 100 MHz (10 ns) *(계획 가정)* | Zybo Z7 PL 동작점 |
| 레지스터 파일 | 32 × 32-bit, 2R/1W, `x0`=0, write-first | WB→ID RAW 회피 |
| 리셋 극성 | active-high `reset`, 비동기 | 프로젝트 관례(`reset='1'`) |

---

## 2. 표기·동작 관례 (반드시 숙지)

- **지연:** `comb`(조합, 동일 사이클 전파) / `seq@↑`(상승 엣지 등록, 1 사이클 지연).
- **진입/이탈:** 각 블록의 입력 유효 시점 → 출력 유효 시점을 명시.
- **진리표 표기:** `-`(don't care), `1`/`0`(레벨), 다중 비트는 2진/16진. 선택표는 "선택신호 값 → 출력 소스/연산".
- **우선순위 표기:** 제어 동작이 겹칠 때 위에서 아래로 우선순위가 높다(예: reset > flush > stall > load).
- **표기 회피:** 표 셀 내부에서 비트 OR 은 파이프 대신 `OR`로 적는다(마크다운 표 보호).
- **동결:** `stall=1`이면 상태 보유 블록은 값 유지, 조합 블록은 입력을 따라간다.

---

## 3. IF 스테이지 — 블록별 동작·조건·데이터 이동

### 3.1 PC Register (`pc_reg`) — seq@↑, 버퍼=PC 1개

**제어 우선순위 선택표** (위가 우선):

| 우선 | 조건 | 동작 |
|---|---|---|
| 1 | `reset = 1` | `pc <= RESET_ADDR(0x0000_0000)` (비동기) |
| 2 | `stall = 1` | `pc` 유지(미스/해저드 동결) |
| 3 | 그 외(상승 엣지) | `pc <= next_pc` |

**데이터 이동:** `next_pc`는 사이클 N 동안 유효 → 사이클 N 말 상승 엣지에 캡처 → N+1부터 `pc` 전파.

### 3.2 PC Adder (`pc_adder`) — comb
- `pc_out = pc + 4`(mod 2^32). 입력과 동일 사이클 출력. 버퍼 없음.

### 3.3 Next-PC MUX (`next_pc_mux`) — comb, **선택표**

| `pc_src` | `next_pc` 선택 | 발생 상황 |
|---|---|---|
| `0` | `pc_plus_4` | 순차 실행(비분기/분기 미성립) |
| `1` | `target_addr` | 분기 성립 또는 점프(EX→IF 역경로) |

### 3.4 Address Aligner (`addr_aligner`) — comb, **비트필드 매핑표**

| 출력 | 비트 | 폭 | 소비처 |
|---|---|---|---|
| `tag` | `address[31:12]` | 20 | Comparator |
| `idx` | `address[11:4]` | 8 | Tag Array, Data Array |
| `offset` | `address[3:0]` | 4 | 워드/바이트 선택 |

세부: `offset[3:2]`=워드 선택(4워드 중 1), `offset[1:0]`=바이트 위치.

### 3.5 Tag Array (`tag_array`) — 읽기 comb / 쓰기 seq@↑, **동작 조건표**

| 조건 | 동작 |
|---|---|
| `reset = 1` | 전 라인 `valid <= 0` (비동기, 태그값은 무효 게이팅) |
| `inv = 1` (상승 엣지) | **전 라인 `valid <= 0`** (무효화, `we`보다 우선; B1 코드적재/FENCE.I) |
| `we = 1` (상승 엣지) | `tag_mem[idx] <= tag_in`, `valid[idx] <= 1` |
| `we = 0` | 유지. `idx` 인가 시 `tag_out/valid_out` 비동기 출력 |

### 3.6 Comparator (`comparator`) — comb, **히트 진리표**

| `valid_bit` | `addr_tag == cache_tag` | `hit` |
|---|---|---|
| `0` | `-` | `0` |
| `1` | 불일치 | `0` |
| `1` | 일치 | `1` |

`hit = valid_bit AND (addr_tag == cache_tag)`. `miss = (인출요청) AND NOT hit`.

### 3.7 Cache Controller (`cache_controller`) — FSM (Moore+Mealy)

**다음 상태표** (입력: `miss, arready, rvalid`):

| 현재 상태 | 조건 | 다음 상태 |
|---|---|---|
| `S_IDLE` | `miss = 1` | `S_SEND_AR` |
| `S_IDLE` | `miss = 0` | `S_IDLE` |
| `S_SEND_AR` | `arready = 1` | `S_WAIT_R` |
| `S_SEND_AR` | `arready = 0` | `S_SEND_AR` |
| `S_WAIT_R` | `rvalid = 1` | `S_UPDATE_CACHE` |
| `S_WAIT_R` | `rvalid = 0` | `S_WAIT_R` |
| `S_UPDATE_CACHE` | `-` | `S_WAKE_UP` |
| `S_WAKE_UP` | `-` | `S_IDLE` |

**출력표** (상태별, `we`는 Mealy):

| 상태 | `stall` | `arvalid` | `rready` | `we` | `wake_up` |
|---|---|---|---|---|---|
| `S_IDLE` | `miss` | `0` | `0` | `0` | `0` |
| `S_SEND_AR` | `1` | `1` | `0` | `0` | `0` |
| `S_WAIT_R` | `1` | `0` | `1` | `rvalid` | `0` |
| `S_UPDATE_CACHE` | `1` | `0` | `0` | `0` | `0` |
| `S_WAKE_UP` | `0` | `0` | `0` | `0` | `1` |

핵심: `S_WAIT_R`에서 `we = rvalid` (Mealy) → **데이터가 유효한 바로 그 사이클에 라인 캡처**(검증 반영). `stall`은 `S_IDLE`에서만 `miss`에 의존(나머지 미스 상태는 항상 1).

**I-Cache 무효화(B1) — `S_IDLE` 추가 동작표** (입력 `fence_i`/`ext_inv`, 1-cycle 펄스):

| 조건 (S_IDLE) | `inv` | `stall` | `iflush` | next_state |
|---|---|---|---|---|
| `fence_i = 1` | `1` | `1` | `1` | `S_IDLE` (무효화 1사이클 후 재페치) |
| `ext_inv = 1` | `1` | `1` | `0` | `S_IDLE` |
| `miss = 1` (무효화 없음) | `0` | `1` | `0` | `S_SEND_AR` |
| 그 외 | `0` | `0` | `0` | `S_IDLE` |

무효화 우선순위는 miss보다 높다. 무효화 사이클에 Tag Array `inv`로 전 Valid가 클리어되고, 다음 사이클 동일 PC는 miss가 되어 **DDR에서 갱신된 코드를 리필**한다 → UART 적재 후 스테일 명령어 페치 방지. `FENCE.I`는 `iflush=1`로 이미 인출된 후속 명령까지 비운다.

### 3.8 Instruction Data Array (SRAM) — 읽기 comb / 쓰기 seq@↑

| 조건 | 동작 |
|---|---|
| 읽기(항상) | `idx`+`offset[3:2]`로 워드 선택 → `instr_out` 비동기 출력 |
| `we=1` 그리고 `line_fill=1` | R Master 4 beat를 `idx` 라인의 4워드에 순차 기록 |

### 3.9 AXI4 AR/R Master (읽기 전용) — **핸드셰이크 조건표**

| 채널 | 전송 성립 조건 | 비고 |
|---|---|---|
| AR | `ARVALID = 1 AND ARREADY = 1` | 주소 1회. `ARADDR={tag,idx,4'b0}`, `ARLEN=3` |
| R | `RVALID = 1 AND RREADY = 1` | beat 카운터++; `RLAST=1`에서 라인 완료 → `wake_up` |

---

## 4. ID 스테이지 — 해독·읽기·즉치

### 4.1 Control Unit (Decoder) — comb, **전체 제어 신호표**

`opcode = instr[6:0]` 입력으로 모든 제어 신호를 동시에 생성한다. (`result_src`: 00=ALU Result, 01=Read Data, 10=PC+4(링크), 11=imm(LUI). `src_a`: 0=rs1_data, 1=PC.)

| 클래스 | opcode | reg_write | src_a | alu_src | mem_read | mem_write | branch | jump | alu_op | result_src |
|---|---|---|---|---|---|---|---|---|---|---|
| R-type | `0110011` | 1 | 0 | 0 | 0 | 0 | 0 | 0 | `10` | `00` |
| I-ALU | `0010011` | 1 | 0 | 1 | 0 | 0 | 0 | 0 | `10` | `00` |
| Load | `0000011` | 1 | 0 | 1 | 1 | 0 | 0 | 0 | `00` | `01` |
| Store | `0100011` | 0 | 0 | 1 | 0 | 1 | 0 | 0 | `00` | `00` |
| Branch | `1100011` | 0 | 0 | 0 | 0 | 0 | 1 | 0 | `01` | `00` |
| JAL | `1101111` | 1 | 1 | 1 | 0 | 0 | 0 | 1 | `00` | `10` |
| JALR | `1100111` | 1 | 0 | 1 | 0 | 0 | 0 | 1 | `00` | `10` |
| LUI | `0110111` | 1 | 0 | 1 | 0 | 0 | 0 | 0 | `11` | `11` |
| AUIPC | `0010111` | 1 | 1 | 1 | 0 | 0 | 0 | 0 | `00` | `00` |
| SYSTEM-CSR | `1110011` | 1 | 0 | 0 | 0 | 0 | 0 | 0 | `00` | `00` |
| SYSTEM-Trap | `1110011` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | `00` | `00` |
| FENCE | `0001111` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | `00` | `00` |
| (default) Illegal | 그 외 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | `00` | `00` |

`mem_to_reg`는 `result_src=01`(Load)일 때 1인 부분집합 신호다. SYSTEM-CSR은 `csr_to_reg=1`로 `csr_rdata`를 `rd`에 기록(§4.5), SYSTEM-Trap(ECALL/EBREAK/MRET)·FENCE·Illegal은 레지스터 부작용이 없다(§4.6·§7.3).

### 4.2 Register File — 읽기 comb / 쓰기 seq(write-first), **포트 조건표**

| 포트 | 조건 | 동작 |
|---|---|---|
| 읽기 A | 항상 | `rs1=0` 이면 `0`, 아니면 `regs[rs1]` → `rs1_data` |
| 읽기 B | 항상 | `rs2=0` 이면 `0`, 아니면 `regs[rs2]` → `rs2_data(Data2)` |
| 쓰기 | `reg_write=1 AND rd≠0` | 클럭 전반(write-first) `regs[rd] <= WriteData` |
| 쓰기 | `rd=0` 또는 `reg_write=0` | 기록 무시 |

write-first: 같은 사이클 WB 쓰기 → ID 읽기에서 최신값 반영(WB→ID RAW 1건 해소).

### 4.3 Immediate Generator — comb, **포맷 선택표**

`imm_sel`(opcode 파생)로 포맷을 선택하고 `instr[31]`로 부호확장한다.

| `imm_sel` | 포맷 | 사용 명령 | 즉치 비트 구성 (MSB→LSB) |
|---|---|---|---|
| `000` | I | I-ALU, Load, JALR | sext, `instr[31:20]` |
| `001` | S | Store | sext, `instr[31:25]`, `instr[11:7]` |
| `010` | B | Branch | sext, `instr[31]`, `instr[7]`, `instr[30:25]`, `instr[11:8]`, `0` |
| `011` | U | LUI, AUIPC | `instr[31:12]`, 하위 12b `0` |
| `100` | J | JAL | sext, `instr[31]`, `instr[19:12]`, `instr[20]`, `instr[30:21]`, `0` |

### 4.4 Hazard Detection Unit (load-use) — comb, **검출 조건표**

| 조건 | 동작 |
|---|---|
| `ID/EX.mem_read=1 AND ID/EX.rd≠0 AND (ID/EX.rd == IF/ID.rs1 OR ID/EX.rd == IF/ID.rs2)` | `stall=1`(PC·IF/ID 유지) + `ID/EX flush`(1-bubble) |
| 그 외 | 정상 진행 |

다음 사이클에 EX/MEM→EX 포워딩으로 값이 확정된다.

### 4.5 CSR File (Machine-mode) — 읽기 comb / 쓰기·부작용 WB 커밋, **접근 규칙표**

`csr_addr=instr[31:20]`로 CSR를 읽고, `csr_cmd`로 갱신한다. `src = csr_use_imm ? zext(zimm5=rs1필드) : rs1_data`.

| 명령 | 읽기(→rd) | 쓰기(csr ←) | 부작용 억제 |
|---|---|---|---|
| CSRRW | old CSR (rd≠x0) | `src` | rd=x0이면 읽기 억제 |
| CSRRS | old CSR | `csr OR src` (set) | rs1=x0이면 쓰기 억제 |
| CSRRC | old CSR | `csr AND NOT src` (clear) | rs1=x0이면 쓰기 억제 |
| CSRRWI | old CSR | `zimm` | uimm 규칙 동일 |
| CSRRSI | old CSR | `csr OR zimm` | zimm=0이면 쓰기 억제 |
| CSRRCI | old CSR | `csr AND NOT zimm` | zimm=0이면 쓰기 억제 |

최소 CSR 집합: `mstatus(0x300)`, `misa(0x301)`, `mie(0x304)`, `mtvec(0x305)`, `mscratch(0x340)`, `mepc(0x341)`, `mcause(0x342)`, `mtval(0x343)`, `mip(0x344)`, `mhartid(0xF14)`. 리셋 시 `mstatus.MIE=0`(안전값).

### 4.6 SYSTEM / FENCE 디코드 & 불법명령 — comb, **디코드표**

| funct3 | 식별 | 명령 | 동작 |
|---|---|---|---|
| `000` | imm=`0x000` | ECALL | 예외(cause 11) |
| `000` | imm=`0x001` | EBREAK | 예외(cause 3) |
| `000` | `0x302` | MRET | mstatus 복원, PC←mepc |
| `000` | `0x105` | WFI | (옵션) NOP |
| `001` | csr | CSRRW | csr ↔ rs1 |
| `010` | csr | CSRRS | set |
| `011` | csr | CSRRC | clear |
| `101` | csr | CSRRWI | csr ↔ zimm |
| `110` | csr | CSRRSI | set imm |
| `111` | csr | CSRRCI | clear imm |

FENCE(`0001111`): `funct3=000`=FENCE(단순코어 NOP, 단 디코드 필수), `funct3=001`=FENCE.I(I-Cache 무효화). **불법명령:** 유효 인코딩 미매칭 → `illegal_instr=1` → 트랩(cause 2).

---

## 5. EX 스테이지 — 연산·분기 (모든 선택/연산 진리표)

### 5.1 Operand A MUX — comb, **선택표**

| `src_a_sel` | `a` 선택 |
|---|---|
| `0` | `rs1_data` (포워딩 반영) |
| `1` | `pc` (AUIPC/JAL 타겟 가산용) |

### 5.2 Operand B MUX (`alu_src`) — comb, **선택표**

| `alu_src` | `b` 선택 |
|---|---|
| `0` | `rs2_data(Data2)` (포워딩 반영) |
| `1` | `imm` |

### 5.3 ALU Control — comb, **완전 디코드표** (`alu_op`, `funct3`, `funct7[5]` → `alu_ctrl`)

| `alu_op` | `funct3` | `funct7[5]` | `alu_ctrl` | 연산 |
|---|---|---|---|---|
| `00` | `-` | `-` | `0000` | ADD (주소: Load/Store/AUIPC/JALR) |
| `01` | `-` | `-` | `0001` | SUB (분기 비교) |
| `11` | `-` | `-` | `1010` | Bpass (LUI: b 통과) |
| `10` | `000` | `0` | `0000` | ADD |
| `10` | `000` | `1` | `0001` | SUB |
| `10` | `001` | `-` | `0101` | SLL |
| `10` | `010` | `-` | `1000` | SLT |
| `10` | `011` | `-` | `1001` | SLTU |
| `10` | `100` | `-` | `0100` | XOR |
| `10` | `101` | `0` | `0110` | SRL |
| `10` | `101` | `1` | `0111` | SRA |
| `10` | `110` | `-` | `0011` | OR |
| `10` | `111` | `-` | `0010` | AND |

주: `funct7[5]`는 R-type와 시프트 즉치(SRLI/SRAI)에서만 유효. ADDI(`funct3=000`, I-ALU)는 `funct7` 무시하고 ADD.

### 5.4 ALU — comb, **연산표** (`alu_ctrl` → `result`, `zero`)

| `alu_ctrl` | 연산 | `result` |
|---|---|---|
| `0000` | ADD | `a + b` |
| `0001` | SUB | `a − b` |
| `0010` | AND | `a AND b` |
| `0011` | OR | `a OR b` |
| `0100` | XOR | `a XOR b` |
| `0101` | SLL | `a << b[4:0]` |
| `0110` | SRL | `a >> b[4:0]` (logical) |
| `0111` | SRA | `a >> b[4:0]` (arithmetic) |
| `1000` | SLT | signed `a < b` ? 1 : 0 |
| `1001` | SLTU | unsigned `a < b` ? 1 : 0 |
| `1010` | Bpass | `b` |

`zero = (result == 0)`. 결과는 `ALU Result`로 EX/MEM·MEM 주소·WB result MUX로 전파.

### 5.5 BCU (Branch Comparison Unit) — 비교부, comb, **조건표** (`funct3`)

BCU는 EX의 분기 해소 전담 조합 유닛으로, ALU와 분리된 전용 비교기로 포워딩된 `a`/`b`를 비교한다.

| `funct3` | 분기 | 성립 조건(`cond_met`) |
|---|---|---|
| `000` | BEQ | `a == b` |
| `001` | BNE | `a != b` |
| `100` | BLT | signed `a < b` |
| `101` | BGE | signed `a >= b` |
| `110` | BLTU | unsigned `a < b` |
| `111` | BGEU | unsigned `a >= b` |

`funct3=010/011`은 분기 미정의(예약).

### 5.6 BCU — pc_src / target_addr 생성, comb, **진리표**

| `branch` | `jump` | `cond_met` | `pc_src` | `target_addr` 선택 |
|---|---|---|---|---|
| `0` | `0` | `-` | `0` | (미사용) |
| `1` | `0` | `0` | `0` | (미선택) |
| `1` | `0` | `1` | `1` | `pc + imm` |
| `0` | `1` | `-` | `1` | JAL: `pc + imm` / JALR: `(rs1_data + imm) AND ~1` |

`pc_src = jump OR (branch AND cond_met)`. JALR 여부는 opcode로 구분(target 하위 비트 클리어).

### 5.7 Forwarding Unit & Forwarding MUX — comb, **선택표** (`forward_a`, 동일 논리로 `forward_b`)

Forwarding Unit이 후속 스테이지 목적지와 EX 소스를 비교해 `forward_a/b`를 생성하고, Forwarding MUX가 ALU·BCU 입력 직전에서 우회 선택한다.

우선순위: EX/MEM(가장 최근) > MEM/WB > 레지스터 파일.

| `forward_a` | 조건 | `a` 소스 |
|---|---|---|
| `10` | `EX/MEM.reg_write=1 AND EX/MEM.rd≠0 AND EX/MEM.rd == ID/EX.rs1` | `EX/MEM.alu_result` |
| `01` | 위 불성립 그리고 `MEM/WB.reg_write=1 AND MEM/WB.rd≠0 AND MEM/WB.rd == ID/EX.rs1` | `MEM/WB.write_data` |
| `00` | 그 외 | `rs1_data` (레지스터 파일) |

`forward_b`는 `ID/EX.rs2` 기준으로 동일하게 결정한다.

---

## 6. MEM 스테이지 — 데이터 캐시·정렬·AXI

### 6.1 Address Aligner (데이터) — comb
`ALU Result`를 §3.4와 동일한 비트필드(tag20/idx8/offset4)로 분해 → Tag/Data Array 인덱싱.

### 6.2 Hit 판정 게이트 — comb, **진리표**

| `match`(태그 일치) | `valid` | `hit` |
|---|---|---|
| `0` | `-` | `0` |
| `1` | `0` | `0` |
| `1` | `1` | `1` |

### 6.3 Tag/Data Array (D-Cache) — 읽기 comb / 쓰기 seq@↑, **동작 조건표**

| 조건 | 동작 |
|---|---|
| 로드 hit | `idx`+`offset[3:2]` 워드 읽기 → Read MUX/Aligner |
| 스토어 hit | `wstrb` 지정 바이트 기록(seq@↑), 해당 라인 `dirty<=1` |
| 리필 | R Master 4 beat를 라인에 채움(`line_fill`), `valid<=1` |
| `reset=1` | 전 라인 `valid<=0` |

### 6.4 Read MUX / Aligner — comb, **로드 추출·확장표** (`funct3`, `byte_off=offset[1:0]`)

먼저 `offset[3:2]`로 4워드 중 1워드 선택 후, 다음 규칙으로 정렬·확장한다.

| `funct3` | 명령 | 크기 | 확장 | 유효 `byte_off` | 출력 |
|---|---|---|---|---|---|
| `000` | LB | 8b | 부호확장(sign) | 0,1,2,3 | `byte_off` 위치 바이트 → 32b sext |
| `001` | LH | 16b | 부호확장(sign) | 0,2 | 하프워드 → 32b sext |
| `010` | LW | 32b | 없음 | 0 | 워드 그대로 |
| `100` | LBU | 8b | 0확장(zero) | 0,1,2,3 | 바이트 → 32b zext |
| `101` | LHU | 16b | 0확장(zero) | 0,2 | 하프워드 → 32b zext |

비정렬(`byte_off`가 유효 집합 밖)은 misalign 예외 후보(옵션).

### 6.5 Write Strobe Generator — comb, **`wstrb` 생성표** (`funct3` 스토어, `byte_off`)

| `funct3` | 명령 | `byte_off` | `wstrb` |
|---|---|---|---|
| `000` | SB | 0 | `0001` |
| `000` | SB | 1 | `0010` |
| `000` | SB | 2 | `0100` |
| `000` | SB | 3 | `1000` |
| `001` | SH | 0 | `0011` |
| `001` | SH | 2 | `1100` |
| `010` | SW | 0 | `1111` |

`wstrb`는 Data Array와 AXI W 채널(`WSTRB`)에 동일 공급. `Data2`는 `byte_off`에 맞춰 바이트 레인 정렬 후 기록.

### 6.6 Cache Controller (D-Cache, Write-Back) — FSM **천이·출력표**

| 현재 상태 | 조건 | 다음 상태 | 주요 출력 |
|---|---|---|---|
| `D_IDLE` | 접근요청 AND hit | `D_IDLE` | `stall=0` (로드/스토어 즉시) |
| `D_IDLE` | miss AND dirty | `D_WB_AW` | `stall=1` |
| `D_IDLE` | miss AND NOT dirty | `D_ALLOC_AR` | `stall=1` |
| `D_WB_AW` | `AWREADY=1` | `D_WB_W` | `awvalid=1` |
| `D_WB_W` | `WLAST` 송출 | `D_WB_B` | `wvalid=1`, `wstrb` |
| `D_WB_B` | `BVALID=1` | `D_ALLOC_AR` | `bready=1` |
| `D_ALLOC_AR` | `ARREADY=1` | `D_ALLOC_R` | `arvalid=1` |
| `D_ALLOC_R` | `RLAST=1` | `D_REFILL` | `rready=1`, `we=rvalid` |
| `D_REFILL` | `-` | `D_WAKE` | `valid<=1` |
| `D_WAKE` | `-` | `D_IDLE` | `wake_up=1`, `stall=0` |

`wake_up = (읽기 RLAST 완료) OR (쓰기 BVALID 완료)`. 스토어 hit는 `D_IDLE`에서 `tag_we`+`dirty_in=1`로 Dirty 세팅 후 유지.

### 6.7 AXI4 Master (AW/W/B/AR/R) — **핸드셰이크 조건표**

| 채널 | 전송 성립 조건 | 완료 표식 |
|---|---|---|
| AW | `AWVALID=1 AND AWREADY=1` | — |
| W | `WVALID=1 AND WREADY=1` | `WLAST` |
| B | `BVALID=1 AND BREADY=1` | `BVALID` → wake_up(쓰기) |
| AR | `ARVALID=1 AND ARREADY=1` | — |
| R | `RVALID=1 AND RREADY=1` | `RLAST` → wake_up(읽기) |

폭 32-bit 고정(`xSIZE=010`), 라인 = 4 beat INCR(`xLEN=3`).

---

## 7. WB 스테이지

### 7.1 WB Result MUX (MemtoReg 확장) — comb, **선택표** (`result_src`)

| `result_src` | `WriteData` 선택 | 명령 |
|---|---|---|
| `00` | `ALU Result` | R/I-ALU/Store(미기록)/AUIPC |
| `01` | `Read Data` | Load |
| `10` | `PC + 4` | JAL/JALR(링크) |
| `11` | `imm` | LUI |

기존 2:1 `MemtoReg` MUX는 `result_src ∈ {00,01}`(ALU/메모리) 부분집합이다. `MemtoReg=1`일 때 선택 = `Read Data`(`result_src=01`). **`csr_to_reg=1`이면 `result_src`보다 우선하여 `csr_rdata`를 기록한다(CSRR* 명령).**

### 7.2 Register File 쓰기 포트 — seq(write-first), **조건표**

| 조건 | 동작 |
|---|---|
| `reg_write=1 AND rd≠0` | 클럭 전반 `regs[rd] <= WriteData` |
| `rd=0` 또는 `reg_write=0` | 기록 무시 |

### 7.3 Trap & Exception Unit (Machine-mode) — WB 커밋, **원인표·시퀀스**

예외 플래그는 검출 단에서 생성·전달되고, **WB 커밋 시점**에 트랩이 확정되어 후속 단을 모두 flush(정밀 예외).

**예외 원인(`mcause`):**

| cause | 예외 |
|---|---|
| `0` | 명령 주소 정렬오류 |
| `2` | 불법 명령 |
| `3` | 브레이크포인트(EBREAK) |
| `4` | 로드 주소 정렬오류 |
| `6` | 스토어 주소 정렬오류 |
| `11` | 환경호출 ECALL(M) |
| MSB=1 | 인터럽트(예: `7` 머신 타이머) |

**트랩 진입:** `mepc←instr_pc`, `mcause←cause`, `mtval←fault_addr`, `mstatus.MPIE←MIE`, `mstatus.MIE←0`, `mstatus.MPP←11`, `PC←mtvec.BASE`, `flush_all=1`, 부작용(RegWrite/mem_write) squash.
**MRET:** `mstatus.MIE←MPIE`, `MPIE←1`, `MPP←00`, `PC←mepc`, `flush_all=1`.

---

## 8. 파이프라인 레지스터 — 동작·우선순위

모든 경계 레지스터 공통 **제어 우선순위표**(위가 우선):

| 우선 | 조건 | 동작 |
|---|---|---|
| 1 | `reset=1` | 전 필드 0 (비동기) |
| 2 | `flush=1` | 제어 신호 0 클리어(버블 주입) |
| 3 | `stall=1` | 값 유지(동결) |
| 4 | 그 외(상승 엣지) | 입력을 출력으로 래치 |

| 레지스터 | 보유 데이터(요약) | flush 발생 | stall 발생 |
|---|---|---|---|
| IF/ID | pc, pc+4, instr | 분기 성립 | 미스/로드-유즈 |
| ID/EX | pc, pc+4, rs1/rs2_data, imm, rs1/rs2/rd, funct3/funct7_5, 제어 | 분기 성립/로드-유즈 | 미스 |
| EX/MEM | ALU Result, Data2, rd, funct3, 제어 | — | 미스 |
| MEM/WB | Read Data, ALU Result, rd, 제어 | — | (미스 시 버블 주입) |

---

## 9. 종단 데이터 이동 시나리오 (사이클 단위, 제어값 포함)

### 9.1 인출 Hit (1 cycle)
- C0: `pc=A` → Addr Aligner → Tag/Comparator `hit=1`(comb) → Data Array 워드 → IF/ID 래치(C0 말 ↑). `stall=0`.

### 9.2 인출 Miss + 리필
- C0: `hit=0` → `S_IDLE`에서 `stall=1`. C1: `S_SEND_AR`(`arvalid=1`). C2..C5: `S_WAIT_R`(`rready=1`), `rvalid` 사이클마다 `we=1`로 라인 캡처, `RLAST`→완료. `S_WAKE_UP`에서 `stall=0`. 재시도 hit. PC=A 유지.

### 9.3 로드 Hit (LW, `funct3=010`)
- EX: `alu_src=1`,`alu_op=00`→주소`=rs1+imm`(`ALU Result`). MEM: Data Array 워드 읽기 → Read MUX(`funct3=010`)→`Read Data`. WB: `result_src=01`→`WriteData=Read Data`→`rd` 기록(`reg_write=1`).

### 9.4 분기 성립 (BEQ taken)
- EX(C2): `branch=1`,`alu_op=01`, Branch Comparator `cond_met=1` → `pc_src=1`,`target_addr=pc+imm`(comb)→IF Next-PC MUX 즉시. IF/ID(C1)·ID/EX(C2) `flush`(2-bubble). C3부터 타겟 인출.

### 9.5 스토어 Hit (SH, `funct3=001`, `byte_off=2`)
- EX: `mem_write=1`,주소`=rs1+imm`, `Data2=rs2`. MEM: Write Strobe `wstrb=1100`, Data Array 상위 하프워드 기록(seq@↑), `dirty=1`. WB 미기록(`reg_write=0`).

### 9.6 로드-유즈 해저드 (LW 다음 명령이 결과 사용)
- Hazard Unit 검출 → `stall=1`+`ID/EX flush`(1-bubble). 다음 사이클 EX/MEM→EX 포워딩(`forward_a/b`)으로 값 확정.

---

## 10. 블록별 지연·버퍼 분류 요약

| 블록 | 지연 유형 | 내부 버퍼 | 진입→이탈 |
|---|---|---|---|
| PC Register | seq@↑ | PC 1개 | next_pc(N)→pc(N+1) |
| PC Adder | comb | 없음 | pc→pc+4 |
| Next-PC MUX | comb | 없음 | 선택→next_pc |
| Address Aligner | comb | 없음 | addr→tag/idx/offset |
| Tag Array | 읽기 comb/쓰기 seq@↑ | 256×(tag+valid) | idx→tag_out/valid |
| Comparator | comb | 없음 | tag/valid→hit |
| Cache Controller | FSM seq | 상태 레지스터 | miss→stall/we/AXI |
| Data Array (SRAM) | 읽기 comb/쓰기 seq@↑ | 256×16B | idx/offset→word |
| Control Unit | comb | 없음 | opcode→제어 |
| Register File | 읽기 comb/쓰기 seq | 32×32 | rs1/rs2→data |
| Immediate Generator | comb | 없음 | instr→imm |
| ALU Control | comb | 없음 | alu_op/funct→alu_ctrl |
| ALU | comb | 없음 | a/b/ctrl→result |
| BCU (Branch Comparison Unit) | comb | 없음 | a_fwd/b_fwd/funct3→branch_taken/pc_src/target |
| Forwarding Unit & MUX | comb | 없음 | rd 비교→forward_a/b→소스 우회 |
| Read MUX / Aligner | comb | 없음 | line/word/funct3→Read Data |
| Write Strobe Gen | comb | 없음 | funct3/byte_off→wstrb |
| MemtoReg/Result MUX | comb | 없음 | result_src→WriteData |
| 파이프라인 레지스터(×4) | seq@↑ | 단별 필드 | 입력단→출력단 |

> 핵심: 연산·선택·디코드·정렬은 전부 **조합(comb)**, 상태는 PC·Tag/Data Array·Register File·캐시 FSM·4개 경계 레지스터에만 존재. 임계경로는 조합 체인(Addr Aligner→SRAM 읽기→Comparator→Read MUX) 길이로 결정(타이밍은 Phase 3).

---

## 11. 제어신호 종합 교차표

| 제어신호 | 생산 블록 | 소비 블록 | 값 의미 |
|---|---|---|---|
| `pc_src` | BCU(EX) | Next-PC MUX(IF) | 1=타겟, 0=순차 |
| `stall` | Cache Controller | PC·IF/ID·ID/EX·EX/MEM | 1=동결 |
| `flush` | Branch/Hazard | IF/ID·ID/EX | 1=버블 |
| `wake_up` | Cache Controller | 파이프라인 재개 | 1=리필 완료 |
| `we` | Cache Controller | Tag/Data Array | 1=라인 기록(Mealy=rvalid) |
| `reg_write` | Control Unit | Register File(WB) | 1=기록 |
| `result_src` | Control Unit | WB Result MUX | 00/01/10/11 |
| `alu_src` | Control Unit | EX Operand B MUX | 1=imm |
| `src_a_sel` | Control Unit | EX Operand A MUX | 1=PC |
| `alu_op` | Control Unit | ALU Control | 00/01/10/11 |
| `alu_ctrl` | ALU Control | ALU | 4-bit 연산 |
| `forward_a/b` | Forwarding Unit | EX Operand MUX, BCU | 00/01/10 소스 |
| `wstrb` | Write Strobe Gen | Data Array·W Master | 바이트 레인 |
| `mem_read`/`mem_write` | Control Unit | Cache Controller | 로드/스토어 |
| `branch`/`jump` | Control Unit | BCU | 분기/점프 |
| `csr_to_reg`/`csr_we`/`csr_cmd` | Control Unit | CSR File, WB MUX | CSR 읽기/쓰기/연산 |
| `illegal_instr` | Decoder(default) | Trap Unit | 1=불법명령 |
| `is_ecall`/`is_ebreak`/`is_mret` | Control Unit | Trap Unit | 트랩/복귀 |
| `trap_taken`/`trap_target` | Trap Unit | PC(IF), 전 파이프라인 flush | 1=트랩, 목적 PC |
| `csr_rdata` | CSR File | WB Result MUX | CSR 읽기값 |
| `fence_i`/`ext_inv` | Decoder(FENCE.I)/호스트 적재 | Cache Controller | I-Cache 무효화 요청 |
| `inv` | Cache Controller | Tag Array(I-Cache) | 전 Valid 클리어 |
| `iflush` | Cache Controller | IF/ID·ID/EX flush | FENCE.I 파이프라인 비움 |
