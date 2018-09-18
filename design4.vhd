
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use ieee.numeric_std.ALL;

--#design1

entity design4 is
    generic (
        clk_in_freq  : natural;
        clk_out_freq : natural
    );
    port (
        rst     : in  std_logic;
        clk_in  : in  std_logic;
        clk_out : out std_logic
    );
end design4;

architecture BHV of design4 is
    constant OUT_PERIOD_COUNT : integer := (clk_in_freq/clk_out_freq)-1;
begin
    process(clk_in, rst)
        variable count : integer range 0 to OUT_PERIOD_COUNT; -- note: integer type defaults to 32-bits wide unless you specify the range yourself
    begin
        if(rst = '1') then
            count := 0;
            clk_out <= '0';
        elsif(rising_edge(clk_in)) then
            if(count = OUT_PERIOD_COUNT) then
                count := 0;
            else
                count := count + 1;
            end if;
            if(count > OUT_PERIOD_COUNT/2) then
                clk_out <= '1';
            else
                clk_out <= '0';
            end if;
        end if;
    end process;
end BHV;
--#design1



--#pipe

entity design4 is

	port (
	        a: in std_logic;
	        b: in std_logic;
	        o: out std_logic
		
	);
end design4;
	
architecture hw of design4 is
	--
	
begin
	--
     o<=(a and b);
     
end hw;     
	
--#pipe


--#design3

entity design4 is
	port (
		CLK : in std_logic;					--fast io clock
		READY : out std_logic := '0';		--set when ready for ENABLE
		ENABLE : in std_logic;				--values input only when this is 1
		XXIN : in std_logic_vector(35 downto 0);	--4 x 9bit, first px is lsbs
		VALID : out std_logic := '0';				--values output only when this is 1
		YNOUT : out std_logic_vector(13 downto 0)	--output (zigzag order)
	);
end design4;

architecture hw of design4 is
	--
	alias xx0 : std_logic_vector(8 downto 0) is XXIN(8 downto 0);
	alias xx1 : std_logic_vector(8 downto 0) is XXIN(17 downto 9);
	alias xx2 : std_logic_vector(8 downto 0) is XXIN(26 downto 18);
	alias xx3 : std_logic_vector(8 downto 0) is XXIN(35 downto 27);
	--
	signal xt0 : std_logic_vector(9 downto 0) := (others => '0');
	signal xt1 : std_logic_vector(9 downto 0) := (others => '0');
	signal xt2 : std_logic_vector(9 downto 0) := (others => '0');
	signal xt3 : std_logic_vector(9 downto 0) := (others => '0');
	signal ff00 : std_logic_vector(11 downto 0) := (others => '0');
	signal ff01 : std_logic_vector(11 downto 0) := (others => '0');
	signal ff02 : std_logic_vector(11 downto 0) := (others => '0');
	signal ff03 : std_logic_vector(11 downto 0) := (others => '0');
	signal ff10 : std_logic_vector(11 downto 0) := (others => '0');
	signal ff11 : std_logic_vector(11 downto 0) := (others => '0');
	signal ff12 : std_logic_vector(11 downto 0) := (others => '0');
	signal ff13 : std_logic_vector(11 downto 0) := (others => '0');
	signal ff20 : std_logic_vector(11 downto 0) := (others => '0');
	signal ff21 : std_logic_vector(11 downto 0) := (others => '0');
	signal ff22 : std_logic_vector(11 downto 0) := (others => '0');
	signal ff23 : std_logic_vector(11 downto 0) := (others => '0');
	signal ffx0 : std_logic_vector(11 downto 0) := (others => '0');
	signal ffx1 : std_logic_vector(11 downto 0) := (others => '0');
	signal ffx2 : std_logic_vector(11 downto 0) := (others => '0');
	signal ffx3 : std_logic_vector(11 downto 0) := (others => '0');
	signal ff0p : std_logic_vector(11 downto 0) := (others => '0');
	signal ff1p : std_logic_vector(11 downto 0) := (others => '0');
	signal ff2p : std_logic_vector(11 downto 0) := (others => '0');
	signal ff3p : std_logic_vector(11 downto 0) := (others => '0');
	signal ff0pu : std_logic_vector(11 downto 0) := (others => '0');
	signal ff1pu : std_logic_vector(11 downto 0) := (others => '0');
	signal ff2pu : std_logic_vector(11 downto 0) := (others => '0');
	signal ff3pu : std_logic_vector(11 downto 0) := (others => '0');
	signal yt0 : std_logic_vector(12 downto 0) := (others => '0');
	signal yt1 : std_logic_vector(12 downto 0) := (others => '0');
	signal yt2 : std_logic_vector(12 downto 0) := (others => '0');
	signal yt3 : std_logic_vector(12 downto 0) := (others => '0');
	signal valid1 : std_logic := '0';
	signal valid2 : std_logic := '0';
	--
	signal ixx : std_logic_vector(2 downto 0) := b"000";
	signal iyn : std_logic_vector(3 downto 0) := b"0000";
	--
	signal ynyx : std_logic_vector(3 downto 0) := b"0000";
	alias yny : std_logic_vector(1 downto 0) is ynyx(3 downto 2);
	alias ynx : std_logic_vector(1 downto 0) is ynyx(1 downto 0);
	signal yny1 : std_logic_vector(1 downto 0) := b"00";
	signal yny2 : std_logic_vector(1 downto 0) := b"00";
	constant ROW0 : std_logic_vector(1 downto 0) := b"00";
	constant ROW1 : std_logic_vector(1 downto 0) := b"01";
	constant ROW2 : std_logic_vector(1 downto 0) := b"10";
	constant ROW3 : std_logic_vector(1 downto 0) := b"11";
	constant COL0 : std_logic_vector(1 downto 0) := b"00";
	constant COL1 : std_logic_vector(1 downto 0) := b"01";
	constant COL2 : std_logic_vector(1 downto 0) := b"10";
	constant COL3 : std_logic_vector(1 downto 0) := b"11";
