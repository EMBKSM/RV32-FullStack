# rv32_core BD 연결표 (핀 → 핀)

각 행 = **드라이버 핀 → 받는 핀(들)**. BD에서 드라이버 핀을 클릭해 받는 핀으로 끌면 됩니다.
인스턴스 이름은 아래 그대로 생성하세요(create_bd_cell 시 이름 지정). `ext:` = 외부 포트(Make External).

> **범위:** §0~§5 = rv32_core(파이프라인)를 leaf로 재현. §6 = I$/D$/메모리까지 붙인
> 풀 SoC(= rv32_soc 구조). **한 BD에 다 넣을 수 있습니다.**
> §6을 쓰면 §1의 `ext:imem_*`, §3의 `ext:ic_fence_i`, §4의 `ext:dmem_*`, §0의 `ext:mem_stall`은
> 외부 포트가 아니라 캐시/메모리 블록으로 연결됩니다(§6이 그 부분을 대체).
>
> **래퍼 규칙:** 금지되는 래퍼는 `rv32_core` 하나뿐(코어 leaf와 엔티티 중복). `icache_unit`,
> `cache_unit`는 내부 부품이 코어 leaf와 안 겹쳐서 **블록 하나로 그냥 써도 안전**합니다.

## 인스턴스 이름
```
IF : pc_reg_0  pc_adder_0  next_pc_mux_0  mux2_redirect  orgate2_redirect
     orgate2_corestall  ifid_reg_0
ID : control_unit_0  imm_gen_0  register_file_0  hazard_unit_0  id_decode_glue_0
     mux2_csrwdata  orgate2_bubble  idex_reg_0
EX : forwarding_unit_0  mux3_fa  mux3_fb  mux2_alua  mux2_alub  alu_control_0
     alu_0  bcu_0  csr_file_0  trap_unit_0  andn2_csrwe  andn2_mret  andn2_trapwe
     andn2_traptaken  fencei_oneshot_0  exmem_reg_0
MEM: read_aligner_0  write_strobe_gen_0  xlslice_byteoff  memwb_reg_0
WB : result_mux_0  const0_1b(xlconstant 1bit=0)  const0_32b(xlconstant 32bit=0)
ext: clk reset mem_stall(in) imem_addr(out) imem_rdata(in)
     dmem_addr/dmem_wdata/dmem_wstrb/dmem_we/dmem_re(out) dmem_rdata(in) ic_fence_i(out)
```

## 0. clk / reset (공통)
| 드라이버 | 받는 핀 |
|---|---|
| ext:clk | pc_reg_0.clk, ifid_reg_0.clk, register_file_0.clk, csr_file_0.clk, idex_reg_0.clk, fencei_oneshot_0.clk, exmem_reg_0.clk, memwb_reg_0.clk |
| ext:reset | pc_reg_0.reset, ifid_reg_0.reset, register_file_0.reset, csr_file_0.reset, idex_reg_0.reset, fencei_oneshot_0.reset, exmem_reg_0.reset, memwb_reg_0.reset |
| ext:mem_stall | ifid_reg_0.mem_stall, idex_reg_0.mem_stall, exmem_reg_0.mem_stall, memwb_reg_0.mem_stall, orgate2_corestall.b, andn2_csrwe.b, andn2_mret.b, andn2_trapwe.b, andn2_traptaken.b |

