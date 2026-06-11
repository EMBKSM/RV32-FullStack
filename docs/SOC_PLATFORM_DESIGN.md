# RV32 호스트제어 SoC 플랫폼 설계 (PS-UART + AXI-Lite + MMIO)

PC가 UART로 RISC-V 프로그램/명령을 보내면, Zynq PS(ARM)가 받아서 PL의 rv32 CPU에
적재·실행·관찰하고, 매 실행의 상태변화를 UART로 PC에 회신한다. CPU는 LED/스위치/버튼을
직접 제어(MMIO)한다.

## 1. 시스템 구조
```
PC ⇄ USB-UART ⇄ Zynq PS (UART1@MIO, ARM C SW)
                    │ M_AXI_GP0 (AXI4-Lite, 32b)
                    ▼
  ┌──────────────────────── PL ─────────────────────────────┐
  │ rv32_ctrl_axi  (AXI-Lite slave; 레지스터맵 §4)            │
  │   ├ imem/dmem 적재 포트 구동                              │
  │   ├ cpu_reset / run / step 제어                           │
  │   └ dbg_reg/pc/commit 읽기 (CPU dbg_* 노출)               │
  │        │                                                  │
  │   imem(BRAM) ─I$─ rv32_core ─D$─ dmem(BRAM)               │
  │                       │ dmem 데이터버스                    │
  │                  mmio_bridge (캐시 우회 디코드, §3)        │
  │                       ├ 0x1000_0000 LED  (W)              │
  │                       ├ 0x1000_0004 SW   (R)              │
  │                       └ 0x1000_0008 BTN  (R)              │
  └──────────────────────────────────────────────────────────┘
```
PS가 UART 프로토콜·로더·diff 리포트를 담당(소프트웨어), PL은 AXI-Lite 슬레이브로
"메모리적재 + 실행제어 + 상태읽기"만 제공. 역할 분리가 깔끔함.

## 2. 메모리 맵 (CPU 관점)
| 영역 | 범위 | 용도 |
|---|---|---|
| 명령 RAM (I) | 0x0000_0000 ~ (Harvard, 페치 전용) | I$ 백킹 |
| 데이터 RAM | 0x0000_0000 ~ 0x0000_3FFF | D$ 백킹(캐시됨) |
| MMIO | 0x1000_0000 ~ 0x1000_00FF | 주변장치(캐시 우회) |

> MMIO는 **캐시에 넣으면 안 됨**(장치 레지스터). 그래서 D-버스에서 주소를 먼저 디코드해
> MMIO면 `mmio_bridge`로(1사이클, no-stall), 아니면 D$로 보낸다. rword/stall은 다시 mux.

## 3. MMIO 맵 (CPU가 store/load로 제어)
| 주소 | R/W | 비트 | 기능 |
|---|---|---|---|
| 0x1000_0000 | W | [N-1:0] | LED 출력 (Zybo Z7-20: LED 4개 → [3:0]) |
| 0x1000_0004 | R | [N-1:0] | 스위치 입력 (SW 4개 → [3:0]) |
| 0x1000_0008 | R | [N-1:0] | 버튼 입력 (BTN 4개 → [3:0]) |
예: `li x1,0xF; li x2,0x10000000; sw x1,0(x2)` → LED 4개 점등.
   `li x2,0x10000004; lw x3,0(x2)` → x3 = 스위치 값.