begin
	--select column and row for output in reverse zigzag order (Table 8-12 in std)
	--this list is in forward zigzag order, but scanned in reverse
	ynyx <=	ROW0&COL0 when iyn = 15 else
			ROW0&COL1 when iyn = 14 else
			ROW1&COL0 when iyn = 13 else
			ROW2&COL0 when iyn = 12 else
			ROW1&COL1 when iyn = 11 else
			ROW0&COL2 when iyn = 10 else
			ROW0&COL3 when iyn = 9 else
			ROW1&COL2 when iyn = 8 else
			ROW2&COL1 when iyn = 7 else
			ROW3&COL0 when iyn = 6 else
			ROW3&COL1 when iyn = 5 else
			ROW2&COL2 when iyn = 4 else
			ROW1&COL3 when iyn = 3 else
			ROW2&COL3 when iyn = 2 else
			ROW3&COL2 when iyn = 1 else
			ROW3&COL3;
	--
	ff0pu <=ff00 when ynx=0 else
			ff01 when ynx=1 else
			ff02 when ynx=2 else
			ff03;
	ff1pu <=ff10 when ynx=0 else
			ff11 when ynx=1 else
			ff12 when ynx=2 else
			ff13;
	ff2pu <=ff20 when ynx=0 else
			ff21 when ynx=1 else
			ff22 when ynx=2 else
			ff23;
	ff3pu <=ffx0 when ynx=0 else
			ffx1 when ynx=1 else
			ffx2 when ynx=2 else
			ffx3;
	--
