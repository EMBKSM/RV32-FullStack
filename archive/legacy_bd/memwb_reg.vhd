-- memwb_reg : MEM/WB pipeline boundary register (extracted from rv32_core.vhd)
--   freeze on mem_stall; plain register.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
entity memwb_reg is
    Port (
        clk           : in std_logic;
        reset         : in std_logic;
        mem_stall     : in std_logic;
        read_data_in  : in std_logic_vector(31 downto 0);
        alu_result_in : in std_logic_vector(31 downto 0);
        pc4_in        : in std_logic_vector(31 downto 0);
        rd_in         : in std_logic_vector(4 downto 0);
        reg_write_in  : in std_logic;
        result_src_in : in std_logic_vector(1 downto 0);
        memwb_read_data  : out std_logic_vector(31 downto 0);
        memwb_alu_result : out std_logic_vector(31 downto 0);
        memwb_pc4        : out std_logic_vector(31 downto 0);
        memwb_rd         : out std_logic_vector(4 downto 0);
        memwb_reg_write  : out std_logic;
        memwb_result_src : out std_logic_vector(1 downto 0)
    );
end memwb_reg;
architecture rtl of memwb_reg is
begin
    process(clk, reset)
    begin
        if reset = '1' then
            memwb_read_data<=(others=>'0'); memwb_alu_result<=(others=>'0');
            memwb_pc4<=(others=>'0'); memwb_rd<=(others=>'0');
            memwb_reg_write<='0'; memwb_result_src<="00";
        elsif rising_edge(clk) then
            if mem_stall = '1' then
                null;
            else
                memwb_read_data  <= read_data_in;
                memwb_alu_result <= alu_result_in;
                memwb_pc4        <= pc4_in;
                memwb_rd         <= rd_in;
                memwb_reg_write  <= reg_write_in;
                memwb_result_src <= result_src_in;
            end if;
        end if;
    end process;
end rtl;
