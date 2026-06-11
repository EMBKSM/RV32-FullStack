-- =====================================================================
-- alu.vhd  -  RV32I EX-stage Arithmetic Logic Unit
-- Spec: Movement.md 5.4, RV32_Pipeline_Spec.md 6.1
-- Combinational. shamt = b[4:0] (RV32I). SRA arithmetic, SRL logical.
-- =====================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity alu is
    Port (
        a        : in  std_logic_vector(31 downto 0);
        b        : in  std_logic_vector(31 downto 0);
        alu_ctrl : in  std_logic_vector(3 downto 0);
        result   : out std_logic_vector(31 downto 0);
        zero     : out std_logic
    );
end alu;

architecture Behavioral of alu is
    signal res   : std_logic_vector(31 downto 0);
    signal shamt : integer range 0 to 31;
begin
    -- AC-2: shift amount masked to b[4:0]
    shamt <= to_integer(unsigned(b(4 downto 0)));

    process(a, b, alu_ctrl, shamt)
    begin
        case alu_ctrl is
            when "0000" => res <= std_logic_vector(unsigned(a) + unsigned(b));        -- ADD
            when "0001" => res <= std_logic_vector(unsigned(a) - unsigned(b));        -- SUB
            when "0010" => res <= a and b;                                            -- AND
            when "0011" => res <= a or  b;                                            -- OR
            when "0100" => res <= a xor b;                                            -- XOR
            when "0101" => res <= std_logic_vector(shift_left (unsigned(a), shamt));  -- SLL
            when "0110" => res <= std_logic_vector(shift_right(unsigned(a), shamt));  -- SRL (logical)
            when "0111" => res <= std_logic_vector(shift_right(signed(a),   shamt));  -- SRA (arithmetic, AC-3)
            when "1000" =>                                                            -- SLT (signed, AC-4)
                if signed(a) < signed(b) then res <= x"00000001";
                else                           res <= x"00000000"; end if;
            when "1001" =>                                                            -- SLTU (unsigned, AC-4)
                if unsigned(a) < unsigned(b) then res <= x"00000001";
                else                              res <= x"00000000"; end if;
            when "1010" => res <= b;                                                  -- Bpass (LUI)
            when others => res <= (others => '0');                                    -- AC-6: illegal -> 0
        end case;
    end process;

    result <= res;
    zero   <= '1' when res = x"00000000" else '0';                                    -- AC-5
end Behavioral;
