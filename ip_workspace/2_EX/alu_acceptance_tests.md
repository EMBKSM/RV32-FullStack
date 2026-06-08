# ALU 수용 테스트 명세 (ATDD / Shift-Left)

> 방법: **Shift-Left** — RTL 작성 전에 수용 기준(Acceptance Criteria)을 먼저 확정한다.
> 대상: `alu.vhd` (EX 스테이지 산술논리 유닛). 명세 출처: `Movement.md` §5.4, `RV32_Pipeline_Spec.md` §6.1.
> 절차(ATDD): (1) 본 수용 테스트 정의 → (2) `tb_alu.sv`(SystemVerilog)·`run_alu_at.py`(실행 골든모델)로 테스트 구현 → (3) 통과하도록 `alu.vhd` 구현 → (4) 30회 반복/counter-example.

## 1. DUT 계약 (인터페이스)

| 포트 | 방향 | 폭 | 의미 |
|---|---|---|---|
| `a` | in | 32 | 피연산자 A |
| `b` | in | 32 | 피연산자 B (시프트량은 `b[4:0]`) |
| `alu_ctrl` | in | 4 | 연산 선택 |
| `result` | out | 32 | 연산 결과 |
| `zero` | out | 1 | `result == 0` |

`alu_ctrl` 인코딩: `0000`ADD `0001`SUB `0010`AND `0011`OR `0100`XOR `0101`SLL `0110`SRL `0111`SRA `1000`SLT(signed) `1001`SLTU `1010`Bpass(b 통과) / 그 외=0(default).

## 2. 수용 기준 (불변식)

- AC-1: 순수 조합 — 입력 변화 후 결과는 동일 평가에서 확정(레지스터 없음).
- AC-2: 시프트량은 `b[4:0]`로 마스킹(RV32I shamt 규칙).
- AC-3: SRA는 산술(부호 확장), SRL은 논리.
- AC-4: SLT는 부호 비교, SLTU는 무부호 비교 — 동일 입력에서 서로 다를 수 있음.
- AC-5: `zero = (result == 0)` 모든 연산에서 일관.
- AC-6: 정의되지 않은 `alu_ctrl`은 `result=0`(결정적).

## 3. 수용 테스트 케이스 (AT-01 ~ AT-30)

각 케이스는 given(a,b,ctrl) → expected(result,zero) 형식. 기대값은 **독립 산정**(골든모델과 무관한 상수).

| ID | 연산 | a | b | ctrl | expected result | zero |
|---|---|---|---|---|---|---|
| AT-01 | ADD | 0x00000003 | 0x00000004 | 0000 | 0x00000007 | 0 |
| AT-02 | ADD wrap | 0xFFFFFFFF | 0x00000001 | 0000 | 0x00000000 | 1 |
| AT-03 | ADD (-1)+2 | 0xFFFFFFFF | 0x00000002 | 0000 | 0x00000001 | 0 |
| AT-04 | SUB | 0x0000000A | 0x00000003 | 0001 | 0x00000007 | 0 |
| AT-05 | SUB to 0 | 0x00000005 | 0x00000005 | 0001 | 0x00000000 | 1 |
| AT-06 | SUB underflow | 0x00000000 | 0x00000001 | 0001 | 0xFFFFFFFF | 0 |
| AT-07 | AND | 0xF0F0F0F0 | 0x0FF00FF0 | 0010 | 0x00F000F0 | 0 |
| AT-08 | OR | 0xF0F0F0F0 | 0x0F0F0F0F | 0011 | 0xFFFFFFFF | 0 |
| AT-09 | XOR self | 0xAAAAAAAA | 0xAAAAAAAA | 0100 | 0x00000000 | 1 |
| AT-10 | SLL 1 | 0x00000001 | 0x00000001 | 0101 | 0x00000002 | 0 |
| AT-11 | SLL 31 | 0x00000001 | 0x0000001F | 0101 | 0x80000000 | 0 |
| AT-12 | SLL mask(32→0) | 0x00000001 | 0x00000020 | 0101 | 0x00000001 | 0 |
| AT-13 | SRL 4 | 0x000000F0 | 0x00000004 | 0110 | 0x0000000F | 0 |
| AT-14 | SRL MSB | 0x80000000 | 0x00000001 | 0110 | 0x40000000 | 0 |
| AT-15 | SRA neg | 0x80000000 | 0x00000001 | 0111 | 0xC0000000 | 0 |
| AT-16 | SRA pos | 0x40000000 | 0x00000001 | 0111 | 0x20000000 | 0 |
| AT-17 | SRA 31 neg | 0x80000000 | 0x0000001F | 0111 | 0xFFFFFFFF | 0 |
| AT-18 | SLT -1<1 | 0xFFFFFFFF | 0x00000001 | 1000 | 0x00000001 | 0 |
| AT-19 | SLT 1<-1 | 0x00000001 | 0xFFFFFFFF | 1000 | 0x00000000 | 1 |
| AT-20 | SLT equal | 0x00000005 | 0x00000005 | 1000 | 0x00000000 | 1 |
| AT-21 | SLTU 1<max | 0x00000001 | 0xFFFFFFFF | 1001 | 0x00000001 | 0 |
| AT-22 | SLTU max<1 | 0xFFFFFFFF | 0x00000001 | 1001 | 0x00000000 | 1 |
| AT-23 | SLTU divergence | 0x7FFFFFFF | 0x80000000 | 1001 | 0x00000001 | 0 |
| AT-24 | Bpass(LUI) | 0x12345678 | 0xDEADBEEF | 1010 | 0xDEADBEEF | 0 |
| AT-25 | zero via AND | 0x0000FF00 | 0x000000FF | 0010 | 0x00000000 | 1 |
| AT-26 | SLL high bits | 0xFFFFFFFF | 0x00000004 | 0101 | 0xFFFFFFF0 | 0 |
| AT-27 | SLL by 0 | 0x12345678 | 0x00000000 | 0101 | 0x12345678 | 0 |
| AT-28 | illegal ctrl | 0x12345678 | 0x9ABCDEF0 | 1111 | 0x00000000 | 1 |
| AT-29 | SRL 31 | 0xFFFFFFFF | 0x0000001F | 0110 | 0x00000001 | 0 |
| AT-30 | **랜덤 counter-example** | 랜덤 | 랜덤 | 0000~1010 | 골든모델과 일치 | — |

> AT-30은 무작위 입력(기본 100,000 벡터)을 독립 골든모델과 대조하는 **counter-example 탐색**이다. 불일치가 1건이라도 나오면 반례로 보고하고 FAIL.
> AT-23은 SLT(부호)와 SLTU(무부호)가 동일 입력에서 갈리는 대표 케이스: `0x7FFFFFFF`(+max) vs `0x80000000`(-max). SLTU=1, SLT=0.

## 4. 결함 주입(Counter-example) 시연

`run_alu_at.py --bug sra|slt|shamt`로 의도적 결함을 주입하면 AT-30(및 해당 directed AT)이 **반례를 출력하고 FAIL**해야 한다 — 검증이 실제로 버그를 잡는지(테스트의 유효성) 입증.

| 주입 | 결함 | 잡히는 케이스 |
|---|---|---|
| `sra` | SRA를 논리 시프트로 | AT-15, AT-17, AT-30 |
| `slt` | SLT를 무부호 비교로 | AT-18/19, AT-30 |
| `shamt` | 시프트량 마스킹 누락 | AT-12, AT-30 |