## 1. IF
| 드라이버 | 받는 핀 |
|---|---|
| pc_reg_0.pc | pc_adder_0.pc_in, ifid_reg_0.pc_in, **ext:imem_addr** |
| pc_adder_0.pc_out | next_pc_mux_0.pc_plus_4, ifid_reg_0.pc4_in |
| next_pc_mux_0.next_pc | pc_reg_0.next_pc |
| mux2_redirect.y | next_pc_mux_0.target_addr |
| orgate2_redirect.y | next_pc_mux_0.pc_src, ifid_reg_0.flush, orgate2_bubble.a |
| orgate2_corestall.y | pc_reg_0.stall |
| hazard_unit_0.stall | orgate2_corestall.a, ifid_reg_0.load_use_stall, orgate2_bubble.b |
| **ext:imem_rdata** | ifid_reg_0.instr_in |
| bcu_0.target_addr | mux2_redirect.d0 |
| trap_unit_0.trap_target | mux2_redirect.d1 |
| bcu_0.pc_src | orgate2_redirect.a |
| andn2_traptaken.y | mux2_redirect.sel, orgate2_redirect.b |

ifid_reg_0 출력: ifid_pc, ifid_pc4, ifid_instr (→ ID에서 사용)

## 2. ID
| 드라이버 | 받는 핀 |
|---|---|
| ifid_reg_0.ifid_instr | imm_gen_0.instr, id_decode_glue_0.instr |
| ifid_reg_0.ifid_pc | idex_reg_0.pc_in |
| ifid_reg_0.ifid_pc4 | idex_reg_0.pc4_in |
| id_decode_glue_0.opcode | control_unit_0.opcode, imm_gen_0.opcode |
| id_decode_glue_0.funct3 | control_unit_0.funct3, idex_reg_0.funct3_in |
| id_decode_glue_0.instr_31_20 | control_unit_0.instr_31_20, idex_reg_0.csr_addr_in |
| id_decode_glue_0.rs1 | register_file_0.a1, hazard_unit_0.if_id_rs1, idex_reg_0.rs1_in |
| id_decode_glue_0.rs2 | register_file_0.a2, hazard_unit_0.if_id_rs2, idex_reg_0.rs2_in |
| id_decode_glue_0.rd | idex_reg_0.rd_in |
| id_decode_glue_0.funct7_5 | idex_reg_0.funct7_5_in |
| id_decode_glue_0.jalr | idex_reg_0.jalr_in |
| id_decode_glue_0.zimm | mux2_csrwdata.d1 |
| id_decode_glue_0.csr_we | idex_reg_0.csr_we_in |
| control_unit_0.csr_use_imm | mux2_csrwdata.sel, id_decode_glue_0.csr_use_imm |
| control_unit_0.csr_cmd | idex_reg_0.csr_cmd_in, id_decode_glue_0.csr_cmd |
| imm_gen_0.imm | idex_reg_0.imm_in |
| register_file_0.rd1 | mux2_csrwdata.d0, idex_reg_0.rs1d_in |
| register_file_0.rd2 | idex_reg_0.rs2d_in |
| mux2_csrwdata.y | idex_reg_0.csr_wdata_in |
| orgate2_bubble.y | idex_reg_0.bubble |
| idex_reg_0.idex_mem_read | hazard_unit_0.id_ex_mem_read |
| idex_reg_0.idex_rd | hazard_unit_0.id_ex_rd, forwarding_unit_0.* (EX) |

control_unit_0의 나머지 출력 → idex_reg_0 동명 입력으로:
`reg_write_in, mem_read_in, mem_write_in, alu_src_in, src_a_sel_in, branch_in,
jump_in, alu_op_in, result_src_in, csr_to_reg_in, illegal_in, is_ecall_in,
is_ebreak_in, is_mret_in, is_fence_i_in` (control_unit의 reg_write/mem_read/.../illegal 출력).

