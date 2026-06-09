# rv32_core 손배선 가이드 (Block Design, leaf 블록 조립)

`rv32_core.vhd`의 구조를 IP Integrator 블록디자인에서 **leaf IP + glue**로 재현하기 위한
배선 지도입니다. 코드(rv32_core.vhd)의 동시문/process를 그대로 netlist로 옮긴 것입니다.

## 0. 시작 전 필수 규칙
- **leaf IP만 사용**하고 래퍼 IP(`rv32_core` / `icache_unit` / `cache_unit`)는 **넣지 마세요.**
  같은 엔티티 중복 정의로 충돌합니다.
- BD에 추가할 **glue 모듈**(leaf IP에 없는 것) — 전부 `bd_assembly/`에 개별 파일로 생성됨,
  `package_bd_glue.tcl`로 IP 패키징 가능:
  - `mux2_32`, `mux3_32`, `orgate2`, `andn2`  (먹스/게이트)
  - `id_decode_glue` (필드 슬라이스 + funct7_5 게이팅 + jalr + zimm + csr_we)
  - `fencei_oneshot` (FENCE.I 1-cycle 펄스)
  - 파이프라인 경계 레지스터 4종: `ifid_reg`, `idex_reg`, `exmem_reg`, `memwb_reg`
  - csr_wdata 먹스, alu_a/alu_b 먹스 등은 `mux2_32` 인스턴스로 배선.
  - 단순 상수(WB의 csr_to_reg=0 등)는 stock IP `xlconstant` 사용.
  - (`id_decode_glue`를 쓰면 §2의 필드 슬라이스는 따로 xlslice 안 해도 됩니다.)
- BD 인스턴스화할 leaf IP: pc_reg, pc_adder, next_pc_mux, control_unit, imm_gen,
  register_file, hazard_unit, csr_file, alu, alu_control, bcu, forwarding_unit,
  trap_unit, read_aligner, write_strobe_gen, result_mux. (캐시/ddata 등은 코어 외부)
- 공통: 모든 reg 블록과 pc_reg/register_file/csr_file에 `clk`, `reset` 연결.

표기: `A.out -> B.in` = A의 출력 포트를 B의 입력 포트에 연결. `[글루]` = glue 블록 사용.

---

## 1. IF 스테이지
```
core_stall = orgate2(load_use_stall, mem_stall)                         [glue orgate2]
pc_reg(stall=core_stall, next_pc) -> pc
pc_adder(pc_in=pc) -> pc_plus4
redirect_target = mux2_32(d0=ex_target_addr, d1=trap_target_s, sel=trap_taken_q)  [glue]
redirect_sel    = orgate2(trap_taken_q, ex_pc_src)                      [glue]
next_pc_mux(pc_plus_4=pc_plus4, target_addr=redirect_target, pc_src=redirect_sel) -> next_pc
imem_addr = pc            (외부 I-메모리 주소)
instr_if  = imem_rdata    (외부 I-메모리 데이터)
```
IF/ID 레지스터 `ifid_reg` (clk,reset):
```
in : pc, pc_plus4, instr_if
ctl: mem_stall(freeze), squash=redirect_sel(=ex_pc_src OR trap_taken_q -> instr<=NOP),
     load_use_stall(hold)
out: ifid_pc, ifid_pc4, ifid_instr
```