process(CLK)
begin
	if rising_edge(CLK) then
		if ENABLE='1' or ixx /= 0 then
			ixx <= ixx + 1;
		end if;
	end if;
	if rising_edge(CLK) then
		if ixx < 3 and (iyn >= 14 or iyn=0) then
			READY <= '1';
		else
			READY <= '0';
		end if;
	end if;
	if rising_edge(CLK) then
		--compute matrix ff, from XX times CfT
		--CfT is 1  2  1  1
		--       1  1 -1 -2
		--       1 -1 -1  2
		--       1 -2  1 -1
		if enable='1' then
			--initial helpers (TT+1) (10bit from 9bit)
			xt0 <= (xx0(8)&xx0) + (xx3(8)&xx3);			--xx0 + xx3
			xt1 <= (xx1(8)&xx1) + (xx2(8)&xx2);			--xx1 + xx2
			xt2 <= (xx1(8)&xx1) - (xx2(8)&xx2);			--xx1 - xx2
			xt3 <= (xx0(8)&xx0) - (xx3(8)&xx3);			--xx0 - xx3
		end if;
		if ixx>=1 and ixx<=4 then
			--now compute row of FF matrix at TT+2 (12bit from 10bit)
			ffx0 <= (xt0(9)&xt0(9)&xt0) + (xt1(9)&xt1(9)&xt1);	--xt0 + xt1
			ffx1 <= (xt2(9)&xt2(9)&xt2) + (xt3(9)&xt3&'0');		--xt2 + 2*xt3
			ffx2 <= (xt0(9)&xt0(9)&xt0) - (xt1(9)&xt1(9)&xt1);	--xt0 - xt1
			ffx3 <= (xt3(9)&xt3(9)&xt3) - (xt2(9)&xt2&'0');		--xt3 - 2*xt2
		end if;
		--place rows 0,1,2 into slots at TT+3,4,5
		if ixx=2 then
			ff00 <= ffx0;
			ff01 <= ffx1;
			ff02 <= ffx2;
			ff03 <= ffx3;
		elsif ixx=3 then
			ff10 <= ffx0;
			ff11 <= ffx1;
			ff12 <= ffx2;
			ff13 <= ffx3;
		elsif ixx=4 then
			ff20 <= ffx0;
			ff21 <= ffx1;
			ff22 <= ffx2;
			ff23 <= ffx3;
		end if;
		--
		--compute element of matrix YN, from Cf times ff
		--Cf is 1  1  1  1
		--      2  1 -1 -2
		--      1 -1 -1  1
		--      1 -2  2 -1
		--
		--second stage helpers (13bit from 12bit) TT+6..TT+21
		--ff0p..3 are column entries selected above
		if ixx = 5 or iyn /= 0 then
			ff0p <= ff0pu;
			ff1p <= ff1pu;
			ff2p <= ff2pu;
			ff3p <= ff3pu;
			yny1 <= yny;
			iyn <= iyn + 1;
			valid1 <= '1';
		else
			valid1 <= '0';
		end if;
		if valid1='1' then
			yt0 <= (ff0p(11)&ff0p) + (ff3p(11)&ff3p);	--ff0 + ff3
			yt1 <= (ff1p(11)&ff1p) + (ff2p(11)&ff2p);	--ff1 + ff2
			yt2 <= (ff1p(11)&ff1p) - (ff2p(11)&ff2p);	--ff1 - ff2
			yt3 <= (ff0p(11)&ff0p) - (ff3p(11)&ff3p);	--ff0 - ff3
			yny2 <= yny1;
		end if;
		--now compute output stage
		if valid2='1' then
			--compute final YNOUT values (14bit from 13bit)
			if yny2=0 then
				YNOUT <= (yt0(12)&yt0) + (yt1(12)&yt1);	-- yt0 + yt1
			elsif yny2=1 then
				YNOUT <= (yt2(12)&yt2) + (yt3&'0');		-- yt2 + 2*yt3
			elsif yny2=2 then
				YNOUT <= (yt0(12)&yt0) - (yt1(12)&yt1);	-- yt0 - yt1
			else--if yny2=3 then
				YNOUT <= (yt3(12)&yt3) - (yt2&'0');		-- yt3 - 2*yt2
			end if;
		end if;
		VALID2 <= valid1;
		VALID <= valid2;
	end if;
end process;
	--
end hw;

--#design3



--#design4

entity design4 is
Port ( 
    a : in std_logic;
    b : in std_logic;
    cin : in std_logic;
    s : out std_logic;
    cout : out std_logic);
end design4;

architecture Behavioral of design4 is

begin


    s<=(a xor (b xor cin));   
    cout<=(b and cin) or (a and cin) or (a and b);

end Behavioral;

--#design4
