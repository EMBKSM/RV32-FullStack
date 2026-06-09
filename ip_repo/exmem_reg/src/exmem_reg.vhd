-- exmem_reg : EX/MEM pipeline boundary register (extracted from rv32_core.vhd)
--   freeze on mem_stall; folds the CSR read value into the result path
--   (alu_result <= csr_rdata when csr_to_reg else alu_result_ex).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
entity exmem_reg is
    Port (
        clk           : in std_logic;
        reset         : in std_logic;
        mem_stall     : in std_logic;
        alu_result_in : in std_logic_vector(31 downto 0);
        csr_rdata_in  : in std_logic_vector(31 downto 0);
        csr_to_reg_in : in std_logic;
        store_in      : in std_logic_vector(31 downto 0);   -- forwarded rs2 (fb_val)
        pc4_in        : in std_logic_vector(31 downto 0);
        rd_in         : in std_logic_vector(4 downto 0);
        funct3_in     : in std_logic_vector(2 downto 0);
        reg_write_in  : in std_logic;
        mem_read_in   : in std_logic;
        mem_write_in  : in std_logic;
        result_src_in : in std_logic_vector(1 downto 0);
        exmem_alu_result : out std_logic_vector(31 downto 0);
        exmem_store      : out std_logic_vector(31 downto 0);
        exmem_pc4        : out std_logic_vector(31 downto 0);
        exmem_rd         : out std_logic_vector(4 downto 0);
        exmem_funct3     : out std_logic_vector(2 downto 0);
        exmem_reg_write  : out std_logic;
        exmem_mem_read   : out std_logic;
        exmem_mem_write  : out std_logic;
        exmem_result_src : out std_logic_vector(1 downto 0)
    );
end exmem_reg;
architecture rtl of exmem_reg is
begin
    process(clk, reset)
    begin
        if reset = '1' then
            exmem_alu_result<=(others=>'0'); exmem_store<=(others=>'0');
            exmem_pc4<=(others=>'0'); exmem_rd<=(others=>'0'); exmem_funct3<=(others=>'0');
            exmem_reg_write<='0'; exmem_mem_read<='0'; exmem_mem_write<='0';
            exmem_result_src<="00";
        elsif rising_edge(clk) then
            if mem_stall = '1' then
                null;
            else
                if csr_to_reg_in = '1' then
                    exmem_alu_result <= csr_rdata_in;
                else
                    exmem_alu_result <= alu_result_in;
                end if;
                exmem_store      <= store_in;
                exmem_pc4        <= pc4_in;
                exmem_rd         <= rd_in;
                exmem_funct3     <= funct3_in;
                exmem_reg_write  <= reg_write_in;
                exmem_mem_read   <= mem_read_in;
                exmem_mem_write  <= mem_write_in;
                exmem_result_src <= result_src_in;
            end if;
        end if;
    end process;
end rtl;