## 2. ID 스테이지
명령어 필드 슬라이스 (xlslice on `ifid_instr`):
```
opcode      = ifid_instr[6:0]
id_rd       = ifid_instr[11:7]
id_funct3   = ifid_instr[14:12]
id_rs1      = ifid_instr[19:15]
id_rs2      = ifid_instr[24:20]
instr_31_20 = ifid_instr[31:20]
bit30       = ifid_instr[30]
```
```
control_unit(opcode, funct3=id_funct3, instr_31_20)
   -> c_reg_write, c_mem_read, c_mem_write, c_alu_src, c_src_a_sel, c_branch, c_jump,
      c_alu_op[2], c_result_src[2], u_csr_to_reg, u_csr_use_imm, u_csr_cmd[2],
      u_is_ecall, u_is_ebreak, u_is_mret, u_is_fence_i, u_illegal
imm_gen(instr=ifid_instr, opcode) -> id_imm
register_file(we3=memwb_reg_write, a1=id_rs1, a2=id_rs2, a3=memwb_rd, wd3=wb_write_data)
   -> id_rs1_data, id_rs2_data
hazard_unit(id_ex_mem_read=idex_mem_read, id_ex_rd=idex_rd, if_id_rs1=id_rs1,
            if_id_rs2=id_rs2) -> load_use_stall, flush(unused)
```
funct7_5 게이팅과 jalr (작은 조합 글루, 또는 idex_reg 안에 흡수):
```
id_funct7_5 = bit30 AND (opcode=0110011 OR (opcode=0010011 AND funct3=101))   else 0
id_jalr     = (opcode = 1100111)
```
CSR 오퍼랜드 빌드 (글루):
```
id_csr_addr  = instr_31_20
id_zimm      = zero-extend(id_rs1 field, 32)            [xlconcat: 27'b0 & ifid_instr[19:15]]
id_csr_wdata = mux2_32(d0=id_rs1_data, d1=id_zimm, sel=u_csr_use_imm)   [glue]
id_src_nonzero = (u_csr_use_imm? (rs1field/=0) : (id_rs1/=0))
id_csr_we    = (u_csr_cmd=01) OR ((u_csr_cmd=10 or 11) AND id_src_nonzero)
```
ID/EX 레지스터 `idex_reg` (clk,reset) — bubble nullification 포함:
```
bubble = load_use_stall OR ex_pc_src OR trap_taken_q
freeze = mem_stall
data 입력 : ifid_pc, ifid_pc4, id_rs1_data, id_rs2_data, id_imm, id_rs1, id_rs2, id_rd,
            id_funct3, id_funct7_5, id_jalr, id_csr_addr, id_csr_wdata
ctrl 입력 : c_reg_write,c_mem_read,c_mem_write,c_alu_src,c_src_a_sel,c_branch,c_jump,
            c_alu_op,c_result_src,u_csr_to_reg,id_csr_we,u_csr_cmd,
            u_illegal,u_is_ecall,u_is_ebreak,u_is_mret,u_is_fence_i
출력 idex_* : 위 전부 (bubble=1이면 ctrl은 0으로, data는 통과)
```

## 3. EX 스테이지
```
forwarding_unit(id_ex_rs1=idex_rs1, id_ex_rs2=idex_rs2, ex_mem_rd=exmem_rd,
   ex_mem_reg_write=exmem_reg_write, mem_wb_rd=memwb_rd, mem_wb_reg_write=memwb_reg_write)
   -> forward_a[2], forward_b[2]
fa_val = mux3_32(d_reg=idex_rs1d, d_wb=wb_write_data, d_exmem=exmem_alu_result, sel=forward_a) [glue]
fb_val = mux3_32(d_reg=idex_rs2d, d_wb=wb_write_data, d_exmem=exmem_alu_result, sel=forward_b) [glue]
alu_a  = mux2_32(d0=fa_val, d1=idex_pc,  sel=idex_src_a_sel)    [glue]
alu_b  = mux2_32(d0=fb_val, d1=idex_imm, sel=idex_alu_src)      [glue]
alu_control(alu_op=idex_alu_op, funct3=idex_funct3, funct7_5=idex_funct7_5) -> alu_ctrl[4]
alu(a=alu_a, b=alu_b, alu_ctrl) -> alu_result_ex, zero(unused)
bcu(a_fwd=fa_val, b_fwd=fb_val, rs1_fwd=fa_val, pc=idex_pc, imm=idex_imm,
    funct3=idex_funct3, branch=idex_branch, jump=idex_jump, is_jalr=idex_jalr)
    -> ex_branch_taken(unused), ex_pc_src, ex_target_addr
```
CSR / Trap (커밋 가드는 andn2 = x AND not mem_stall):
```
csr_we_qual  = andn2(idex_csr_we,  mem_stall)     [glue]
mret_qual    = andn2(idex_is_mret, mem_stall)     [glue]
trap_we_qual = andn2(trap_we_s,    mem_stall)     [glue]
trap_taken_q = andn2(trap_taken_s, mem_stall)     [glue]
csr_file(csr_addr=idex_csr_addr, csr_cmd=idex_csr_cmd, csr_wdata=idex_csr_wdata,
   csr_we=csr_we_qual, trap_we=trap_we_qual, trap_mepc=trap_mepc_s,
   trap_mcause=trap_mcause_s, trap_mtval=trap_mtval_s, is_mret=mret_qual)
   -> csr_rdata_ex, mstatus_o(unused), mtvec_o=mtvec_s, mepc_o=mepc_s
trap_unit(illegal_instr=idex_illegal, instr_misalign=0, load_misalign=0, store_misalign=0,
   is_ecall=idex_is_ecall, is_ebreak=idex_is_ebreak, is_mret=idex_is_mret,
   instr_pc=idex_pc, fault_addr=idex_pc, mtvec=mtvec_s, mepc=mepc_s)
   -> trap_taken_s, trap_target_s, flush_all_s(unused), trap_we_s,
      trap_mepc_s, trap_mcause_s, trap_mtval_s
```
FENCE.I one-shot (idex_reg에 1-cycle 지연 플롭 fencei_seen 추가하거나 작은 글루):
```
ic_fence_i = idex_is_fence_i AND (NOT fencei_seen);   fencei_seen <= idex_is_fence_i (clk)
```
EX/MEM 레지스터 `exmem_reg` (clk,reset; CSR-fold 먹스 내장):
```
freeze = mem_stall
exmem_alu_result <= mux2_32(d0=alu_result_ex, d1=csr_rdata_ex, sel=idex_csr_to_reg)
exmem_store      <= fb_val
exmem_pc4        <= idex_pc4
exmem_rd         <= idex_rd
exmem_funct3     <= idex_funct3
exmem_reg_write  <= idex_reg_write
exmem_mem_read   <= idex_mem_read
exmem_mem_write  <= idex_mem_write
exmem_result_src <= idex_result_src
(exmem_csr_to_reg / exmem_csr_rdata 는 운반만; WB에서 미사용 — 생략 가능)
```