## 3. EX
| 드라이버 | 받는 핀 |
|---|---|
| idex_reg_0.idex_rs1 | forwarding_unit_0.id_ex_rs1 |
| idex_reg_0.idex_rs2 | forwarding_unit_0.id_ex_rs2 |
| exmem_reg_0.exmem_rd | forwarding_unit_0.ex_mem_rd |
| exmem_reg_0.exmem_reg_write | forwarding_unit_0.ex_mem_reg_write |
| memwb_reg_0.memwb_rd | forwarding_unit_0.mem_wb_rd, register_file_0.a3 |
| memwb_reg_0.memwb_reg_write | forwarding_unit_0.mem_wb_reg_write, register_file_0.we3 |
| forwarding_unit_0.forward_a | mux3_fa.sel |
| forwarding_unit_0.forward_b | mux3_fb.sel |
| idex_reg_0.idex_rs1d | mux3_fa.d_reg |
| idex_reg_0.idex_rs2d | mux3_fb.d_reg |
| result_mux_0.write_data | mux3_fa.d_wb, mux3_fb.d_wb, register_file_0.wd3 |
| exmem_reg_0.exmem_alu_result | mux3_fa.d_exmem, mux3_fb.d_exmem, **ext:dmem_addr**, xlslice_byteoff.Din, memwb_reg_0.alu_result_in |
| mux3_fa.y (fa_val) | mux2_alua.d0, bcu_0.a_fwd, bcu_0.rs1_fwd |
| mux3_fb.y (fb_val) | mux2_alub.d0, bcu_0.b_fwd, exmem_reg_0.store_in |
| idex_reg_0.idex_pc | mux2_alua.d1, bcu_0.pc, trap_unit_0.instr_pc, trap_unit_0.fault_addr |
| idex_reg_0.idex_imm | mux2_alub.d1, bcu_0.imm |
| idex_reg_0.idex_src_a_sel | mux2_alua.sel |
| idex_reg_0.idex_alu_src | mux2_alub.sel |
| mux2_alua.y | alu_0.a |
| mux2_alub.y | alu_0.b |
| idex_reg_0.idex_alu_op | alu_control_0.alu_op |
| idex_reg_0.idex_funct3 | alu_control_0.funct3, bcu_0.funct3, exmem_reg_0.funct3_in |
| idex_reg_0.idex_funct7_5 | alu_control_0.funct7_5 |
| alu_control_0.alu_ctrl | alu_0.alu_ctrl |
| alu_0.result | exmem_reg_0.alu_result_in |
| idex_reg_0.idex_branch | bcu_0.branch |
| idex_reg_0.idex_jump | bcu_0.jump |
| idex_reg_0.idex_jalr | bcu_0.is_jalr |

CSR / Trap:
| 드라이버 | 받는 핀 |
|---|---|
| idex_reg_0.idex_csr_addr | csr_file_0.csr_addr |
| idex_reg_0.idex_csr_cmd | csr_file_0.csr_cmd |
| idex_reg_0.idex_csr_wdata | csr_file_0.csr_wdata |
| idex_reg_0.idex_csr_we | andn2_csrwe.a |
| idex_reg_0.idex_is_mret | andn2_mret.a, trap_unit_0.is_mret |
| idex_reg_0.idex_illegal | trap_unit_0.illegal_instr |
| idex_reg_0.idex_is_ecall | trap_unit_0.is_ecall |
| idex_reg_0.idex_is_ebreak | trap_unit_0.is_ebreak |
| idex_reg_0.idex_is_fence_i | fencei_oneshot_0.is_fence_i |
| andn2_csrwe.y | csr_file_0.csr_we |
| andn2_mret.y | csr_file_0.is_mret |
| andn2_trapwe.y | csr_file_0.trap_we |
| trap_unit_0.trap_we | andn2_trapwe.a |
| trap_unit_0.trap_taken | andn2_traptaken.a |
| trap_unit_0.trap_mepc | csr_file_0.trap_mepc |
| trap_unit_0.trap_mcause | csr_file_0.trap_mcause |
| trap_unit_0.trap_mtval | csr_file_0.trap_mtval |
| csr_file_0.csr_rdata | exmem_reg_0.csr_rdata_in |
| csr_file_0.mtvec_o | trap_unit_0.mtvec |
| csr_file_0.mepc_o | trap_unit_0.mepc |
| idex_reg_0.idex_csr_to_reg | exmem_reg_0.csr_to_reg_in |
| fencei_oneshot_0.ic_fence_i | **ext:ic_fence_i** |
| const0_1b.dout | trap_unit_0.instr_misalign, trap_unit_0.load_misalign, trap_unit_0.store_misalign, result_mux_0.csr_to_reg |

