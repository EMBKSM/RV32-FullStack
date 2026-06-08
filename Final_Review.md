# 최종 아키텍처 완전성 검토 — 표준 RV32I 대비 누락 점검

> 목적: 현 문서 일습(`RV32_Pipeline_Spec.md`, `Movement.md`, `Phase3~6`)이 **표준 RISC-V(RV32I + 머신모드) CPU**로서 반드시 갖춰야 할 컴포넌트/기능을 빠짐없이 포함하는지 감사한다.
> 결론(요약): 데이터패스·해저드·캐시·AXI는 견고하나, base RV32I ISA의 일부(`SYSTEM`/`FENCE` 디코드)와 CSR·트랩·예외 체계가 누락이었다. **→ Category A 5개 항목은 전 문서에 반영 완료**(§9 반영 상태). Category B/C는 후속 권고로 유지.

---

## 1. 검토 요약 (Verdict)

| 카테고리 | 내용 | 건수 |
|---|---|---|
| A. 치명적 누락 (표준 필수) → **반영 완료** | base ISA 일부·CSR·트랩·예외·불법명령 | 5 (반영) |
| B. 중요/설계특화 권장 | I-Cache 일관성·인터럽트·정렬예외·트랩 플러시 | 4 |
| C. 표준이나 본 범위서 합리적 제외 | MMU·권한모드·확장(M/A/F/D/C)·PLIC·멀티하트 | 6 |
| D. 이미 완비 | 데이터패스·해저드·캐시·AXI·레지스터파일 등 | — |

→ **A 카테고리는 RTL 착수 전에 반드시 명세에 반영**해야 표준 호환·툴체인 호환이 보장된다.

## 2. 검토 방법

- 전 6개 문서를 키워드 감사(CSR/trap/interrupt/ECALL/EBREAK/FENCE/illegal/privilege/misalign/WFI)했고 전부 0건이었다.
- RV32I **비특권(Unprivileged) 기본 명령어 집합**과 **특권(Privileged) 머신모드 트랩 모델**을 기준으로 대조했다.

---

## 3. 카테고리 A — 치명적 누락 (표준 RV32I 필수) — **전 항목 반영 완료**

### A1. `SYSTEM` opcode(`1110011`) 미디코드 → ECALL / EBREAK 부재
- **누락:** 현 Decoder 제어표는 9개 opcode만 정의하고 `SYSTEM`을 다루지 않는다. `ECALL`·`EBREAK`는 **base RV32I에 포함된 명령**이다.
- **영향:** 베어메탈 프로그램이 런타임/호스트와 통신하거나 디버그 정지를 요청할 방법이 없다. 표준 미준수.
- **조치:** `SYSTEM` 디코드 추가, ECALL/EBREAK는 최소한 트랩(A4)으로 진입.

### A2. `FENCE`/`FENCE.I` opcode(`0001111`) 미디코드
- **누락:** `FENCE`(메모리 순서)·`FENCE.I`(명령어 페치 동기)는 base ISA 명령이다. 단순 인오더 코어에서 `FENCE`는 NOP 처리가 가능하나 **디코드는 되어야 하며**(아니면 불법명령), `FENCE.I`는 I-Cache 일관성(§B1)에 직결된다.
- **조치:** `FENCE` 디코드(코어 단순형은 NOP), `FENCE.I`는 I-Cache 무효화로 사상.

### A3. CSR 파일 + Zicsr 명령(CSRRW/RS/RC[I]) 부재
- **누락:** 제어·상태 레지스터(CSR) 파일과 `CSRR*` 명령이 없다. 표준 머신모드 CSR: `mstatus, mtvec, mepc, mcause, mtval, mie, mip, mscratch, misa, mhartid, mvendorid, marchid, mimpid`.
- **영향:** 트랩 벡터 설정·상태 저장/복원·머신정보 조회가 불가. **RISC-V 부트코드(crt0)와 GCC 런타임이 `mtvec`/`mstatus`/`mhartid` 존재를 전제**하므로, 이들이 없으면 표준 스타트업이 동작하지 않는다.
- **조치:** 최소 머신모드 CSR 파일 + Zicsr 6종 명령 명세 추가.

