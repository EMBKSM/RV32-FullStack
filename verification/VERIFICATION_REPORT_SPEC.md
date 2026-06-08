# RV32_MEM_WB_Spec.md — 문서 검증 리포트

대상: `RV32_Pipeline_Spec.md` (구 `RV32_MEM_WB_Spec.md`) (MEM/WB 스테이지 컴포넌트 명세)
방법: 기계적 재검증 10회 + 표준/RTL 대조 수동 리뷰
결과: **수정 후 10/10 통과, 239건 점검 ALL GREEN**

---

## 1. 요약

| 단계 | 통과 | 점검 | 비고 |
|---|---|---|---|
| 문서 초기 상태 | 6 / 10 | 238 | 실제 결함 4종 검출 |
| **수정 후** | **10 / 10** | 239 | ALL GREEN |

문서를 10개 관점에서 재검증해 **실제 결함 4건(렌더링·일관성·완전성·오타)** 을 발견·수정하고, 명확성 개선 3건을 함께 반영했다. RV32I 인코딩·주소 산술·AXI4 상수·신호 폭·컴포넌트 커버리지 등 핵심 기술 내용은 모두 정확함을 확인했다.

> 방법론 주: 검증 스크립트(`verification/verify_spec.py`) 자체도 1차 작성 시 오탐 2건(Iter 08 섹션 추출기, Iter 09 열 인덱스)이 있어 먼저 교정했다. 위 "문서 초기 상태 6/10"은 검증기를 교정한 뒤의 순수 문서 기준 결과다.

---

## 2. 검증 방법

`verify_spec.py` 가 문서를 직접 파싱해 다음 10개 반복을 수행한다. 의미적(설계 판단) 항목은 표준 문서(RISC-V Unprivileged ISA, AMBA AXI4)와 리포지토리 RTL을 수동 대조했다.

실행:
```bash
python3 verification/verify_spec.py     # exit 0 = ALL GREEN
```

---

## 3. 반복별 결과

| # | 검증 항목 | 점검 | 초기 | 수정 후 |
|---|---|---|---|---|
| 01 | 마크다운 표 무결성(열 수·이스케이프 안 된 파이프) | 177 | **FAIL** | PASS |
| 02 | 캐시 주소 필드 산술(20+8+4=32, 4KB/16B=256라인 등) | 14 | PASS | PASS |
| 03 | RV32I 로드 funct3 인코딩(LB/LH/LW/LBU/LHU) | 8 | PASS | PASS |
| 04 | AXI4 상수(INCR=01, AxSIZE=010, AxLEN=beats-1, RESP=00, WSTRB=4) | 6 | PASS | PASS |
| 05 | 신호 비트폭 일관성(rd5·funct3 3·data32·tag20·idx8·line128) | 6 | PASS | PASS |
| 06 | 다이어그램 컴포넌트 커버리지(14개 블록) | 14 | PASS | PASS |
| 07 | 리셋 극성 관례(active-high `reset`) | 3 | **FAIL** | PASS |
| 08 | 상태 보유 블록 reset 포트 존재 | 4 | **FAIL** | PASS |
| 09 | 파이프라인 통과표 일관성(funct3·Data2·Read Data) | 3 | PASS | PASS |
| 10 | 상호참조 & 오타 스캔 | 4 | **FAIL** | PASS |

---

## 4. 발견 결함 및 수정

| ID | 심각도 | 위치 | 내용 | 수정 |
|---|---|---|---|---|
| DOC-001 | High(렌더링) | §3.7 FSM 표 | 표 셀 내부에 이스케이프되지 않은 `\|`(`mem_read\|mem_write`)가 있어 표 열이 깨짐 | `mem_read` 또는 `mem_write` 로 치환 |
| DOC-002 | Medium(일관성) | §0.3, §2, §3.1, §3.7, §4 | `rst_n`(active-low)로 표기 — 프로젝트 RTL은 전부 active-high `reset`(`reset='1'`) | 전부 `reset`(active-high)로 통일, §0.3에 리셋 관례 명문화 |
| DOC-003 | Medium(완전성) | §3.3 Tag Array | 포트 목록에 `reset` 누락 — Valid 비트를 리셋 시 클리어할 수 없음(정합성 문제) | `reset` 포트 추가 + 동작에 "Valid 전체 0 클리어" 명시 |
| DOC-004 | Low(완전성) | §3.7 동작 | 스토어 hit 시 Dirty 비트 세팅 경로 미기술 | `COMPARE`에서 `tag_we`+`dirty_in=1` 로 Dirty 세팅 후 IDLE 복귀 명시 |
| DOC-005 | Low(명확성) | §3.4 Data Array | `rdata`/`word_out` 행 설명에 "또는"이 매달려 모호 | 라인 단위(128b)/워드 단위(32b) 용도 구분 명확화 |
| DOC-006 | Low(오타) | §4 MEM/WB | 다이어그램 라벨 오타 `ALU Reasult` 그대로 차용 | `ALU Result` 로 정정 |
| DOC-007 | Low(명확성) | §3.9.2/3.9.4 | `RDATA/WDATA` 폭을 `32(/64)`로 모호 표기(고정 AxLEN=3/AxSIZE=010과 충돌 소지) | 32-bit 기준 확정, 64-bit HP 포트는 재조정 옵션으로 주석화 |

