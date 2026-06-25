-- =====================================================================
-- pwm_gen.vhd  -  MMIO PWM generator (NCH channels, shared period)
--
-- A free-running counter wraps at PERIOD; each channel output is high while the
-- counter is below that channel's DUTY (and the channel is enabled). Drive servos,
-- LEDs, motor drivers, etc. from a Pmod. pwm_freq = clk / PERIOD.
--
-- Register block (word offsets, reg = addr[4:2]):
--   0x0 CTRL   (RW) b[NCH-1:0] per-channel enable
--   0x4 PERIOD (RW) counter modulus (wrap point); 0 disables the counter
--   0x8 DUTY0  (RW) high-time for channel 0 (counts < DUTY0 => '1')
--   0xC DUTY1  ...  0x10 DUTY2 ... 0x14 DUTY3
-- =====================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pwm_gen is
    generic ( NCH : integer := 4; CW : integer := 24 );
    Port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        sel    : in  std_logic;
        we     : in  std_logic;
        reg    : in  std_logic_vector(2 downto 0);
        wdata  : in  std_logic_vector(31 downto 0);
        rdata  : out std_logic_vector(31 downto 0);
        pwm_o  : out std_logic_vector(NCH-1 downto 0)
    );
end pwm_gen;

architecture rtl of pwm_gen is
    type duty_arr is array (0 to 3) of unsigned(CW-1 downto 0);
    signal duty   : duty_arr := (others=>(others=>'0'));
    signal period : unsigned(CW-1 downto 0) := (others=>'0');
    signal cnt    : unsigned(CW-1 downto 0) := (others=>'0');
    signal en     : std_logic_vector(3 downto 0) := (others=>'0');
begin
    with reg select rdata <=
        std_logic_vector(resize(unsigned(en),32))  when "000",
        std_logic_vector(resize(period,32))        when "001",
        std_logic_vector(resize(duty(0),32))       when "010",
        std_logic_vector(resize(duty(1),32))       when "011",
        std_logic_vector(resize(duty(2),32))       when "100",
        std_logic_vector(resize(duty(3),32))       when "101",
        (others=>'0')                              when others;

    -- channel outputs
    gen_out : for i in 0 to NCH-1 generate
        pwm_o(i) <= '1' when (en(i)='1' and cnt < duty(i)) else '0';
    end generate;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst='1' then
                duty<=(others=>(others=>'0')); period<=(others=>'0');
                cnt<=(others=>'0'); en<=(others=>'0');
            else
                -- free-running counter
                if period = 0 then
                    cnt <= (others=>'0');
                elsif cnt >= period - 1 then
                    cnt <= (others=>'0');
                else
                    cnt <= cnt + 1;
                end if;

                if (sel='1' and we='1') then
                    case reg is
                        when "000" => en     <= wdata(3 downto 0);
                        when "001" => period <= unsigned(wdata(CW-1 downto 0));
                        when "010" => duty(0)<= unsigned(wdata(CW-1 downto 0));
                        when "011" => duty(1)<= unsigned(wdata(CW-1 downto 0));
                        when "100" => duty(2)<= unsigned(wdata(CW-1 downto 0));
                        when "101" => duty(3)<= unsigned(wdata(CW-1 downto 0));
                        when others => null;
                    end case;
                end if;
            end if;
        end if;
    end process;
end rtl;
