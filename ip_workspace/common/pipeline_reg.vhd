-- pipeline_reg.vhd - generic pipeline boundary register
-- flush nullifies control (bubble); stall holds; data passes through on flush.
--
-- Field packing (datapath responsibility):
--   IF/ID  : d={pc,pc4,instr}                         c={valid}
--   ID/EX  : d={pc,pc4,rs1d,rs2d,imm,rs1,rs2,rd,f3,f7_5}
--            c={reg_write,mem_read,mem_write,alu_src,src_a_sel,branch,jump,
--               alu_op[2],result_src[2],csr_to_reg,csr_cmd[2],is_ecall,is_ebreak,
--               is_mret,is_fence_i,illegal}
--   EX/MEM : d={alu_result,data2,rd,f3,pc4,csr_rdata}
--            c={reg_write,mem_read,mem_write,result_src[2],csr_to_reg}
--   MEM/WB : d={read_data,alu_result,pc4,csr_rdata,rd}
--            c={reg_write,result_src[2],csr_to_reg}
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity pipeline_reg is
    Generic (
        DW : integer := 32;   -- packed data width
        CW : integer := 8     -- packed control width
    );
    Port (
        clk   : in  std_logic;
        reset : in  std_logic;
        stall : in  std_logic;
        flush : in  std_logic;
        d_in  : in  std_logic_vector(DW-1 downto 0);
        c_in  : in  std_logic_vector(CW-1 downto 0);
        d_out : out std_logic_vector(DW-1 downto 0);
        c_out : out std_logic_vector(CW-1 downto 0)
    );
end pipeline_reg;

architecture Behavioral of pipeline_reg is
begin
    process(clk, reset)
    begin
        if reset = '1' then
            d_out <= (others => '0');
            c_out <= (others => '0');
        elsif rising_edge(clk) then
            if flush = '1' then
                d_out <= d_in;
                c_out <= (others => '0');   -- bubble: control nullified
            elsif stall = '1' then
                null;                        -- hold
            else
                d_out <= d_in;
                c_out <= c_in;
            end if;
        end if;
    end process;
end Behavioral;