## 4. MEM 스테이지
```
dmem_addr   = exmem_alu_result          (외부 D-메모리 주소)
mem_byte_off= exmem_alu_result[1:0]     [xlslice]
dmem_re     = exmem_mem_read
dmem_we     = exmem_mem_write
read_aligner(word_data=dmem_rdata, byte_off=mem_byte_off, funct3=exmem_funct3) -> mem_read_data
write_strobe_gen(funct3=exmem_funct3, byte_off=mem_byte_off, store_data=exmem_store)
   -> mem_wstrb (=dmem_wstrb), mem_wdata_aligned (=dmem_wdata)
```
MEM/WB 레지스터 `memwb_reg` (clk,reset):
```
freeze = mem_stall
in : mem_read_data, exmem_alu_result, exmem_pc4, exmem_rd, exmem_reg_write, exmem_result_src
out: memwb_read_data, memwb_alu_result, memwb_pc4, memwb_rd, memwb_reg_write, memwb_result_src
```

## 5. WB 스테이지
```
result_mux(result_src=memwb_result_src, csr_to_reg=0(xlconstant),
   alu_result=memwb_alu_result, read_data=memwb_read_data,
   pc_plus4=memwb_pc4, csr_rdata=0(xlconstant)) -> wb_write_data
wb_write_data -> register_file.wd3,  forwarding 경로(mux3 d_wb)
```

## 6. 아직 만들어야 할 glue (파이프라인 레지스터 4종)
`ifid_reg`, `idex_reg`, `exmem_reg`, `memwb_reg` 는 leaf IP에 없습니다. 위 §1~4의
입출력/freeze/bubble 사양 그대로 작은 엔티티로 만들어 BD에 module reference로 추가하면
됩니다. (원하면 이어서 생성해 드립니다 — rv32_core.vhd의 해당 process를 1:1로 떼어낸
형태가 됩니다.)

## 7. BD 절차 요약
1. 새 프로젝트(또는 검증 프로젝트 보존하려면 별도 프로젝트) → Create Block Design.
2. `bd_mux_glue.vhd` + (생성한)4종 reg + leaf IP 소스를 프로젝트에 add.
   IP는 `ip_repo` 등록(`set_property ip_repo_paths ...; update_ip_catalog`) 후 카탈로그에서,
   glue/reg는 BD 캔버스에서 우클릭 → Add Module.
3. clk/reset 포트 만들고 모든 순차 블록에 분배.
4. §1→§5 순서로 연결. 외부 포트로 빼낼 것: imem_addr/imem_rdata, dmem_addr/dmem_wdata/
   dmem_wstrb/dmem_we/dmem_re/dmem_rdata, mem_stall, ic_fence_i, (디버그 포트 선택).
5. Validate Design (F6)로 미연결/폭불일치 점검.

## 8. 검증 팁
완성 후, 기존 `tb_rv32_core_if_wb.sv`를 이 BD 래퍼에 그대로 물려 시뮬하면(포트 이름만 맞추면)
손배선이 rv32_core와 동일하게 동작하는지 바로 확인할 수 있습니다 — 같은 자극, 같은 기대값.