### A4. 트랩/예외 유닛(머신모드) 부재
- **누락:** 예외 검출·트랩 진입/복귀 경로가 없다. 필요: `mtvec`로 분기, `mepc`에 복귀 PC, `mcause`에 원인, `mstatus.MIE/MPIE/MPP` 갱신, 복귀는 `MRET`.
- **표준이 요구하는 동기 예외(최소):** 불법 명령, 명령 주소 정렬오류, 로드/스토어 주소 정렬오류, ECALL(M), EBREAK.
- **조치:** 트랩 유닛 + `MRET` 명세, 파이프라인 트랩 플러시(§B4) 연계.

### A5. 불법 명령(Illegal Instruction) 검출 부재
- **누락:** Decoder는 유효 opcode만 나열하고 **정의되지 않은 opcode/funct 조합에 대한 default 동작이 없다**. 표준 코어는 불법 명령을 검출해 예외(A4)를 발생시켜야 한다.
- **조치:** 디코더 default 경로 = `illegal_instr=1` → 트랩.

---

## 4. 카테고리 B — 중요 / 본 설계 특화 권장

### B1. I-Cache 일관성 ↔ UART 코드 적재 (FENCE.I / 무효화) — **본 프로젝트 직결** · [반영 완료]
- **문제:** 본 시스템은 UART로 기계어를 DDR에 적재한 뒤 실행한다. **I-Cache가 이전 프로그램의 라인을 유효(valid)로 보유**하고 있으면, 새 코드를 적재해도 CPU가 **스테일(stale) 명령어를 페치**한다. JTAG-less IDE의 "다운로드 후 실행" 워크플로우가 깨질 수 있다.
- **조치(반영됨):** Cache Controller에 `fence_i`/`ext_inv` 입력과 `inv`/`iflush` 출력을 추가하고, Tag Array에 `inv`(전 Valid 단일 사이클 클리어)를 추가했다. `FENCE.I`와 호스트 TLV INVALIDATE가 무효화를 트리거한다. RTL·모델·테스트(test_rv32 U-invalidation)·전 문서에 반영 완료.

### B2. 타이머 인터럽트 / CLINT(`mtime`/`mtimecmp`) + `mie`/`mip`
- **누락:** 비동기 인터럽트 경로가 없다. 임베디드 표준 구성은 최소 타이머 인터럽트를 포함한다.
- **조치:** CLINT(머신 타이머) + 인터럽트 플러밍(`mie/mip`, `mtvec` 비동기 진입). 최소 코어는 후순위 가능하나 "표준"엔 필요.

### B3. 정렬 오류(misalignment) 예외 정식화
- **현황:** `addr_aligner`의 misalign 검출이 **옵션 주석**으로만 존재.
- **조치:** 명령 주소(4B)·로드/스토어 자연정렬 위반을 정식 예외로 정의(A4 연계). 미지원 시 하드웨어가 정렬 보장하거나 예외 발생, 둘 중 하나를 명문화.

### B4. 트랩 시 파이프라인 플러시·우선순위
- **누락:** 현 흐름제어는 해저드/분기 stall·flush만 다루고, **트랩 발생 시 PC를 `mtvec`로 리다이렉트하고 후속 단을 비우는 경로**가 없다.
- **조치:** 트랩을 분기보다 높은 우선순위의 redirect/flush로 §10(Phase 3)·§12(스펙) 우선순위표에 추가.

---

## 5. 카테고리 C — 표준이나 본 베어메탈 범위에서 합리적 제외 (명시 권장)

다음은 일반 RISC-V엔 있으나, 본 프로젝트(RV32I 베어메탈, MMU·OS 제외)의 명시적 범위 결정으로 제외 가능하다. **단, "제외"임을 문서에 명문화**해야 한다.