## 4. AXI-Lite 제어/상태 레지스터맵 (PS 관점, 슬레이브 베이스 = M_AXI_GP0 할당)
| 오프셋 | R/W | 이름 | 설명 |
|---|---|---|---|
| 0x00 | W | CTRL | b0=cpu_reset, b1=run_en, b2=step(1펄스), b3=clr_commitcnt |
| 0x04 | R | STATUS | b0=halted(자가점프 감지), b1=commit_valid, b2=running |
| 0x08 | W | IMEM_ADDR | 명령 적재 주소(바이트) |
| 0x0C | W | IMEM_WDATA | 쓰면 IMEM_ADDR에 1워드 적재(프리로드 펄스) |
| 0x10 | W | DMEM_ADDR | 데이터 적재 주소 |
| 0x14 | W | DMEM_WDATA | 쓰면 DMEM_ADDR에 1워드 적재 |
| 0x18 | W | REG_ADDR | 읽을 레지스터 번호(0~31) → dbg_reg_addr |
| 0x1C | R | REG_RDATA | dbg_reg_data (해당 레지스터 값) |
| 0x20 | R | PC | 현재/마지막 PC |
| 0x24 | R | LAST_RD | 마지막 커밋의 rd 번호 (dbg_rd) |
| 0x28 | R | LAST_WDATA | 마지막 커밋의 기록값 (dbg_wdata) |
| 0x2C | R | COMMIT_CNT | 리타이어한 명령 수(스텝/런 판단용) |
| 0x30 | W | DMEM_RADDR | 데이터 메모리 읽기 주소(바이트) |
| 0x34 | R | DMEM_RDATA | 백킹 데이터 RAM[RADDR] (※ write-back 주의: D$의 더티 라인은 아직 RAM에 없을 수 있음 — 정확한 덤프는 프로그램 halt 후, 가능하면 캐시가 비워진 상태에서) |

**상태변화(diff) 회신 방식**: PS가 STEP 1회 → COMMIT_CNT 증가 확인 → LAST_RD/LAST_WDATA
읽어 "x{rd} <= {wdata}" 한 줄을 UART로 PC에 송신. (레지스터 전체 스냅샷 비교도 REG_ADDR/
REG_RDATA로 가능.) "프로그램 일괄"은 run_en 후 halted까지, 커밋 로그를 모아 회신.

## 5. 빌드 단계
- **A. PL 플랫폼 RTL**: `mmio_bridge` + `gpio_io`, 합성용 RAM(기존 axi_slave_mem 재사용 가능),
  `rv32_ctrl_axi`(AXI-Lite 슬레이브), `rv32_platform`(합성용 PL 탑). + 시뮬 TB.
- **B. Vivado BD**: Zynq7 PS(UART1, M_AXI_GP0) + AXI Interconnect → `rv32_platform`(AXI-Lite).
  LED/SW/BTN은 PL 외부핀(XDC). 래퍼 생성·주소할당.
- **C. PS 소프트웨어(C)**: 베어메탈, UART 명령 파서(LOAD/RUN/STEP/RESET/DUMP), AXI-Lite
  레지스터 구동, diff 회신.
- **D. 제약·비트스트림·보드**: Zybo Z7-20 XDC(clk 125MHz, LED/SW/BTN; UART는 PS MIO라 PL핀
  불필요), Synthesis→Implementation→Bitstream→Vitis→보드 검증.

## 6. 설계 노트 / 결정사항
- CPU의 기존 `dbg_commit/dbg_rd/dbg_wdata/dbg_reg_addr/dbg_reg_data`를 그대로 활용
  (상태읽기·diff가 설계 단계부터 준비돼 있었음).
- 단일스텝 = `run_en`을 1사이클만 또는 step 펄스로 CPU clock-enable 게이팅. (코어는 mem_stall로
  freeze 가능하므로, step은 "1 명령 리타이어까지 진행 후 정지"로 구현: COMMIT_CNT 증가 감지.)
- 명령 적재 중에는 cpu_reset=1로 코어 정지, I$/D$ 무효 상태에서 RAM 적재 → reset 해제 시
  콜드미스로 새 프로그램 페치(코히런시 문제 없음). 데이터 재적재 시에도 reset 동안.
- 메모리는 합성 가능(BRAM). axi_slave_mem은 prog 포트가 있어 적재경로로 그대로 쓸 수 있고
  합성도 됨(초기화 RAM). 단, 캐시 라이트백 데이터가 RAM에 있으므로 데이터 덤프는 REG 경유 권장.
```
```