exmem_reg_0 나머지 입력: pc4_in←idex_reg_0.idex_pc4, rd_in←idex_reg_0.idex_rd,
reg_write_in←idex_reg_0.idex_reg_write, mem_read_in←idex_reg_0.idex_mem_read,
mem_write_in←idex_reg_0.idex_mem_write, result_src_in←idex_reg_0.idex_result_src.

## 4. MEM
| 드라이버 | 받는 핀 |
|---|---|
| exmem_reg_0.exmem_mem_read | **ext:dmem_re** |
| exmem_reg_0.exmem_mem_write | **ext:dmem_we** |
| exmem_reg_0.exmem_store | write_strobe_gen_0.store_data |
| exmem_reg_0.exmem_funct3 | read_aligner_0.funct3, write_strobe_gen_0.funct3 |
| xlslice_byteoff.Dout ([1:0] of exmem_alu_result) | read_aligner_0.byte_off, write_strobe_gen_0.byte_off |
| **ext:dmem_rdata** | read_aligner_0.word_data |
| read_aligner_0.read_data | memwb_reg_0.read_data_in |
| write_strobe_gen_0.wstrb | **ext:dmem_wstrb** |
| write_strobe_gen_0.wdata_aligned | **ext:dmem_wdata** |
| exmem_reg_0.exmem_pc4 | memwb_reg_0.pc4_in |
| exmem_reg_0.exmem_rd | memwb_reg_0.rd_in |
| exmem_reg_0.exmem_reg_write | memwb_reg_0.reg_write_in |
| exmem_reg_0.exmem_result_src | memwb_reg_0.result_src_in |

(xlslice_byteoff: Din width 32, Din From=1 Down To=0 → Dout 2bit)

## 5. WB
| 드라이버 | 받는 핀 |
|---|---|
| memwb_reg_0.memwb_result_src | result_mux_0.result_src |
| memwb_reg_0.memwb_alu_result | result_mux_0.alu_result |
| memwb_reg_0.memwb_read_data | result_mux_0.read_data |
| memwb_reg_0.memwb_pc4 | result_mux_0.pc_plus4 |
| const0_32b.dout | result_mux_0.csr_rdata |
| const0_1b.dout | result_mux_0.csr_to_reg |
| result_mux_0.write_data | register_file_0.wd3, mux3_fa.d_wb, mux3_fb.d_wb |

## 6. SoC: 코어 ↔ I$/D$ ↔ 메모리 (한 BD에 다 넣기)
이 절을 쓰면 §1/§3/§4의 `ext:imem_*`,`ext:dmem_*`,`ext:ic_fence_i`,`ext:mem_stall`은
**외부 포트 대신** 아래 캐시/메모리 블록에 연결됩니다.

추가 인스턴스:
```
icache_unit_0 (user:rv32:icache_unit)      cache_unit_0 (user:rv32:cache_unit)
imem (axi_slave_mem, Add Module 모듈참조)   dmem (axi_slave_mem, Add Module 모듈참조)
orgate2_memstall (i_stall OR d_stall)       orgate2_dreq (dmem_re OR dmem_we)
```
> `axi_slave_mem`은 IP가 아니라 시뮬용 거동 메모리입니다. BD 캔버스 우클릭 → **Add Module**로
> `ip_workspace/3_Mem/axi_slave_mem.vhd`를 모듈참조 추가하세요. (합성용이 아니라 bring-up/sim용.)