| 항목 | 판단 | 비고 |
|---|---|---|
| MMU / 가상메모리 / 페이지폴트 | 제외 | 기획서가 명시적으로 범위 외 |
| S/U 권한 모드 | 제외(머신모드만) | 베어메탈 표준 관행 |
| M 확장(곱셈/나눗셈) | 제외(RV32I) | **주의: 실무 함정 §7 참조** |
| A/F/D/C 확장 | 제외 | RV32I 기본만 |
| PLIC(외부 인터럽트 컨트롤러) | 조건부 제외 | 외부 인터럽트 미사용 시 |
| 멀티하트 / 캐시 일관성 | 제외 | 단일 코어 |

## 6. 카테고리 D — 이미 완비(확인)

5단 데이터패스(IF/ID/EX/MEM/WB), 4개 경계 레지스터, 해저드(Forwarding Unit·Hazard Unit)·분기 해소(BCU), Direct-Mapped I/D 캐시 + AXI4(AW/W/B/AR/R) 32-bit, 레지스터 파일(x0=0, write-first), 즉치 생성(I/S/B/U/J), 분기/점프(JAL/JALR), LUI/AUIPC, 서브워드 로드/스토어(정렬·wstrb). → 자료흐름·제어는 견고.

---

## 7. 실무 함정 (반드시 인지)

- **툴체인 `-march`:** 코어가 RV32I 기본이므로, GCC를 `-march=rv32i -mabi=ilp32`로 컴파일해야 한다. 기본 멀티립(예: rv32imac)으로 빌드하면 **곱셈/나눗셈/원자/압축 명령이 섞여 불법 명령**이 된다(A5와 결합 시 트랩). 크로스컴파일 파이프라인에 플래그를 고정할 것.
- **부트(crt0):** 표준 스타트업은 `mtvec`·`mstatus`·`mhartid`를 건드린다. CSR 부재 시 커스텀 최소 crt0가 필요하다(A3 해소 시 표준 crt0 사용 가능).

## 8. 권고 조치 (우선순위)

1. (A1·A2·A5) Decoder에 `SYSTEM`/`FENCE` 디코드 + 불법명령 default 추가 → base RV32I 완성.
2. (A3·A4) 최소 머신모드 CSR 파일 + 트랩/예외 유닛 + `MRET` 명세화.
3. (B1) I-Cache 무효화/`FENCE.I` 경로 — UART 적재 워크플로우 정합.
4. (B2·B3·B4) 타이머 인터럽트·정렬 예외·트랩 플러시 보강.
5. (C·§7) 제외 항목과 툴체인 플래그를 범위 문서에 명문화.

---

## 9. Category A 반영 상태 (완료)

| 항목 | 반영 위치 | 검증 |
|---|---|---|
| A1 SYSTEM(ECALL/EBREAK/MRET) 디코드 | 스펙 §4.2/§4.2.1, Movement §4.6 | verify_spec opcode `1110011`, verify_docs SYSTEM |
| A2 FENCE/FENCE.I 디코드 | 스펙 §4.2.1, Movement §4.6 | verify_spec opcode `0001111`, verify_docs FENCE |
| A3 CSR File + Zicsr | 스펙 §4.6, Movement §4.5 | verify_spec "CSR File", verify_docs CSR |
| A4 Trap/Exception Unit(mtvec/mepc/mcause, MRET) | 스펙 §6.7/§10.3, Movement §7.3 | verify_spec "Trap & Exception Unit", verify_docs Trap |
| A5 불법명령 검출(디코더 default) | 스펙 §4.2.1, Movement §4.6 | illegal_instr 명시 |
| **B1 I-Cache 무효화(추가 반영)** | 스펙 §2.4.2/§2.4.4, Movement §3.5/§3.7, RTL(tag_array/cache_controller) | verify_spec/docs 무효화·ext_inv, test_rv32 U-invalidation |

데이터플로우(Phase 3 §10 트랩 경로)·인터페이스(Phase 4 §4.5 CSR/Trap)·구조(Phase 5 §2.5)·검증(Phase 6 U8) 전반에 반영되었으며, 검증 하네스가 전 문서에서 CSR·Trap·SYSTEM·FENCE 존재를 필수 점검한다. Category B(특히 B1 I-Cache 무효화)·C는 후속 권고로 남는다.
