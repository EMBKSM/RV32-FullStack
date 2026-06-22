-- axi_master.vhd - AXI4 read/write burst master (32-bit data, 4-beat INCR line)
-- Spec: RV32_Pipeline_Spec.md 8.9. Line = 128b (4 x 32b).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity axi_master is
    Port (
        clk      : in  std_logic;
        reset    : in  std_logic;
        -- controller request interface
        rd_start : in  std_logic;
        wr_start : in  std_logic;
        addr     : in  std_logic_vector(31 downto 0);     -- line base (16B aligned)
        wb_line  : in  std_logic_vector(127 downto 0);    -- dirty line to write back
        rd_line  : out std_logic_vector(127 downto 0);    -- refilled line
        done     : out std_logic;                         -- 1-cycle pulse on completion
        -- AXI4 read
        ARADDR   : out std_logic_vector(31 downto 0);
        ARLEN    : out std_logic_vector(7 downto 0);
        ARSIZE   : out std_logic_vector(2 downto 0);
        ARBURST  : out std_logic_vector(1 downto 0);
        ARVALID  : out std_logic;
        ARREADY  : in  std_logic;
        RDATA    : in  std_logic_vector(31 downto 0);
        RLAST    : in  std_logic;
        RVALID   : in  std_logic;
        RREADY   : out std_logic;
        -- AXI4 write
        AWADDR   : out std_logic_vector(31 downto 0);
        AWLEN    : out std_logic_vector(7 downto 0);
        AWSIZE   : out std_logic_vector(2 downto 0);
        AWBURST  : out std_logic_vector(1 downto 0);
        AWVALID  : out std_logic;
        AWREADY  : in  std_logic;
        WDATA    : out std_logic_vector(31 downto 0);
        WSTRB    : out std_logic_vector(3 downto 0);
        WLAST    : out std_logic;
        WVALID   : out std_logic;
        WREADY   : in  std_logic;
        BVALID   : in  std_logic;
        BREADY   : out std_logic
    );
end axi_master;

architecture Behavioral of axi_master is
    type st_t is (A_IDLE, A_AR, A_R, A_AW, A_W, A_B, A_DONE);
    signal st   : st_t := A_IDLE;
    signal beat : integer range 0 to 3 := 0;
    signal rbuf : std_logic_vector(127 downto 0) := (others => '0');
    signal wsel : std_logic_vector(31 downto 0);
begin
    ARLEN <= x"03"; ARSIZE <= "010"; ARBURST <= "01"; ARADDR <= addr;
    AWLEN <= x"03"; AWSIZE <= "010"; AWBURST <= "01"; AWADDR <= addr;
    WSTRB <= "1111";
    rd_line <= rbuf;

    -- current writeback word
    with beat select wsel <=
        wb_line(31 downto 0)    when 0,
        wb_line(63 downto 32)   when 1,
        wb_line(95 downto 64)   when 2,
        wb_line(127 downto 96)  when others;
    WDATA <= wsel;

    -- Moore outputs
    ARVALID <= '1' when st = A_AR else '0';
    RREADY  <= '1' when st = A_R  else '0';
    AWVALID <= '1' when st = A_AW else '0';
    WVALID  <= '1' when st = A_W  else '0';
    WLAST   <= '1' when (st = A_W and beat = 3) else '0';
    BREADY  <= '1' when st = A_B  else '0';
    done    <= '1' when st = A_DONE else '0';

    process(clk, reset)
    begin
        if reset = '1' then
            st <= A_IDLE; beat <= 0; rbuf <= (others => '0');
        elsif rising_edge(clk) then
            case st is
                when A_IDLE =>
                    beat <= 0;
                    if    rd_start = '1' then st <= A_AR;
                    elsif wr_start = '1' then st <= A_AW; end if;
                when A_AR =>
                    if ARREADY = '1' then st <= A_R; beat <= 0; end if;
                when A_R =>
                    if RVALID = '1' then
                        case beat is
                            when 0 => rbuf(31 downto 0)   <= RDATA;
                            when 1 => rbuf(63 downto 32)  <= RDATA;
                            when 2 => rbuf(95 downto 64)  <= RDATA;
                            when others => rbuf(127 downto 96) <= RDATA;
                        end case;
                        if RLAST = '1' then st <= A_DONE;
                        else beat <= beat + 1; end if;
                    end if;
                when A_AW =>
                    if AWREADY = '1' then st <= A_W; beat <= 0; end if;
                when A_W =>
                    if WREADY = '1' then
                        if beat = 3 then st <= A_B;
                        else beat <= beat + 1; end if;
                    end if;
                when A_B =>
                    if BVALID = '1' then st <= A_DONE; end if;
                when A_DONE =>
                    st <= A_IDLE;
            end case;
        end if;
    end process;
end Behavioral;
