# IF~WB Write-Path 통합 수용 테스트 명세 (ATDD / Shift-Left)

> 방법: **Shift-Left** — 통합 RTL(`rv32_core.vhd`)을 작성하기 **전에** 수용 기준(Acceptance Criteria)과 30개 수용 테스트를 먼저 확정한다.
> 대상: IF→ID→EX→MEM→**WB(register write-back)** 5단 파이프라인 통합 데이터패스.
> 명세 출처: `RV32_Pipeline_Spec.md` §1·§11·§12, `Movement.md`, `Verification_Handover.md` U7.
> 절차(ATDD): (1) 본 수용 테스트 정의 → (2) `tb_rv32_core_if_wb.sv`(SystemVerilog)·`run_ifwb_core.py`(사이클정확 모델+독립 ISS 골든) 구현 → (3) 통과하도록 `rv32_core.vhd` 구현 → (4) 30 iteration + 랜덤 counter-example + 결함주입.

---

## 1. DUT 계약 (통합 코어 인터페이스)

`rv32_core` 는 이상적(single-cycle hit) 명령/데이터 메모리를 외부 포트로 두고, IF~WB 레지스터 기록 경로를 통합한다. 캐시/AXI/CSR/Trap은 본 통합 범위 밖이며 각각 별도 검증됨(`VERIFICATION_REPORT*.md`).

| 포트 | 방향 | 폭 | 의미 |
|---|---|---|---|
| `clk`, `reset` | in | 1 | 클럭 / active-high 비동기 리셋 |
| `imem_addr` | out | 32 | 명령 인출 주소(=PC) |
| `imem_rdata` | in | 32 | 인출 명령어(조합 read, 항상 hit) |
| `dmem_addr` | out | 32 | 데이터 접근 주소(=ALU Result) |
| `dmem_wdata` | out | 32 | 레인 정렬된 스토어 데이터 |
| `dmem_wstrb` | out | 4 | 바이트 스트로브(SB/SH/SW) |
| `dmem_we` | out | 1 | 스토어 enable |
| `dmem_re` | out | 1 | 로드 enable |
| `dmem_rdata` | in | 32 | 워드 read 데이터(조합) |
| `dbg_commit` | out | 1 | WB 단 레지스터 기록 커밋(스코어보드용) |
| `dbg_rd` / `dbg_wdata` | out | 5 / 32 | 커밋된 목적지/데이터 |
| `dbg_reg_addr` | in | 5 | 디버그 레지스터 읽기 주소 |
| `dbg_reg_data` | out | 32 | 해당 아키텍처 레지스터 값(shadow) |

## 2. 수용 기준 (불변식)

- **AC-1 (정확성/등가):** 임의의 프로그램에 대해, 파이프라인이 산출하는 최종 아키텍처 레지스터 상태는 동일 프로그램을 명령 단위로 순차 실행한 **독립 ISS**의 결과와 비트 단위로 일치한다(포워딩/해저드/분기가 가시적 상태를 바꾸지 않음).
- **AC-2 (x0 고정):** `x0`은 항상 0. `x0`을 목적지로 한 기록은 무시.
- **AC-3 (포워딩):** 연속/1-간격 종속(RAW)은 버블 없이 EX/MEM·MEM/WB 바이패스로 해소(우선순위 EX/MEM > MEM/WB > RF).
- **AC-4 (로드-유즈 해저드):** 로드 결과를 직후 명령이 사용하면 정확히 1 버블 후 MEM/WB 포워딩으로 올바른 값.
- **AC-5 (제어 해저드):** 분기/점프 성립 시 IF/ID·ID/EX 2 버블 flush, `pc_src`/`target_addr`로 IF 리다이렉트(정적 not-taken). 미성립 시 순차 진행.
- **AC-6 (링크값):** JAL/JALR은 `rd ← PC+4`, 점프 타겟은 BCU 규약(JALR=`(rs1+imm)&~1`).
- **AC-7 (메모리 정렬):** 로드는 `funct3`로 부호/0 확장(LB/LH/LW/LBU/LHU), 스토어는 `wstrb`로 바이트 선택(SB/SH/SW). 라운드트립(store→load) 값 보존.
- **AC-8 (결정성):** 동일 프로그램·동일 리셋에서 결과는 결정적.