### 코어 ↔ I-캐시
| 드라이버 | 받는 핀 |
|---|---|
| pc_reg_0.pc | icache_unit_0.addr  *(§1의 ext:imem_addr 대체)* |
| icache_unit_0.rword | ifid_reg_0.instr_in  *(§1의 ext:imem_rdata 대체)* |
| fencei_oneshot_0.ic_fence_i | icache_unit_0.fence_i  *(§3의 ext:ic_fence_i 대체)* |
| const0_1b.dout | icache_unit_0.ext_inv |
| icache_unit_0.iflush | (비워둠) |
| icache_unit_0.stall | orgate2_memstall.a |

### 코어 ↔ D-캐시
| 드라이버 | 받는 핀 |
|---|---|
| exmem_reg_0.exmem_alu_result | cache_unit_0.addr  *(§4의 ext:dmem_addr 대체)* |
| exmem_reg_0.exmem_mem_write | cache_unit_0.we, orgate2_dreq.a  *(§4의 ext:dmem_we 대체)* |
| exmem_reg_0.exmem_mem_read | orgate2_dreq.b  *(§4의 ext:dmem_re 대체)* |
| orgate2_dreq.y | cache_unit_0.req |
| write_strobe_gen_0.wdata_aligned | cache_unit_0.st_data  *(§4의 ext:dmem_wdata 대체)* |
| write_strobe_gen_0.wstrb | cache_unit_0.st_strb  *(§4의 ext:dmem_wstrb 대체)* |
| cache_unit_0.rword | read_aligner_0.word_data  *(§4의 ext:dmem_rdata 대체)* |
| cache_unit_0.stall | orgate2_memstall.b |

### mem_stall 합치기
| 드라이버 | 받는 핀 |
|---|---|
| orgate2_memstall.y (= i_stall OR d_stall) | (§0의 ext:mem_stall이 가던 모든 곳) ifid_reg_0.mem_stall, idex_reg_0.mem_stall, exmem_reg_0.mem_stall, memwb_reg_0.mem_stall, orgate2_corestall.b, andn2_csrwe.b, andn2_mret.b, andn2_trapwe.b, andn2_traptaken.b |

### I-캐시 ↔ imem (AXI), D-캐시 ↔ dmem (AXI)
각 캐시의 AXI 마스터 포트를 같은 이름의 메모리 슬레이브 포트에 1:1 연결:
```
icache_unit_0.{ARADDR,ARVALID,ARREADY,RDATA,RLAST,RVALID,RREADY,
               AWADDR,AWVALID,AWREADY,WDATA,WSTRB,WLAST,WVALID,WREADY,BVALID,BREADY}
   <->  imem.{동일 이름}
cache_unit_0.{...동일...}  <->  dmem.{동일 이름}
```
메모리 프리로드 포트 → 외부로:
```
imem.prog_we / prog_addr / prog_data        -> ext (명령어 로드)
dmem.prog_we / prog_addr / prog_data        -> ext (데이터 초기화, 선택)
imem.clk/reset, dmem.clk/reset              -> ext:clk / ext:reset
```

## 마무리 체크
- 모든 `*_reg`/순차 블록에 clk/reset 연결됐는지.
- 외부 포트:
  - **코어만(§1~5)** 만들 때: clk, reset, mem_stall, imem_addr, imem_rdata,
    dmem_addr, dmem_wdata, dmem_wstrb, dmem_we, dmem_re, dmem_rdata, ic_fence_i.
  - **풀 SoC(§6 포함)** 일 때: clk, reset, imem.prog_we/prog_addr/prog_data,
    dmem.prog_we/prog_addr/prog_data 만 외부로 (imem/dmem/mem_stall/ic_fence_i는 내부 연결).
- 미사용 출력(alu_0.zero, bcu_0.branch_taken, csr_file_0.mstatus_o, trap_unit_0.flush_all,
  hazard_unit_0.flush)은 그냥 비워두면 됨.
- Validate Design (F6) → 미연결/폭불일치 0 이어야 함.
