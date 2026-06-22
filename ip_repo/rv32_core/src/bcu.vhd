-- bcu.vhd - Branch Comparison Unit: compare + target + pc_src (EX->IF)
-- Spec: RV32_Pipeline_Spec.md 6.4, Movement.md 5.5/5.6
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity bcu is
    Port (
        a_fwd        : in  std_logic_vector(31 downto 0);  -- forwarded rs1 (compare)
        b_fwd        : in  std_logic_vector(31 downto 0);  -- forwarded rs2 (compare)
        rs1_fwd      : in  std_logic_vector(31 downto 0);  -- JALR base
        pc           : in  std_logic_vector(31 downto 0);
        imm          : in  std_logic_vector(31 downto 0);
        funct3       : in  std_logic_vector(2 downto 0);
        branch       : in  std_logic;
        jump         : in  std_logic;
        is_jalr      : in  std_logic;
        branch_taken : out std_logic;
        pc_src       : out std_logic;
        target_addr  : out std_logic_vector(31 downto 0)
    );
end bcu;

architecture Behavioral of bcu is
    signal cond : std_logic;
    signal jt   : std_logic_vector(31 downto 0);
begin
    process(a_fwd, b_fwd, funct3)
    begin
        cond <= '0';
        case funct3 is
            when "000"  => if a_fwd = b_fwd                       then cond <= '1'; end if;  -- BEQ
            when "001"  => if a_fwd /= b_fwd                      then cond <= '1'; end if;  -- BNE
            when "100"  => if signed(a_fwd)   <  signed(b_fwd)    then cond <= '1'; end if;  -- BLT
            when "101"  => if signed(a_fwd)   >= signed(b_fwd)    then cond <= '1'; end if;  -- BGE
            when "110"  => if unsigned(a_fwd) <  unsigned(b_fwd)  then cond <= '1'; end if;  -- BLTU
            when "111"  => if unsigned(a_fwd) >= unsigned(b_fwd)  then cond <= '1'; end if;  -- BGEU
            when others => cond <= '0';                                                      -- reserved
        end case;
    end process;

    branch_taken <= cond;
    pc_src       <= jump or (branch and cond);

    -- JALR target = (rs1+imm) & ~1 ; else PC+imm
    jt <= std_logic_vector(unsigned(rs1_fwd) + unsigned(imm)) and x"FFFFFFFE";
    target_addr <= jt when is_jalr = '1'
                   else std_logic_vector(unsigned(pc) + unsigned(imm));
end Behavioral;