---

## 5. 정확성 확인 항목 (수정 불필요)

- **RV32I 로드 funct3**: LB=000, LH=001, LW=010, LBU=100, LHU=101 — ISA 명세와 정확히 일치. 예약 코드(011/110/111)를 로드로 오기한 곳 없음.
- **주소 필드 산술**: TAG20+INDEX8+OFFSET4=32, 4KB/16B=256라인, INDEX=log2(256)=8, OFFSET=log2(16)=4 — 전부 정합. 분해도 비트필드([31:12]/[11:4]/[3:2]/[1:0])도 일치.
- **AXI4 상수**: AxBURST INCR=01, AxSIZE=010(4B/beat), AxLEN=beats-1=3(4-beat), RRESP/BRESP OKAY=00, WSTRB=4비트 — AMBA AXI4 표준과 일치.
- **신호 폭**: rd 5b, funct3 3b, 데이터 버스 32b, Tag 20b, Index 8b, 캐시 라인 128b — 문서 전반 일관.
- **컴포넌트 커버리지**: 다이어그램 14개 블록 전부 섹션화(100%).
- **파이프라인 통과표(§7)**: funct3·Data2는 WB로 전달 안 됨, Read Data는 MEM에서 생성(EX/MEM 부재) — 정합.
- **MemtoReg MUX 극성**: `WriteData = MemtoReg ? ReadData : ALU_Result` 와 "MemtoReg=1→메모리" 설명 일치.

---

## 6. RTL 대조 (정보성 — 오류 아님, 범위 차이)

본 명세는 **브라우저 다이어그램의 MEM 스테이지 데이터 캐시**(스토어 경로·Data2·MemWrite 포함, Write-Back)를 기준으로 한다. 현재 리포지토리의 `ip_workspace/0_IF/` 캐시는 별개의 **읽기 전용 명령어 캐시(I-Cache) 프론트엔드**로 다음이 다르다.

- FSM 상태명: 명세(IDLE/COMPARE/WRITE_BACK/ALLOCATE/REFILL) ↔ RTL(S_IDLE/S_SEND_AR/S_WAIT_R/S_UPDATE_CACHE/S_WAKE_UP).
- RTL은 단일 비트 리필·`AR/R`만 사용, Dirty/Write-Back/`AW/W/B` 없음(I-Cache라 의도적).

→ 데이터 캐시 명세로서 위 항목은 **정상(범위 차이)**. 한편 `addr_aligner`(tag20/idx8/offset4)·`comparator`·`tag_array`의 포트 폭은 명세와 **정합**함을 확인했다.

---

## 7. 산출물

- `RV32_Pipeline_Spec.md` — 5단계 파이프라인 전체 명세(검증 통과본). 구 `RV32_MEM_WB_Spec.md`는 리다이렉트 스텁으로 남아 있으니 수동 삭제 가능.
- `verification/verify_spec.py` — 10-iteration 문서 검증 스크립트(재실행 가능).
- `verification/VERIFICATION_REPORT_SPEC.md` — 본 리포트.


---

## 8. 개정 — IF/ID/EX 스테이지 추가 및 파일명 변경

요청에 따라 누락돼 있던 **IF·ID·EX 스테이지**와 4개 경계 레지스터(IF/ID·ID/EX)를 추가하고, 범위가 5단계 전체로 확장되어 파일명을 `RV32_MEM_WB_Spec.md` → **`RV32_Pipeline_Spec.md`** 로 변경했다.

- **IF 스테이지(§2):** 리포지토리 실제 RTL(`ip_workspace/0_IF/`) 기준 — PC Register/PC Adder/Next-PC MUX와 I-Cache(Addr Aligner·Tag Array·Comparator·Cache Controller FSM)의 포트를 VHDL과 일치시켜 기술. 명령어 데이터 어레이·AXI AR/R 마스터는 *보충*(RTL 미구현) 표기.
- **ID 스테이지(§4):** 명령어 필드 추출, Control Unit(주요 9개 opcode 제어표), Register File, Immediate Generator(I/S/B/U/J), 로드-유즈 해저드.
- **EX 스테이지(§6):** ALU, ALU Control, Operand MUX, Branch Unit(분기 funct3 6종), 포워딩 MUX.
- **경계 레지스터:** IF/ID(§3), ID/EX(§5). 기존 EX/MEM·MEM/WB는 §7·§9로 재배치.
- **기존 MEM/WB 내용은 검증 통과본을 그대로 재사용**(§8·§9·§10), 내부 절 번호·상호참조(예: `8.2~8.9`, `§8.9.5`)를 자동 재정렬.

검증기(`verify_spec.py`)를 신규 구조에 맞춰 갱신하고 IF/ID/EX 점검(분기 funct3, opcode 9종, 즉치 비트, 신규 컴포넌트/레지스터 reset 포트, 5열 통과표)을 추가했다.

**확장 후 재검증 결과: 10/10 반복, 442건 점검 ALL GREEN.** (표 무결성 45개 표, 컴포넌트/opcode/즉치 35건 포함.) IF 스테이지 포트는 실제 VHDL과 일치함을 확인했다.

> 미구현 보충 항목(ID/EX RTL, 포워딩·해저드 유닛, I-Cache 데이터 어레이/AXI 마스터, 분기 해소 스테이지)은 문서 §13에 정리.
