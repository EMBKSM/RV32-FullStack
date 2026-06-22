library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity cache_controller is
    Port (
        clk       : in  std_logic;
        reset     : in  std_logic;

        -- CPU Core (Comparator) Interface
        miss      : in  std_logic;
        fence_i   : in  std_logic;   -- FENCE.I invalidate request (1-cycle pulse)
        ext_inv   : in  std_logic;   -- host code-load invalidate request (1-cycle pulse)
        stall     : out std_logic;
        wake_up   : out std_logic;
        we        : out std_logic;
        inv       : out std_logic;   -- I-Cache invalidate to Tag Array
        iflush    : out std_logic;   -- pipeline flush on FENCE.I

        -- AXI Master Interface (Simplified)
        arready   : in  std_logic;
        rvalid    : in  std_logic;
        arvalid   : out std_logic;
        rready    : out std_logic
    );
end cache_controller;

architecture Behavioral of cache_controller is
    type state_type is (
        S_IDLE,         -- 정상 동작 상태 (Hit 대기)
        S_SEND_AR,      -- AXI Read Address 전송 대기 (ARVALID)
        S_WAIT_R,       -- AXI Read Data 수신 대기 (RREADY)
        S_UPDATE_CACHE, -- 수신된 데이터를 SRAM(Data/Tag Array)에 쓰기
        S_WAKE_UP       -- 파이프라인 재개 (Stall 해제)
    );

    signal state_reg, next_state : state_type;

begin
    process(clk, reset)
    begin
        if reset = '1' then
            state_reg <= S_IDLE;
        elsif rising_edge(clk) then
            state_reg <= next_state;
        end if;
    end process;

    process(state_reg, miss, arready, rvalid, fence_i, ext_inv)
    begin
        next_state <= state_reg;

        case state_reg is
            when S_IDLE =>
                if (fence_i or ext_inv) = '1' then
                    next_state <= S_IDLE;   -- 1-cycle invalidate, then re-fetch as miss
                elsif miss = '1' then
                    next_state <= S_SEND_AR;
                end if;

            when S_SEND_AR =>
                if arready = '1' then
                    next_state <= S_WAIT_R;
                end if;

            when S_WAIT_R =>
                if rvalid = '1' then
                    next_state <= S_UPDATE_CACHE;
                end if;

            when S_UPDATE_CACHE =>
                next_state <= S_WAKE_UP;

            when S_WAKE_UP =>
                next_state <= S_IDLE;

            when others =>
                next_state <= S_IDLE;
        end case;
    end process;

    -- NOTE: fence_i/ext_inv/rvalid in the sensitivity list (invalidate + Mealy we).
    -- driven by the AXI read-data handshake (BUG-001 fix). Omitting it would
    -- cause a simulation/synthesis mismatch.
    process(state_reg, miss, rvalid, fence_i, ext_inv)
    begin
        stall   <= '0';
        wake_up <= '0';
        we      <= '0';
        arvalid <= '0';
        rready  <= '0';
        inv     <= '0';
        iflush  <= '0';

        case state_reg is
            when S_IDLE =>
                if (fence_i or ext_inv) = '1' then
                    inv    <= '1';      -- clear all valid bits (1 cycle)
                    stall  <= '1';
                    iflush <= fence_i;  -- FENCE.I flushes stale fetched insns
                elsif miss = '1' then
                    stall <= '1';
                end if;

            when S_SEND_AR =>
                stall   <= '1';
                arvalid <= '1';

            when S_WAIT_R =>
                stall   <= '1';
                rready  <= '1';
                -- BUG-001 fix: capture the refill word in the SAME cycle the read
                -- data is valid (RVALID & RREADY). Previously 'we' was asserted in
                -- S_UPDATE_CACHE, one cycle after RVALID had dropped, so the data
                -- array would have latched stale/invalid bus data.
                we      <= rvalid;
            when S_UPDATE_CACHE =>
                stall   <= '1';
                -- write already committed on the RVALID beat; settle/wake margin cycle

            when S_WAKE_UP =>
                wake_up <= '1';

            when others =>
                null;
        end case;
    end process;

end Behavioral;