## 3. 수용 테스트 케이스 (AT-01 ~ AT-30)

각 directed 케이스의 기대 레지스터 값은 **독립 산정**(손계산 상수). 프로그램은 `imem` 워드 주소 0부터 적재, `reset` 후 충분 사이클 실행 뒤 아키텍처 레지스터를 점검. 데이터 영역 베이스는 `0x40`.

| ID | 검증 포커스 | 프로그램(요약) | 기대 결과 |
|---|---|---|---|
| AT-01 | ADDI / WB 기록 | `addi x1,x0,5` | x1=0x00000005 |
| AT-02 | 부호확장 즉치 | `addi x2,x0,-1` | x2=0xFFFFFFFF |
| AT-03 | R-type ADD + 포워딩 | `addi x1,x0,7; addi x2,x0,11; add x3,x1,x2` | x1=7, x2=11, x3=18 |
| AT-04 | SUB | `addi x1,x0,20; addi x2,x0,8; sub x3,x1,x2` | x3=12 |
| AT-05 | AND/OR/XOR 즉치 | `addi x1,x0,0xF0; andi x2,x1,0xFF; ori x3,x1,0x0F; xori x4,x1,0xFF` | x1=0xF0, x2=0xF0, x3=0xFF, x4=0x0F |
| AT-06 | SLTI / SLTIU 발산 | `addi x1,x0,-1; slti x2,x1,0; sltiu x3,x1,0` | x2=1, x3=0 |
| AT-07 | SLLI/SRLI/SRAI | `addi x1,x0,-16; srai x2,x1,2; srli x3,x1,2; slli x4,x1,1` | x2=0xFFFFFFFC, x3=0x3FFFFFFC, x4=0xFFFFFFE0 |
| AT-08 | LUI (Bpass) | `lui x1,0xABCDE` | x1=0xABCDE000 |
| AT-09 | AUIPC (PC+imm) | `auipc x1,0x12345` @PC=0 | x1=0x12345000 |
| AT-10 | LUI+ADDI 32b 상수, 포워딩 | `lui x1,0x12345; addi x1,x1,0x678` | x1=0x12345678 |
| AT-11 | EX/MEM 포워딩(연속) | `addi x1,x0,10; addi x2,x1,20` | x1=10, x2=30 |
| AT-12 | MEM/WB 포워딩(1-간격) | `addi x1,x0,10; nop; add x2,x1,x1` | x2=20 |
| AT-13 | 양 피연산자 다른 스테이지 포워딩 | `addi x1,x0,3; addi x2,x0,4; add x3,x1,x2` | x3=7 |
| AT-14 | x0 고정 | `addi x0,x0,123; add x1,x0,x0; addi x2,x0,5` | x0=0, x1=0, x2=5 |
| AT-15 | SW→LW 라운드트립 | `addi x2,x0,0x40; addi x1,x0,0x123; sw x1,0(x2); lw x3,0(x2)` | x3=0x123 |
| AT-16 | 로드-유즈 해저드(1 버블) | `addi x2,x0,0x40; addi x5,x0,0x55; sw x5,0(x2); lw x1,0(x2); add x3,x1,x1` | x1=0x55, x3=0xAA |
| AT-17 | SB / LBU | `addi x2,x0,0x40; addi x5,x0,0xAB; sb x5,0(x2); lbu x1,0(x2)` | x1=0xAB |
| AT-18 | SH / LH(부호) / LHU | `addi x5,x0,-1; addi x2,x0,0x40; sh x5,0(x2); lh x1,0(x2); lhu x3,0(x2)` | x1=0xFFFFFFFF, x3=0x0000FFFF |
| AT-19 | BEQ taken(전방, skip) | `addi x1,x0,5; addi x2,x0,5; beq x1,x2,+8; addi x3,x0,99; addi x4,x0,7` | x3=0(skip), x4=7 |
| AT-20 | BEQ not-taken | `addi x1,x0,5; addi x2,x0,6; beq x1,x2,+8; addi x3,x0,99; addi x4,x0,7` | x3=99, x4=7 |
| AT-21 | BNE taken | `addi x1,x0,5; addi x2,x0,6; bne x1,x2,+8; addi x3,x0,99; addi x4,x0,1` | x3=0(skip), x4=1 |
| AT-22 | BLT(부호) taken | `addi x1,x0,-1; addi x2,x0,1; blt x1,x2,+8; addi x3,x0,99; addi x4,x0,2` | x3=0(skip), x4=2 |
| AT-23 | BLTU(무부호) not-taken | `addi x1,x0,-1; addi x2,x0,1; bltu x1,x2,+8; addi x3,x0,99; addi x4,x0,3` | x3=99, x4=3 |
| AT-24 | 포워딩→BCU 비교 입력 | `addi x1,x0,5; addi x2,x1,0; beq x1,x2,+8; addi x3,x0,99; addi x4,x0,4` | x3=0(skip), x4=4 |
| AT-25 | JAL 링크+점프 | `jal x1,+8` @0; `addi x2,x0,99` @4; `addi x3,x0,7` @8 | x1=4(link), x2=0(skip), x3=7 |
| AT-26 | JALR 링크+base 포워딩 | `addi x1,x0,12` @0; `jalr x2,x1,0` @4; `addi x3,x0,99` @8; `addi x4,x0,5` @12 | x2=8(link), x3=0(skip), x4=5 |
| AT-27 | 3단 포워딩 체인 | `addi x1,x0,1; addi x2,x1,1; addi x3,x2,1; addi x4,x3,1` | x1=1,x2=2,x3=3,x4=4 |
| AT-28 | 후방분기 루프(합 4..1) | `x1=0; x2=4; L: x1+=x2; x2-=1; bne x2,x0,L` | x1=10, x2=0 |
| AT-29 | 2×(SW/LW), 주소 분리 | `x2=0x40;x3=0x44;x10=0xAA;x11=0xBB; sw x10,0(x2); sw x11,0(x3); lw x4,0(x2); lw x5,0(x3)` | x4=0xAA, x5=0xBB |
| AT-30 | **랜덤 counter-example** | 랜덤 RV32I 프로그램(R/I/load/store/전방분기/lui/auipc/jal, x1..x8) × 다수 시드 | 파이프라인 최종 레지스터 = **독립 ISS**와 전수 일치 |

> AT-30 은 무작위 프로그램(기본 2,000개 × 각 40 명령)을 명령단위 순차 실행 ISS와 대조하는 **counter-example 탐색**이다. 단 1개라도 불일치하면 반례(프로그램·레지스터)를 출력하고 FAIL.
> AT-06/AT-23 은 부호(SLT/BLT)와 무부호(SLTU/BLTU)가 동일 입력에서 갈리는 대표 케이스다.

## 4. 결함 주입(Counter-example) 시연

`run_ifwb_core.py --bug forward|hazard|branch|x0` 로 통합 제어에 의도적 결함을 주입하면, AT-30(및 해당 directed AT)이 **반례를 출력하고 FAIL** 해야 한다 — 테스트가 실제로 통합 버그를 잡는지(검증 유효성)를 입증한다.

| 주입 | 결함 | 잡히는 케이스 |
|---|---|---|
| `forward` | EX 바이패스 비활성(항상 RF 값) | AT-11/12/13/27/30 |
| `hazard` | load-use stall 누락 | AT-16/30 |
| `branch` | 분기 성립 시 flush 누락 | AT-19/21/22/25/28/30 |
| `x0` | x0 기록 허용(하드와이어 해제) | AT-14/30 |
