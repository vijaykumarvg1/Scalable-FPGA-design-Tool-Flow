

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use ieee.numeric_std.ALL;


--#buffer

entity design4 is
	port (
		CLK : in std_logic;					--clock
		NEWSLICE : in std_logic;			--reset: this is the first in a slice
		NEWLINE : in std_logic;				--this is the first in a line
		--
		VALIDI : in std_logic;				--luma/chroma data here (15/16/4 of these)
		ZIN : in std_logic_vector(11 downto 0);	--luma/chroma data
		READYI : out std_logic := '0';		--set when ready for next luma/chroma
		CCIN : out std_logic := '0';		--set when inputting chroma
		DONE : out std_logic := '0';		--set when all done and quiescent
		--
		VOUT : out std_logic_vector(11 downto 0) := (others=>'0');	--luma/chroma data
		VALIDO : out std_logic := '0';		--strobe for data out
		--
		NLOAD : out std_logic := '0';		--load for CAVLC NOUT
		NX : out std_logic_vector(2 downto 0) := b"000";	--X value for NIN/NOUT
		NY : out std_logic_vector(2 downto 0) := b"000";	--Y value for NIN/NOUT
		NV : out std_logic_vector(1 downto 0) := b"00";	--valid flags for NIN/NOUT (1=left, 2=top, 3=avg)
		NXINC : out std_logic := '0';		--increment for X macroblock counter
		--
		READYO : in std_logic;				--from cavlc module (goes inactive after block starts)
		TREADYO : in std_logic;				--from tobytes module: tells it to freeze
		HVALID : in std_logic				--when header module outputting
	);
end design4;

architecture hw of design4 is
	type Tbuf is array(511 downto 0) of std_logic_vector(11 downto 0);
	signal buf : Tbuf;
	--
	signal ix : std_logic_vector(3 downto 0) := x"0";	--index inside block
	signal isubmb : std_logic_vector(3 downto 0) := x"0";--index to blocks of luma
	signal ichsubmb : std_logic_vector(2 downto 0) := b"000";--index to blocks of chroma
	signal ichf : std_logic := '0';						--chroma flag
	signal ichdc : std_logic := '0';					--dc chroma flag
	signal imb : std_logic_vector(1 downto 0) := b"00";	--odd/even mb for chroma
	signal ox : std_logic_vector(3 downto 0) := x"0";	--index inside block
	signal osubmb : std_logic_vector(3 downto 0) := x"0";--index to blocks of luma
	signal ochf : std_logic := '0';						--chroma flag
	signal ochdc : std_logic := '0';					--dc chroma flag
	signal omb : std_logic_vector(1 downto 0) := b"00";	--odd/even mb for chroma
	signal nloadi : std_logic := '0';					--flag for nload (delay by 1)
	signal nxinci : std_logic := '0';					--flag for nload (delay by 1)
	signal nv0 : std_logic := '0';					--for NV(0)
	signal nv1 : std_logic := '0';					--for NV(1)
	signal nlvalid: std_logic := '0';					--left N is valid
	signal ntvalid: std_logic := '0';					--top N is valid
	signal ccinf : std_logic := '0';					--chroma in
	--
begin
	--
	READYI <= '1' when omb=imb or (ochf='1' and isubmb < 12) or 
			(isubmb+1 < osubmb and isubmb < 12) else '0';
	DONE <= '1' when omb=imb and isubmb=0 and osubmb=0 and READYO='1' else '0';
	nv0 <= '1' when nlvalid='1' or (osubmb(2)='1' and ochf='0') or osubmb(0)='1' else '0';
	nv1 <= '1' when ntvalid='1' or (osubmb(3)='1' and ochf='0') or osubmb(1)='1' else '0';
	--
process(CLK)
	variable addr : std_logic_vector(8 downto 0);
begin
	if rising_edge(CLK) then
		if NEWSLICE='1' then
			ix <= x"0";		--reset
			isubmb <= x"0";
			ichsubmb <= b"000";
			ichf <= '0';
			ichdc <= '0';
			imb <= b"00";
			ox <= x"0";
			osubmb <= x"0";
			ochf <= '0';
			ochdc <= '0';
			omb <= b"00";
			nloadi <= '0';
			nlvalid <= '0';
			ntvalid <= '0';
		elsif NEWLINE='1' then
			nlvalid <= '0';
			ntvalid <= '1';
		end if;
		--
		if VALIDI='1' and NEWSLICE='0' then
			if ichf='0' then
				addr := '0' & isubmb & ix;		
			elsif ichdc='0' then
				addr := '1' & imb(0) & ichsubmb & ix;
			else
				addr := '1' & imb(0) & ichsubmb(2) & (not ix(1 downto 0)) & x"F";
			end if;
			assert not is_x(ZIN) report "Problems with ZIN" severity WARNING;
			if ichf='0' or ix/=15 then
				buf(conv_integer(addr)) <= ZIN;
			end if;
			if ichf='0' then	--luma
				ix <= ix + 1;
				if ix=15 then
					isubmb <= isubmb+1;
					ichf <= not isubmb(0);	--switch to chroma after even blocks
					if isubmb=0 or isubmb=8 then
						ichdc <= '1';
					end if;
					if isubmb=15 then
						imb <= imb+1;
					end if;
					assert isubmb/=osubmb or ochf='1' or ox>ix or imb=omb report "xbuffer overflow?" severity ERROR;
				end if;
			elsif ichdc='1' then	--chromadc
				if ix=3 then
					ix <= x"0";
					ichdc <= '0';
				else
					ix <= ix + 1;
				end if;
			elsif ichdc='0' then
				ix <= ix + 1;
				if ix=15 then
					ichsubmb <= ichsubmb + 1;
					ichf <= '0';
				end if;
			end if;
		end if;
		if VALIDI='0' and NEWSLICE='0' then
			assert ix=0 report "VALIDI has fallen when in middle of block" severity WARNING;
		end if;
		--
		if NEWSLICE='0' and HVALID='0' and imb/=omb and ((TREADYO='1' and READYO='1') or ox/=0) then
			--output
			if ochf='0' then
				addr := '0' & osubmb & ox;
			elsif ochdc='1' then
				addr := '1' & omb(0) & osubmb(2) & ox(1 downto 0) & x"F";
			else
				addr := '1' & omb(0) & osubmb(2 downto 0) & ox;
			end if;	
			VOUT <= buf(conv_integer(addr));
			assert not is_x(buf(conv_integer(addr))) report "Problems with VOUT" severity WARNING;
			VALIDO <= '1';
			if ochf='0' then
				NX <= '0'&osubmb(2)&osubmb(0);
				NY <= '0'&osubmb(3)&osubmb(1);
			else
				NX <= '1'&osubmb(2)&osubmb(0);	--osubmb(2) is Cr/Cb flag
				NY <= '1'&osubmb(2)&osubmb(1);
			end if;
			if ochf='0' then
				ox <= ox+1;
				if ox=15 then
					osubmb <= osubmb+1;
					if osubmb=15 then
						ochf <= '1';
						ochdc <= '1';	--DC chroma follows Luma
					end if;
					nloadi <= '1';
				end if;
			elsif ochdc='1' then
				if ox/=3 then
					ox <= ox+1;
				else
					ox <= x"0";					
					osubmb(2) <= not osubmb(2);
					if osubmb(2)='1' then
						ochdc <= '0';	--AC chroma follows both DC chroma
					end if;
				end if;
			else
				if ox/=14 then
					ox <= ox+1;
				else
					ox <= x"0";
					osubmb(2 downto 0) <= osubmb(2 downto 0)+1;
					if osubmb(2 downto 0)=7 then
						ochf <= '0';
						omb <= omb+1;
						nxinci <= '1';
					end if;
					nloadi <= '1';
				end if;
			end if;
		else
			VALIDO <= '0';
		end if;
		NLOAD <= nloadi;
		NXINC <= nxinci;
		NV <= nv1&nv0;
		if nloadi='1' then
			nloadi <= '0';
		end if;
		if nxinci='1' then
			nxinci <= '0';
			nlvalid <= '1';
		end if;
		--
		ccinf <= ichf and VALIDI;
		CCIN <= ccinf;
	end if;
end process;
	--
end hw;	--h264buffer

--#buffer



--#cavlc


entity design4 is
	port (
		CLK : in std_logic;					--main clock / output clock
		CLK2 : in std_logic;				--input clock (typically twice CLK)
		ENABLE : in std_logic;				--values transfered only when this is 1
		READY : out std_logic;				--enable can fall when this 1
		VIN : in std_logic_vector(11 downto 0);	--12bits max (+/- 2048)
		NIN : in std_logic_vector(4 downto 0);	--N coeffs nearby mb
		SIN : in std_logic := '0';				--stream/strobe flag, copied to VS
		VS : out std_logic := '0';				--stream/strobe flag sync'd with VL/VE
		VE : out std_logic_vector(24 downto 0) := (others=>'0');
		VL : out std_logic_vector(4 downto 0) := (others=>'0');
		VALID : out std_logic := '0';			-- enable delayed to same as VE/VL
		XSTATE : out std_logic_vector(2 downto 0); 	--debug only
		NOUT : out std_logic_vector(4 downto 0) := b"00000"	--N coeffs for this mb
	);
end design4;

architecture hw of design4 is
	-- information collected from input when ENABLE=1
	-- all thse are in the "CLK2" timing domain
	signal eenable : std_logic := '0';			--1 if ENABLE=1 seen
	signal eparity : std_logic := '0';			--which register bank to use
	signal emaxcoeffs : std_logic_vector(4 downto 0) := b"00000";
	signal etotalcoeffs : std_logic_vector(4 downto 0) := b"00000";
	signal etotalzeros : std_logic_vector(4 downto 0) := b"00000";
	signal etrailingones : std_logic_vector(1 downto 0) := b"00";	--max 3 allowed
	signal ecnz : std_logic := '0';		--flag set if coeff nz so far
	signal ecgt1 : std_logic := '0';	--flag set if coeff >1 so far
	signal et1signs : std_logic_vector(2 downto 0) := b"000";		--signs of above (1=-ve)
	signal erun : std_logic_vector(3 downto 0) := b"0000";		--run before next coeff
	signal eindex : std_logic_vector(3 downto 0) := b"0000";	--index into coeff table
	signal etable : std_logic_vector(1 downto 0);
	signal es : std_logic := '0';				--s (stream) flag
	-- holding buffer; "CLK2" timing domain
	signal hvalidi : std_logic := '0';			--1 if holding buffer valid
	signal hvalid : std_logic := '0';			--1 if holding buffer valid (delayed 1 clk)
	signal hparity : std_logic := '0';			--which register bank to use
	signal hmaxcoeffs : std_logic_vector(4 downto 0) := b"00000";
	signal htotalcoeffs : std_logic_vector(4 downto 0) := b"00000";
	signal htotalzeros : std_logic_vector(4 downto 0) := b"00000";
	signal htrailingones : std_logic_vector(1 downto 0) := b"00";	--max 3 allowed
	signal htable : std_logic_vector(1 downto 0);
	signal hs : std_logic := '0';				--s (stream) flag
	signal t1signs : std_logic_vector(2 downto 0) := b"000";		--signs of above (1=-ve)
	--
	--information copied from above during STATE_IDLE or RUNBF
	--this is in the "CLK" domain
	signal maxcoeffs : std_logic_vector(4 downto 0) := b"00000";
	signal totalcoeffs : std_logic_vector(4 downto 0) := b"00000";
	signal totalzeros : std_logic_vector(4 downto 0) := b"00000";
	signal trailingones : std_logic_vector(1 downto 0) := b"00";	--max 3 allowed
	signal parity : std_logic := '0';			--which register bank to use
	--
	-- states private to this processing engine
	constant STATE_IDLE   : std_logic_vector(2 downto 0) := b"000";
	constant STATE_READ   : std_logic_vector(2 downto 0) := b"001";
	constant STATE_CTOKEN : std_logic_vector(2 downto 0) := b"010";
	constant STATE_T1SIGN : std_logic_vector(2 downto 0) := b"011";
	constant STATE_COEFFS : std_logic_vector(2 downto 0) := b"100";
	constant STATE_TZEROS : std_logic_vector(2 downto 0) := b"101";
	constant STATE_RUNBF  : std_logic_vector(2 downto 0) := b"110";
	signal state : std_logic_vector(2 downto 0) := STATE_IDLE;
	--
	-- runbefore subprocessor state
	signal rbstate : std_logic := '0';		--1=running 0=done
	--
	--stuff used during processing
	signal cindex : std_logic_vector(3 downto 0) := b"0000";	--index into coeff table
	signal abscoeff : std_logic_vector(10 downto 0);
	signal abscoeffa : std_logic_vector(10 downto 0);			--adjusted version of abscoeff
	signal signcoeff : std_logic := '0';
	signal suffixlen : std_logic_vector(2 downto 0);			--0..6
	signal rbindex : std_logic_vector(3 downto 0) := b"0000";	--index into coeff table
	signal runb : std_logic_vector(3 downto 0) := b"0000";		--run before next coeff
	signal rbzerosleft : std_logic_vector(4 downto 0) := b"00000";
	signal rbve : std_logic_vector(24 downto 0) := (others => '0');
	signal rbvl : std_logic_vector(4 downto 0) := b"00000";
	--tables
	signal coeff_token : std_logic_vector(5 downto 0);
	signal ctoken_len : std_logic_vector(4 downto 0);
	constant CTABLE0 : std_logic_vector(2 downto 0) := b"000";
	constant CTABLE1 : std_logic_vector(2 downto 0) := b"001";
	constant CTABLE2 : std_logic_vector(2 downto 0) := b"010";
	constant CTABLE3 : std_logic_vector(2 downto 0) := b"011";
	constant CTABLE4 : std_logic_vector(2 downto 0) := b"100";
	signal ctable : std_logic_vector(2 downto 0) := CTABLE0;
	signal ztoken : std_logic_vector(2 downto 0);
	signal ztoken_len : std_logic_vector(3 downto 0);
	signal ztable : std_logic := '0';
	signal rbtoken : std_logic_vector(2 downto 0);
	--data arrays
	type Tcoeffarray is array(31 downto 0) of std_logic_vector(11 downto 0);
	type Trunbarray is array(31 downto 0) of std_logic_vector(3 downto 0);
	signal coeffarray : Tcoeffarray := (others=>x"000");
	signal runbarray : Trunbarray := (others=>x"0");
	--
begin
	XSTATE <= state;	--DEBUG only
	--
	-- tables for coeff_token
	--
	coeff_token <=
		b"000001" when trailingones=0 and totalcoeffs=0 and ctable=0 else
		b"000101" when trailingones=0 and totalcoeffs=1 and ctable=0 else
		b"000001" when trailingones=1 and totalcoeffs=1 and ctable=0 else
		b"000111" when trailingones=0 and totalcoeffs=2 and ctable=0 else
		b"000100" when trailingones=1 and totalcoeffs=2 and ctable=0 else
		b"000001" when trailingones=2 and totalcoeffs=2 and ctable=0 else
		b"000111" when trailingones=0 and totalcoeffs=3 and ctable=0 else
		b"000110" when trailingones=1 and totalcoeffs=3 and ctable=0 else
		b"000101" when trailingones=2 and totalcoeffs=3 and ctable=0 else
		b"000011" when trailingones=3 and totalcoeffs=3 and ctable=0 else
		b"000111" when trailingones=0 and totalcoeffs=4 and ctable=0 else
		b"000110" when trailingones=1 and totalcoeffs=4 and ctable=0 else
		b"000101" when trailingones=2 and totalcoeffs=4 and ctable=0 else
		b"000011" when trailingones=3 and totalcoeffs=4 and ctable=0 else
		b"000111" when trailingones=0 and totalcoeffs=5 and ctable=0 else
		b"000110" when trailingones=1 and totalcoeffs=5 and ctable=0 else
		b"000101" when trailingones=2 and totalcoeffs=5 and ctable=0 else
		b"000100" when trailingones=3 and totalcoeffs=5 and ctable=0 else
		b"001111" when trailingones=0 and totalcoeffs=6 and ctable=0 else
		b"000110" when trailingones=1 and totalcoeffs=6 and ctable=0 else
		b"000101" when trailingones=2 and totalcoeffs=6 and ctable=0 else
		b"000100" when trailingones=3 and totalcoeffs=6 and ctable=0 else
		b"001011" when trailingones=0 and totalcoeffs=7 and ctable=0 else
		b"001110" when trailingones=1 and totalcoeffs=7 and ctable=0 else
		b"000101" when trailingones=2 and totalcoeffs=7 and ctable=0 else
		b"000100" when trailingones=3 and totalcoeffs=7 and ctable=0 else
		b"001000" when trailingones=0 and totalcoeffs=8 and ctable=0 else
		b"001010" when trailingones=1 and totalcoeffs=8 and ctable=0 else
		b"001101" when trailingones=2 and totalcoeffs=8 and ctable=0 else
		b"000100" when trailingones=3 and totalcoeffs=8 and ctable=0 else
		b"001111" when trailingones=0 and totalcoeffs=9 and ctable=0 else
		b"001110" when trailingones=1 and totalcoeffs=9 and ctable=0 else
		b"001001" when trailingones=2 and totalcoeffs=9 and ctable=0 else
		b"000100" when trailingones=3 and totalcoeffs=9 and ctable=0 else
		b"001011" when trailingones=0 and totalcoeffs=10 and ctable=0 else
		b"001010" when trailingones=1 and totalcoeffs=10 and ctable=0 else
		b"001101" when trailingones=2 and totalcoeffs=10 and ctable=0 else
		b"001100" when trailingones=3 and totalcoeffs=10 and ctable=0 else
		b"001111" when trailingones=0 and totalcoeffs=11 and ctable=0 else
		b"001110" when trailingones=1 and totalcoeffs=11 and ctable=0 else
		b"001001" when trailingones=2 and totalcoeffs=11 and ctable=0 else
		b"001100" when trailingones=3 and totalcoeffs=11 and ctable=0 else
		b"001011" when trailingones=0 and totalcoeffs=12 and ctable=0 else
		b"001010" when trailingones=1 and totalcoeffs=12 and ctable=0 else
		b"001101" when trailingones=2 and totalcoeffs=12 and ctable=0 else
		b"001000" when trailingones=3 and totalcoeffs=12 and ctable=0 else
		b"001111" when trailingones=0 and totalcoeffs=13 and ctable=0 else
		b"000001" when trailingones=1 and totalcoeffs=13 and ctable=0 else
		b"001001" when trailingones=2 and totalcoeffs=13 and ctable=0 else
		b"001100" when trailingones=3 and totalcoeffs=13 and ctable=0 else
		b"001011" when trailingones=0 and totalcoeffs=14 and ctable=0 else
		b"001110" when trailingones=1 and totalcoeffs=14 and ctable=0 else
		b"001101" when trailingones=2 and totalcoeffs=14 and ctable=0 else
		b"001000" when trailingones=3 and totalcoeffs=14 and ctable=0 else
		b"000111" when trailingones=0 and totalcoeffs=15 and ctable=0 else
		b"001010" when trailingones=1 and totalcoeffs=15 and ctable=0 else
		b"001001" when trailingones=2 and totalcoeffs=15 and ctable=0 else
		b"001100" when trailingones=3 and totalcoeffs=15 and ctable=0 else
		b"000100" when trailingones=0 and totalcoeffs=16 and ctable=0 else
		b"000110" when trailingones=1 and totalcoeffs=16 and ctable=0 else
		b"000101" when trailingones=2 and totalcoeffs=16 and ctable=0 else
		b"001000" when trailingones=3 and totalcoeffs=16 and ctable=0 else
		--
		b"000011" when trailingones=0 and totalcoeffs=0 and ctable=1 else
		b"001011" when trailingones=0 and totalcoeffs=1 and ctable=1 else
		b"000010" when trailingones=1 and totalcoeffs=1 and ctable=1 else
		b"000111" when trailingones=0 and totalcoeffs=2 and ctable=1 else
		b"000111" when trailingones=1 and totalcoeffs=2 and ctable=1 else
		b"000011" when trailingones=2 and totalcoeffs=2 and ctable=1 else
		b"000111" when trailingones=0 and totalcoeffs=3 and ctable=1 else
		b"001010" when trailingones=1 and totalcoeffs=3 and ctable=1 else
		b"001001" when trailingones=2 and totalcoeffs=3 and ctable=1 else
		b"000101" when trailingones=3 and totalcoeffs=3 and ctable=1 else
		b"000111" when trailingones=0 and totalcoeffs=4 and ctable=1 else
		b"000110" when trailingones=1 and totalcoeffs=4 and ctable=1 else
		b"000101" when trailingones=2 and totalcoeffs=4 and ctable=1 else
		b"000100" when trailingones=3 and totalcoeffs=4 and ctable=1 else
		b"000100" when trailingones=0 and totalcoeffs=5 and ctable=1 else
		b"000110" when trailingones=1 and totalcoeffs=5 and ctable=1 else
		b"000101" when trailingones=2 and totalcoeffs=5 and ctable=1 else
		b"000110" when trailingones=3 and totalcoeffs=5 and ctable=1 else
		b"000111" when trailingones=0 and totalcoeffs=6 and ctable=1 else
		b"000110" when trailingones=1 and totalcoeffs=6 and ctable=1 else
		b"000101" when trailingones=2 and totalcoeffs=6 and ctable=1 else
		b"001000" when trailingones=3 and totalcoeffs=6 and ctable=1 else
		b"001111" when trailingones=0 and totalcoeffs=7 and ctable=1 else
		b"000110" when trailingones=1 and totalcoeffs=7 and ctable=1 else
		b"000101" when trailingones=2 and totalcoeffs=7 and ctable=1 else
		b"000100" when trailingones=3 and totalcoeffs=7 and ctable=1 else
		b"001011" when trailingones=0 and totalcoeffs=8 and ctable=1 else
		b"001110" when trailingones=1 and totalcoeffs=8 and ctable=1 else
		b"001101" when trailingones=2 and totalcoeffs=8 and ctable=1 else
		b"000100" when trailingones=3 and totalcoeffs=8 and ctable=1 else
		b"001111" when trailingones=0 and totalcoeffs=9 and ctable=1 else
		b"001010" when trailingones=1 and totalcoeffs=9 and ctable=1 else
		b"001001" when trailingones=2 and totalcoeffs=9 and ctable=1 else
		b"000100" when trailingones=3 and totalcoeffs=9 and ctable=1 else
		b"001011" when trailingones=0 and totalcoeffs=10 and ctable=1 else
		b"001110" when trailingones=1 and totalcoeffs=10 and ctable=1 else
		b"001101" when trailingones=2 and totalcoeffs=10 and ctable=1 else
		b"001100" when trailingones=3 and totalcoeffs=10 and ctable=1 else
		b"001000" when trailingones=0 and totalcoeffs=11 and ctable=1 else
		b"001010" when trailingones=1 and totalcoeffs=11 and ctable=1 else
		b"001001" when trailingones=2 and totalcoeffs=11 and ctable=1 else
		b"001000" when trailingones=3 and totalcoeffs=11 and ctable=1 else
		b"001111" when trailingones=0 and totalcoeffs=12 and ctable=1 else
		b"001110" when trailingones=1 and totalcoeffs=12 and ctable=1 else
		b"001101" when trailingones=2 and totalcoeffs=12 and ctable=1 else
		b"001100" when trailingones=3 and totalcoeffs=12 and ctable=1 else
		b"001011" when trailingones=0 and totalcoeffs=13 and ctable=1 else
		b"001010" when trailingones=1 and totalcoeffs=13 and ctable=1 else
		b"001001" when trailingones=2 and totalcoeffs=13 and ctable=1 else
		b"001100" when trailingones=3 and totalcoeffs=13 and ctable=1 else
		b"000111" when trailingones=0 and totalcoeffs=14 and ctable=1 else
		b"001011" when trailingones=1 and totalcoeffs=14 and ctable=1 else
		b"000110" when trailingones=2 and totalcoeffs=14 and ctable=1 else
		b"001000" when trailingones=3 and totalcoeffs=14 and ctable=1 else
		b"001001" when trailingones=0 and totalcoeffs=15 and ctable=1 else
		b"001000" when trailingones=1 and totalcoeffs=15 and ctable=1 else
		b"001010" when trailingones=2 and totalcoeffs=15 and ctable=1 else
		b"000001" when trailingones=3 and totalcoeffs=15 and ctable=1 else
		b"000111" when trailingones=0 and totalcoeffs=16 and ctable=1 else
		b"000110" when trailingones=1 and totalcoeffs=16 and ctable=1 else
		b"000101" when trailingones=2 and totalcoeffs=16 and ctable=1 else
		b"000100" when trailingones=3 and totalcoeffs=16 and ctable=1 else
		--
		b"001111" when trailingones=0 and totalcoeffs=0 and ctable=2 else
		b"001111" when trailingones=0 and totalcoeffs=1 and ctable=2 else
		b"001110" when trailingones=1 and totalcoeffs=1 and ctable=2 else
		b"001011" when trailingones=0 and totalcoeffs=2 and ctable=2 else
		b"001111" when trailingones=1 and totalcoeffs=2 and ctable=2 else
		b"001101" when trailingones=2 and totalcoeffs=2 and ctable=2 else
		b"001000" when trailingones=0 and totalcoeffs=3 and ctable=2 else
		b"001100" when trailingones=1 and totalcoeffs=3 and ctable=2 else
		b"001110" when trailingones=2 and totalcoeffs=3 and ctable=2 else
		b"001100" when trailingones=3 and totalcoeffs=3 and ctable=2 else
		b"001111" when trailingones=0 and totalcoeffs=4 and ctable=2 else
		b"001010" when trailingones=1 and totalcoeffs=4 and ctable=2 else
		b"001011" when trailingones=2 and totalcoeffs=4 and ctable=2 else
		b"001011" when trailingones=3 and totalcoeffs=4 and ctable=2 else
		b"001011" when trailingones=0 and totalcoeffs=5 and ctable=2 else
		b"001000" when trailingones=1 and totalcoeffs=5 and ctable=2 else
		b"001001" when trailingones=2 and totalcoeffs=5 and ctable=2 else
		b"001010" when trailingones=3 and totalcoeffs=5 and ctable=2 else
		b"001001" when trailingones=0 and totalcoeffs=6 and ctable=2 else
		b"001110" when trailingones=1 and totalcoeffs=6 and ctable=2 else
		b"001101" when trailingones=2 and totalcoeffs=6 and ctable=2 else
		b"001001" when trailingones=3 and totalcoeffs=6 and ctable=2 else
		b"001000" when trailingones=0 and totalcoeffs=7 and ctable=2 else
		b"001010" when trailingones=1 and totalcoeffs=7 and ctable=2 else
		b"001001" when trailingones=2 and totalcoeffs=7 and ctable=2 else
		b"001000" when trailingones=3 and totalcoeffs=7 and ctable=2 else
		b"001111" when trailingones=0 and totalcoeffs=8 and ctable=2 else
		b"001110" when trailingones=1 and totalcoeffs=8 and ctable=2 else
		b"001101" when trailingones=2 and totalcoeffs=8 and ctable=2 else
		b"001101" when trailingones=3 and totalcoeffs=8 and ctable=2 else
		b"001011" when trailingones=0 and totalcoeffs=9 and ctable=2 else
		b"001110" when trailingones=1 and totalcoeffs=9 and ctable=2 else
		b"001010" when trailingones=2 and totalcoeffs=9 and ctable=2 else
		b"001100" when trailingones=3 and totalcoeffs=9 and ctable=2 else
		b"001111" when trailingones=0 and totalcoeffs=10 and ctable=2 else
		b"001010" when trailingones=1 and totalcoeffs=10 and ctable=2 else
		b"001101" when trailingones=2 and totalcoeffs=10 and ctable=2 else
		b"001100" when trailingones=3 and totalcoeffs=10 and ctable=2 else
		b"001011" when trailingones=0 and totalcoeffs=11 and ctable=2 else
		b"001110" when trailingones=1 and totalcoeffs=11 and ctable=2 else
		b"001001" when trailingones=2 and totalcoeffs=11 and ctable=2 else
		b"001100" when trailingones=3 and totalcoeffs=11 and ctable=2 else
		b"001000" when trailingones=0 and totalcoeffs=12 and ctable=2 else
		b"001010" when trailingones=1 and totalcoeffs=12 and ctable=2 else
		b"001101" when trailingones=2 and totalcoeffs=12 and ctable=2 else
		b"001000" when trailingones=3 and totalcoeffs=12 and ctable=2 else
		b"001101" when trailingones=0 and totalcoeffs=13 and ctable=2 else
		b"000111" when trailingones=1 and totalcoeffs=13 and ctable=2 else
		b"001001" when trailingones=2 and totalcoeffs=13 and ctable=2 else
		b"001100" when trailingones=3 and totalcoeffs=13 and ctable=2 else
		b"001001" when trailingones=0 and totalcoeffs=14 and ctable=2 else
		b"001100" when trailingones=1 and totalcoeffs=14 and ctable=2 else
		b"001011" when trailingones=2 and totalcoeffs=14 and ctable=2 else
		b"001010" when trailingones=3 and totalcoeffs=14 and ctable=2 else
		b"000101" when trailingones=0 and totalcoeffs=15 and ctable=2 else
		b"001000" when trailingones=1 and totalcoeffs=15 and ctable=2 else
		b"000111" when trailingones=2 and totalcoeffs=15 and ctable=2 else
		b"000110" when trailingones=3 and totalcoeffs=15 and ctable=2 else
		b"000001" when trailingones=0 and totalcoeffs=16 and ctable=2 else
		b"000100" when trailingones=1 and totalcoeffs=16 and ctable=2 else
		b"000011" when trailingones=2 and totalcoeffs=16 and ctable=2 else
		b"000010" when trailingones=3 and totalcoeffs=16 and ctable=2 else
		--
		b"000011" when trailingones=0 and totalcoeffs=0 and ctable=3 else
		b"000000" when trailingones=0 and totalcoeffs=1 and ctable=3 else
		b"000001" when trailingones=1 and totalcoeffs=1 and ctable=3 else
		b"000100" when trailingones=0 and totalcoeffs=2 and ctable=3 else
		b"000101" when trailingones=1 and totalcoeffs=2 and ctable=3 else
		b"000110" when trailingones=2 and totalcoeffs=2 and ctable=3 else
		b"001000" when trailingones=0 and totalcoeffs=3 and ctable=3 else
		b"001001" when trailingones=1 and totalcoeffs=3 and ctable=3 else
		b"001010" when trailingones=2 and totalcoeffs=3 and ctable=3 else
		b"001011" when trailingones=3 and totalcoeffs=3 and ctable=3 else
		b"001100" when trailingones=0 and totalcoeffs=4 and ctable=3 else
		b"001101" when trailingones=1 and totalcoeffs=4 and ctable=3 else
		b"001110" when trailingones=2 and totalcoeffs=4 and ctable=3 else
		b"001111" when trailingones=3 and totalcoeffs=4 and ctable=3 else
		b"010000" when trailingones=0 and totalcoeffs=5 and ctable=3 else
		b"010001" when trailingones=1 and totalcoeffs=5 and ctable=3 else
		b"010010" when trailingones=2 and totalcoeffs=5 and ctable=3 else
		b"010011" when trailingones=3 and totalcoeffs=5 and ctable=3 else
		b"010100" when trailingones=0 and totalcoeffs=6 and ctable=3 else
		b"010101" when trailingones=1 and totalcoeffs=6 and ctable=3 else
		b"010110" when trailingones=2 and totalcoeffs=6 and ctable=3 else
		b"010111" when trailingones=3 and totalcoeffs=6 and ctable=3 else
		b"011000" when trailingones=0 and totalcoeffs=7 and ctable=3 else
		b"011001" when trailingones=1 and totalcoeffs=7 and ctable=3 else
		b"011010" when trailingones=2 and totalcoeffs=7 and ctable=3 else
		b"011011" when trailingones=3 and totalcoeffs=7 and ctable=3 else
		b"011100" when trailingones=0 and totalcoeffs=8 and ctable=3 else
		b"011101" when trailingones=1 and totalcoeffs=8 and ctable=3 else
		b"011110" when trailingones=2 and totalcoeffs=8 and ctable=3 else
		b"011111" when trailingones=3 and totalcoeffs=8 and ctable=3 else
		b"100000" when trailingones=0 and totalcoeffs=9 and ctable=3 else
		b"100001" when trailingones=1 and totalcoeffs=9 and ctable=3 else
		b"100010" when trailingones=2 and totalcoeffs=9 and ctable=3 else
		b"100011" when trailingones=3 and totalcoeffs=9 and ctable=3 else
		b"100100" when trailingones=0 and totalcoeffs=10 and ctable=3 else
		b"100101" when trailingones=1 and totalcoeffs=10 and ctable=3 else
		b"100110" when trailingones=2 and totalcoeffs=10 and ctable=3 else
		b"100111" when trailingones=3 and totalcoeffs=10 and ctable=3 else
		b"101000" when trailingones=0 and totalcoeffs=11 and ctable=3 else
		b"101001" when trailingones=1 and totalcoeffs=11 and ctable=3 else
		b"101010" when trailingones=2 and totalcoeffs=11 and ctable=3 else
		b"101011" when trailingones=3 and totalcoeffs=11 and ctable=3 else
		b"101100" when trailingones=0 and totalcoeffs=12 and ctable=3 else
		b"101101" when trailingones=1 and totalcoeffs=12 and ctable=3 else
		b"101110" when trailingones=2 and totalcoeffs=12 and ctable=3 else
		b"101111" when trailingones=3 and totalcoeffs=12 and ctable=3 else
		b"110000" when trailingones=0 and totalcoeffs=13 and ctable=3 else
		b"110001" when trailingones=1 and totalcoeffs=13 and ctable=3 else
		b"110010" when trailingones=2 and totalcoeffs=13 and ctable=3 else
		b"110011" when trailingones=3 and totalcoeffs=13 and ctable=3 else
		b"110100" when trailingones=0 and totalcoeffs=14 and ctable=3 else
		b"110101" when trailingones=1 and totalcoeffs=14 and ctable=3 else
		b"110110" when trailingones=2 and totalcoeffs=14 and ctable=3 else
		b"110111" when trailingones=3 and totalcoeffs=14 and ctable=3 else
		b"111000" when trailingones=0 and totalcoeffs=15 and ctable=3 else
		b"111001" when trailingones=1 and totalcoeffs=15 and ctable=3 else
		b"111010" when trailingones=2 and totalcoeffs=15 and ctable=3 else
		b"111011" when trailingones=3 and totalcoeffs=15 and ctable=3 else
		b"111100" when trailingones=0 and totalcoeffs=16 and ctable=3 else
		b"111101" when trailingones=1 and totalcoeffs=16 and ctable=3 else
		b"111110" when trailingones=2 and totalcoeffs=16 and ctable=3 else
		b"111111" when trailingones=3 and totalcoeffs=16 and ctable=3 else
		--
		b"000001" when trailingones=0 and totalcoeffs=0 and ctable=4 else
		b"000111" when trailingones=0 and totalcoeffs=1 and ctable=4 else
		b"000001" when trailingones=1 and totalcoeffs=1 and ctable=4 else
		b"000100" when trailingones=0 and totalcoeffs=2 and ctable=4 else
		b"000110" when trailingones=1 and totalcoeffs=2 and ctable=4 else
		b"000001" when trailingones=2 and totalcoeffs=2 and ctable=4 else
		b"000011" when trailingones=0 and totalcoeffs=3 and ctable=4 else
		b"000011" when trailingones=1 and totalcoeffs=3 and ctable=4 else
		b"000010" when trailingones=2 and totalcoeffs=3 and ctable=4 else
		b"000101" when trailingones=3 and totalcoeffs=3 and ctable=4 else
		b"000010" when trailingones=0 and totalcoeffs=4 and ctable=4 else
		b"000011" when trailingones=1 and totalcoeffs=4 and ctable=4 else
		b"000010" when trailingones=2 and totalcoeffs=4 and ctable=4 else
		b"000000"; --  trailingones=3 and totalcoeffs=4 and ctable=4
	--
	ctoken_len <=
		b"00001" when trailingones=0 and totalcoeffs=0 and ctable=0 else
		b"00110" when trailingones=0 and totalcoeffs=1 and ctable=0 else
		b"00010" when trailingones=1 and totalcoeffs=1 and ctable=0 else
		b"01000" when trailingones=0 and totalcoeffs=2 and ctable=0 else
		b"00110" when trailingones=1 and totalcoeffs=2 and ctable=0 else
		b"00011" when trailingones=2 and totalcoeffs=2 and ctable=0 else
		b"01001" when trailingones=0 and totalcoeffs=3 and ctable=0 else
		b"01000" when trailingones=1 and totalcoeffs=3 and ctable=0 else
		b"00111" when trailingones=2 and totalcoeffs=3 and ctable=0 else
		b"00101" when trailingones=3 and totalcoeffs=3 and ctable=0 else
		b"01010" when trailingones=0 and totalcoeffs=4 and ctable=0 else
		b"01001" when trailingones=1 and totalcoeffs=4 and ctable=0 else
		b"01000" when trailingones=2 and totalcoeffs=4 and ctable=0 else
		b"00110" when trailingones=3 and totalcoeffs=4 and ctable=0 else
		b"01011" when trailingones=0 and totalcoeffs=5 and ctable=0 else
		b"01010" when trailingones=1 and totalcoeffs=5 and ctable=0 else
		b"01001" when trailingones=2 and totalcoeffs=5 and ctable=0 else
		b"00111" when trailingones=3 and totalcoeffs=5 and ctable=0 else
		b"01101" when trailingones=0 and totalcoeffs=6 and ctable=0 else
		b"01011" when trailingones=1 and totalcoeffs=6 and ctable=0 else
		b"01010" when trailingones=2 and totalcoeffs=6 and ctable=0 else
		b"01000" when trailingones=3 and totalcoeffs=6 and ctable=0 else
		b"01101" when trailingones=0 and totalcoeffs=7 and ctable=0 else
		b"01101" when trailingones=1 and totalcoeffs=7 and ctable=0 else
		b"01011" when trailingones=2 and totalcoeffs=7 and ctable=0 else
		b"01001" when trailingones=3 and totalcoeffs=7 and ctable=0 else
		b"01101" when trailingones=0 and totalcoeffs=8 and ctable=0 else
		b"01101" when trailingones=1 and totalcoeffs=8 and ctable=0 else
		b"01101" when trailingones=2 and totalcoeffs=8 and ctable=0 else
		b"01010" when trailingones=3 and totalcoeffs=8 and ctable=0 else
		b"01110" when trailingones=0 and totalcoeffs=9 and ctable=0 else
		b"01110" when trailingones=1 and totalcoeffs=9 and ctable=0 else
		b"01101" when trailingones=2 and totalcoeffs=9 and ctable=0 else
		b"01011" when trailingones=3 and totalcoeffs=9 and ctable=0 else
		b"01110" when trailingones=0 and totalcoeffs=10 and ctable=0 else
		b"01110" when trailingones=1 and totalcoeffs=10 and ctable=0 else
		b"01110" when trailingones=2 and totalcoeffs=10 and ctable=0 else
		b"01101" when trailingones=3 and totalcoeffs=10 and ctable=0 else
		b"01111" when trailingones=0 and totalcoeffs=11 and ctable=0 else
		b"01111" when trailingones=1 and totalcoeffs=11 and ctable=0 else
		b"01110" when trailingones=2 and totalcoeffs=11 and ctable=0 else
		b"01110" when trailingones=3 and totalcoeffs=11 and ctable=0 else
		b"01111" when trailingones=0 and totalcoeffs=12 and ctable=0 else
		b"01111" when trailingones=1 and totalcoeffs=12 and ctable=0 else
		b"01111" when trailingones=2 and totalcoeffs=12 and ctable=0 else
		b"01110" when trailingones=3 and totalcoeffs=12 and ctable=0 else
		b"10000" when trailingones=0 and totalcoeffs=13 and ctable=0 else
		b"01111" when trailingones=1 and totalcoeffs=13 and ctable=0 else
		b"01111" when trailingones=2 and totalcoeffs=13 and ctable=0 else
		b"01111" when trailingones=3 and totalcoeffs=13 and ctable=0 else
		b"10000" when trailingones=0 and totalcoeffs=14 and ctable=0 else
		b"10000" when trailingones=1 and totalcoeffs=14 and ctable=0 else
		b"10000" when trailingones=2 and totalcoeffs=14 and ctable=0 else
		b"01111" when trailingones=3 and totalcoeffs=14 and ctable=0 else
		b"10000" when trailingones=0 and totalcoeffs=15 and ctable=0 else
		b"10000" when trailingones=1 and totalcoeffs=15 and ctable=0 else
		b"10000" when trailingones=2 and totalcoeffs=15 and ctable=0 else
		b"10000" when trailingones=3 and totalcoeffs=15 and ctable=0 else
		b"10000" when trailingones=0 and totalcoeffs=16 and ctable=0 else
		b"10000" when trailingones=1 and totalcoeffs=16 and ctable=0 else
		b"10000" when trailingones=2 and totalcoeffs=16 and ctable=0 else
		b"10000" when trailingones=3 and totalcoeffs=16 and ctable=0 else
		--
		b"00010" when trailingones=0 and totalcoeffs=0 and ctable=1 else
		b"00110" when trailingones=0 and totalcoeffs=1 and ctable=1 else
		b"00010" when trailingones=1 and totalcoeffs=1 and ctable=1 else
		b"00110" when trailingones=0 and totalcoeffs=2 and ctable=1 else
		b"00101" when trailingones=1 and totalcoeffs=2 and ctable=1 else
		b"00011" when trailingones=2 and totalcoeffs=2 and ctable=1 else
		b"00111" when trailingones=0 and totalcoeffs=3 and ctable=1 else
		b"00110" when trailingones=1 and totalcoeffs=3 and ctable=1 else
		b"00110" when trailingones=2 and totalcoeffs=3 and ctable=1 else
		b"00100" when trailingones=3 and totalcoeffs=3 and ctable=1 else
		b"01000" when trailingones=0 and totalcoeffs=4 and ctable=1 else
		b"00110" when trailingones=1 and totalcoeffs=4 and ctable=1 else
		b"00110" when trailingones=2 and totalcoeffs=4 and ctable=1 else
		b"00100" when trailingones=3 and totalcoeffs=4 and ctable=1 else
		b"01000" when trailingones=0 and totalcoeffs=5 and ctable=1 else
		b"00111" when trailingones=1 and totalcoeffs=5 and ctable=1 else
		b"00111" when trailingones=2 and totalcoeffs=5 and ctable=1 else
		b"00101" when trailingones=3 and totalcoeffs=5 and ctable=1 else
		b"01001" when trailingones=0 and totalcoeffs=6 and ctable=1 else
		b"01000" when trailingones=1 and totalcoeffs=6 and ctable=1 else
		b"01000" when trailingones=2 and totalcoeffs=6 and ctable=1 else
		b"00110" when trailingones=3 and totalcoeffs=6 and ctable=1 else
		b"01011" when trailingones=0 and totalcoeffs=7 and ctable=1 else
		b"01001" when trailingones=1 and totalcoeffs=7 and ctable=1 else
		b"01001" when trailingones=2 and totalcoeffs=7 and ctable=1 else
		b"00110" when trailingones=3 and totalcoeffs=7 and ctable=1 else
		b"01011" when trailingones=0 and totalcoeffs=8 and ctable=1 else
		b"01011" when trailingones=1 and totalcoeffs=8 and ctable=1 else
		b"01011" when trailingones=2 and totalcoeffs=8 and ctable=1 else
		b"00111" when trailingones=3 and totalcoeffs=8 and ctable=1 else
		b"01100" when trailingones=0 and totalcoeffs=9 and ctable=1 else
		b"01011" when trailingones=1 and totalcoeffs=9 and ctable=1 else
		b"01011" when trailingones=2 and totalcoeffs=9 and ctable=1 else
		b"01001" when trailingones=3 and totalcoeffs=9 and ctable=1 else
		b"01100" when trailingones=0 and totalcoeffs=10 and ctable=1 else
		b"01100" when trailingones=1 and totalcoeffs=10 and ctable=1 else
		b"01100" when trailingones=2 and totalcoeffs=10 and ctable=1 else
		b"01011" when trailingones=3 and totalcoeffs=10 and ctable=1 else
		b"01100" when trailingones=0 and totalcoeffs=11 and ctable=1 else
		b"01100" when trailingones=1 and totalcoeffs=11 and ctable=1 else
		b"01100" when trailingones=2 and totalcoeffs=11 and ctable=1 else
		b"01011" when trailingones=3 and totalcoeffs=11 and ctable=1 else
		b"01101" when trailingones=0 and totalcoeffs=12 and ctable=1 else
		b"01101" when trailingones=1 and totalcoeffs=12 and ctable=1 else
		b"01101" when trailingones=2 and totalcoeffs=12 and ctable=1 else
		b"01100" when trailingones=3 and totalcoeffs=12 and ctable=1 else
		b"01101" when trailingones=0 and totalcoeffs=13 and ctable=1 else
		b"01101" when trailingones=1 and totalcoeffs=13 and ctable=1 else
		b"01101" when trailingones=2 and totalcoeffs=13 and ctable=1 else
		b"01101" when trailingones=3 and totalcoeffs=13 and ctable=1 else
		b"01101" when trailingones=0 and totalcoeffs=14 and ctable=1 else
		b"01110" when trailingones=1 and totalcoeffs=14 and ctable=1 else
		b"01101" when trailingones=2 and totalcoeffs=14 and ctable=1 else
		b"01101" when trailingones=3 and totalcoeffs=14 and ctable=1 else
		b"01110" when trailingones=0 and totalcoeffs=15 and ctable=1 else
		b"01110" when trailingones=1 and totalcoeffs=15 and ctable=1 else
		b"01110" when trailingones=2 and totalcoeffs=15 and ctable=1 else
		b"01101" when trailingones=3 and totalcoeffs=15 and ctable=1 else
		b"01110" when trailingones=0 and totalcoeffs=16 and ctable=1 else
		b"01110" when trailingones=1 and totalcoeffs=16 and ctable=1 else
		b"01110" when trailingones=2 and totalcoeffs=16 and ctable=1 else
		b"01110" when trailingones=3 and totalcoeffs=16 and ctable=1 else
		--
		b"00100" when trailingones=0 and totalcoeffs=0 and ctable=2 else
		b"00110" when trailingones=0 and totalcoeffs=1 and ctable=2 else
		b"00100" when trailingones=1 and totalcoeffs=1 and ctable=2 else
		b"00110" when trailingones=0 and totalcoeffs=2 and ctable=2 else
		b"00101" when trailingones=1 and totalcoeffs=2 and ctable=2 else
		b"00100" when trailingones=2 and totalcoeffs=2 and ctable=2 else
		b"00110" when trailingones=0 and totalcoeffs=3 and ctable=2 else
		b"00101" when trailingones=1 and totalcoeffs=3 and ctable=2 else
		b"00101" when trailingones=2 and totalcoeffs=3 and ctable=2 else
		b"00100" when trailingones=3 and totalcoeffs=3 and ctable=2 else
		b"00111" when trailingones=0 and totalcoeffs=4 and ctable=2 else
		b"00101" when trailingones=1 and totalcoeffs=4 and ctable=2 else
		b"00101" when trailingones=2 and totalcoeffs=4 and ctable=2 else
		b"00100" when trailingones=3 and totalcoeffs=4 and ctable=2 else
		b"00111" when trailingones=0 and totalcoeffs=5 and ctable=2 else
		b"00101" when trailingones=1 and totalcoeffs=5 and ctable=2 else
		b"00101" when trailingones=2 and totalcoeffs=5 and ctable=2 else
		b"00100" when trailingones=3 and totalcoeffs=5 and ctable=2 else
		b"00111" when trailingones=0 and totalcoeffs=6 and ctable=2 else
		b"00110" when trailingones=1 and totalcoeffs=6 and ctable=2 else
		b"00110" when trailingones=2 and totalcoeffs=6 and ctable=2 else
		b"00100" when trailingones=3 and totalcoeffs=6 and ctable=2 else
		b"00111" when trailingones=0 and totalcoeffs=7 and ctable=2 else
		b"00110" when trailingones=1 and totalcoeffs=7 and ctable=2 else
		b"00110" when trailingones=2 and totalcoeffs=7 and ctable=2 else
		b"00100" when trailingones=3 and totalcoeffs=7 and ctable=2 else
		b"01000" when trailingones=0 and totalcoeffs=8 and ctable=2 else
		b"00111" when trailingones=1 and totalcoeffs=8 and ctable=2 else
		b"00111" when trailingones=2 and totalcoeffs=8 and ctable=2 else
		b"00101" when trailingones=3 and totalcoeffs=8 and ctable=2 else
		b"01000" when trailingones=0 and totalcoeffs=9 and ctable=2 else
		b"01000" when trailingones=1 and totalcoeffs=9 and ctable=2 else
		b"00111" when trailingones=2 and totalcoeffs=9 and ctable=2 else
		b"00110" when trailingones=3 and totalcoeffs=9 and ctable=2 else
		b"01001" when trailingones=0 and totalcoeffs=10 and ctable=2 else
		b"01000" when trailingones=1 and totalcoeffs=10 and ctable=2 else
		b"01000" when trailingones=2 and totalcoeffs=10 and ctable=2 else
		b"00111" when trailingones=3 and totalcoeffs=10 and ctable=2 else
		b"01001" when trailingones=0 and totalcoeffs=11 and ctable=2 else
		b"01001" when trailingones=1 and totalcoeffs=11 and ctable=2 else
		b"01000" when trailingones=2 and totalcoeffs=11 and ctable=2 else
		b"01000" when trailingones=3 and totalcoeffs=11 and ctable=2 else
		b"01001" when trailingones=0 and totalcoeffs=12 and ctable=2 else
		b"01001" when trailingones=1 and totalcoeffs=12 and ctable=2 else
		b"01001" when trailingones=2 and totalcoeffs=12 and ctable=2 else
		b"01000" when trailingones=3 and totalcoeffs=12 and ctable=2 else
		b"01010" when trailingones=0 and totalcoeffs=13 and ctable=2 else
		b"01001" when trailingones=1 and totalcoeffs=13 and ctable=2 else
		b"01001" when trailingones=2 and totalcoeffs=13 and ctable=2 else
		b"01001" when trailingones=3 and totalcoeffs=13 and ctable=2 else
		b"01010" when trailingones=0 and totalcoeffs=14 and ctable=2 else
		b"01010" when trailingones=1 and totalcoeffs=14 and ctable=2 else
		b"01010" when trailingones=2 and totalcoeffs=14 and ctable=2 else
		b"01010" when trailingones=3 and totalcoeffs=14 and ctable=2 else
		b"01010" when trailingones=0 and totalcoeffs=15 and ctable=2 else
		b"01010" when trailingones=1 and totalcoeffs=15 and ctable=2 else
		b"01010" when trailingones=2 and totalcoeffs=15 and ctable=2 else
		b"01010" when trailingones=3 and totalcoeffs=15 and ctable=2 else
		b"01010" when trailingones=0 and totalcoeffs=16 and ctable=2 else
		b"01010" when trailingones=1 and totalcoeffs=16 and ctable=2 else
		b"01010" when trailingones=2 and totalcoeffs=16 and ctable=2 else
		b"01010" when trailingones=3 and totalcoeffs=16 and ctable=2 else
		--
		b"00110" when ctable=3 else
		--
		b"00010" when trailingones=0 and totalcoeffs=0 and ctable=4 else
		b"00110" when trailingones=0 and totalcoeffs=1 and ctable=4 else
		b"00001" when trailingones=1 and totalcoeffs=1 and ctable=4 else
		b"00110" when trailingones=0 and totalcoeffs=2 and ctable=4 else
		b"00110" when trailingones=1 and totalcoeffs=2 and ctable=4 else
		b"00011" when trailingones=2 and totalcoeffs=2 and ctable=4 else
		b"00110" when trailingones=0 and totalcoeffs=3 and ctable=4 else
		b"00111" when trailingones=1 and totalcoeffs=3 and ctable=4 else
		b"00111" when trailingones=2 and totalcoeffs=3 and ctable=4 else
		b"00110" when trailingones=3 and totalcoeffs=3 and ctable=4 else
		b"00110" when trailingones=0 and totalcoeffs=4 and ctable=4 else
		b"01000" when trailingones=1 and totalcoeffs=4 and ctable=4 else
		b"01000" when trailingones=2 and totalcoeffs=4 and ctable=4 else
		b"00111"; --  trailingones=3 and totalcoeffs=4 and ctable=4
	--
	-- tables for TotalZeros token
	--
	ztoken <=
		b"001" when totalzeros=0 and totalcoeffs=1 and ztable='0' else
		b"011" when totalzeros=1 and totalcoeffs=1 and ztable='0' else
		b"010" when totalzeros=2 and totalcoeffs=1 and ztable='0' else
		b"011" when totalzeros=3 and totalcoeffs=1 and ztable='0' else
		b"010" when totalzeros=4 and totalcoeffs=1 and ztable='0' else
		b"011" when totalzeros=5 and totalcoeffs=1 and ztable='0' else
		b"010" when totalzeros=6 and totalcoeffs=1 and ztable='0' else
		b"011" when totalzeros=7 and totalcoeffs=1 and ztable='0' else
		b"010" when totalzeros=8 and totalcoeffs=1 and ztable='0' else
		b"011" when totalzeros=9 and totalcoeffs=1 and ztable='0' else
		b"010" when totalzeros=10 and totalcoeffs=1 and ztable='0' else
		b"011" when totalzeros=11 and totalcoeffs=1 and ztable='0' else
		b"010" when totalzeros=12 and totalcoeffs=1 and ztable='0' else
		b"011" when totalzeros=13 and totalcoeffs=1 and ztable='0' else
		b"010" when totalzeros=14 and totalcoeffs=1 and ztable='0' else
		b"001" when totalzeros=15 and totalcoeffs=1 and ztable='0' else
		b"111" when totalzeros=0 and totalcoeffs=2 and ztable='0' else
		b"110" when totalzeros=1 and totalcoeffs=2 and ztable='0' else
		b"101" when totalzeros=2 and totalcoeffs=2 and ztable='0' else
		b"100" when totalzeros=3 and totalcoeffs=2 and ztable='0' else
		b"011" when totalzeros=4 and totalcoeffs=2 and ztable='0' else
		b"101" when totalzeros=5 and totalcoeffs=2 and ztable='0' else
		b"100" when totalzeros=6 and totalcoeffs=2 and ztable='0' else
		b"011" when totalzeros=7 and totalcoeffs=2 and ztable='0' else
		b"010" when totalzeros=8 and totalcoeffs=2 and ztable='0' else
		b"011" when totalzeros=9 and totalcoeffs=2 and ztable='0' else
		b"010" when totalzeros=10 and totalcoeffs=2 and ztable='0' else
		b"011" when totalzeros=11 and totalcoeffs=2 and ztable='0' else
		b"010" when totalzeros=12 and totalcoeffs=2 and ztable='0' else
		b"001" when totalzeros=13 and totalcoeffs=2 and ztable='0' else
		b"000" when totalzeros=14 and totalcoeffs=2 and ztable='0' else
		b"101" when totalzeros=0 and totalcoeffs=3 and ztable='0' else
		b"111" when totalzeros=1 and totalcoeffs=3 and ztable='0' else
		b"110" when totalzeros=2 and totalcoeffs=3 and ztable='0' else
		b"101" when totalzeros=3 and totalcoeffs=3 and ztable='0' else
		b"100" when totalzeros=4 and totalcoeffs=3 and ztable='0' else
		b"011" when totalzeros=5 and totalcoeffs=3 and ztable='0' else
		b"100" when totalzeros=6 and totalcoeffs=3 and ztable='0' else
		b"011" when totalzeros=7 and totalcoeffs=3 and ztable='0' else
		b"010" when totalzeros=8 and totalcoeffs=3 and ztable='0' else
		b"011" when totalzeros=9 and totalcoeffs=3 and ztable='0' else
		b"010" when totalzeros=10 and totalcoeffs=3 and ztable='0' else
		b"001" when totalzeros=11 and totalcoeffs=3 and ztable='0' else
		b"001" when totalzeros=12 and totalcoeffs=3 and ztable='0' else
		b"000" when totalzeros=13 and totalcoeffs=3 and ztable='0' else
		b"011" when totalzeros=0 and totalcoeffs=4 and ztable='0' else
		b"111" when totalzeros=1 and totalcoeffs=4 and ztable='0' else
		b"101" when totalzeros=2 and totalcoeffs=4 and ztable='0' else
		b"100" when totalzeros=3 and totalcoeffs=4 and ztable='0' else
		b"110" when totalzeros=4 and totalcoeffs=4 and ztable='0' else
		b"101" when totalzeros=5 and totalcoeffs=4 and ztable='0' else
		b"100" when totalzeros=6 and totalcoeffs=4 and ztable='0' else
		b"011" when totalzeros=7 and totalcoeffs=4 and ztable='0' else
		b"011" when totalzeros=8 and totalcoeffs=4 and ztable='0' else
		b"010" when totalzeros=9 and totalcoeffs=4 and ztable='0' else
		b"010" when totalzeros=10 and totalcoeffs=4 and ztable='0' else
		b"001" when totalzeros=11 and totalcoeffs=4 and ztable='0' else
		b"000" when totalzeros=12 and totalcoeffs=4 and ztable='0' else
		b"101" when totalzeros=0 and totalcoeffs=5 and ztable='0' else
		b"100" when totalzeros=1 and totalcoeffs=5 and ztable='0' else
		b"011" when totalzeros=2 and totalcoeffs=5 and ztable='0' else
		b"111" when totalzeros=3 and totalcoeffs=5 and ztable='0' else
		b"110" when totalzeros=4 and totalcoeffs=5 and ztable='0' else
		b"101" when totalzeros=5 and totalcoeffs=5 and ztable='0' else
		b"100" when totalzeros=6 and totalcoeffs=5 and ztable='0' else
		b"011" when totalzeros=7 and totalcoeffs=5 and ztable='0' else
		b"010" when totalzeros=8 and totalcoeffs=5 and ztable='0' else
		b"001" when totalzeros=9 and totalcoeffs=5 and ztable='0' else
		b"001" when totalzeros=10 and totalcoeffs=5 and ztable='0' else
		b"000" when totalzeros=11 and totalcoeffs=5 and ztable='0' else
		b"001" when totalzeros=0 and totalcoeffs=6 and ztable='0' else
		b"001" when totalzeros=1 and totalcoeffs=6 and ztable='0' else
		b"111" when totalzeros=2 and totalcoeffs=6 and ztable='0' else
		b"110" when totalzeros=3 and totalcoeffs=6 and ztable='0' else
		b"101" when totalzeros=4 and totalcoeffs=6 and ztable='0' else
		b"100" when totalzeros=5 and totalcoeffs=6 and ztable='0' else
		b"011" when totalzeros=6 and totalcoeffs=6 and ztable='0' else
		b"010" when totalzeros=7 and totalcoeffs=6 and ztable='0' else
		b"001" when totalzeros=8 and totalcoeffs=6 and ztable='0' else
		b"001" when totalzeros=9 and totalcoeffs=6 and ztable='0' else
		b"000" when totalzeros=10 and totalcoeffs=6 and ztable='0' else
		b"001" when totalzeros=0 and totalcoeffs=7 and ztable='0' else
		b"001" when totalzeros=1 and totalcoeffs=7 and ztable='0' else
		b"101" when totalzeros=2 and totalcoeffs=7 and ztable='0' else
		b"100" when totalzeros=3 and totalcoeffs=7 and ztable='0' else
		b"011" when totalzeros=4 and totalcoeffs=7 and ztable='0' else
		b"011" when totalzeros=5 and totalcoeffs=7 and ztable='0' else
		b"010" when totalzeros=6 and totalcoeffs=7 and ztable='0' else
		b"001" when totalzeros=7 and totalcoeffs=7 and ztable='0' else
		b"001" when totalzeros=8 and totalcoeffs=7 and ztable='0' else
		b"000" when totalzeros=9 and totalcoeffs=7 and ztable='0' else
		b"001" when totalzeros=0 and totalcoeffs=8 and ztable='0' else
		b"001" when totalzeros=1 and totalcoeffs=8 and ztable='0' else
		b"001" when totalzeros=2 and totalcoeffs=8 and ztable='0' else
		b"011" when totalzeros=3 and totalcoeffs=8 and ztable='0' else
		b"011" when totalzeros=4 and totalcoeffs=8 and ztable='0' else
		b"010" when totalzeros=5 and totalcoeffs=8 and ztable='0' else
		b"010" when totalzeros=6 and totalcoeffs=8 and ztable='0' else
		b"001" when totalzeros=7 and totalcoeffs=8 and ztable='0' else
		b"000" when totalzeros=8 and totalcoeffs=8 and ztable='0' else
		b"001" when totalzeros=0 and totalcoeffs=9 and ztable='0' else
		b"000" when totalzeros=1 and totalcoeffs=9 and ztable='0' else
		b"001" when totalzeros=2 and totalcoeffs=9 and ztable='0' else
		b"011" when totalzeros=3 and totalcoeffs=9 and ztable='0' else
		b"010" when totalzeros=4 and totalcoeffs=9 and ztable='0' else
		b"001" when totalzeros=5 and totalcoeffs=9 and ztable='0' else
		b"001" when totalzeros=6 and totalcoeffs=9 and ztable='0' else
		b"001" when totalzeros=7 and totalcoeffs=9 and ztable='0' else
		b"001" when totalzeros=0 and totalcoeffs=10 and ztable='0' else
		b"000" when totalzeros=1 and totalcoeffs=10 and ztable='0' else
		b"001" when totalzeros=2 and totalcoeffs=10 and ztable='0' else
		b"011" when totalzeros=3 and totalcoeffs=10 and ztable='0' else
		b"010" when totalzeros=4 and totalcoeffs=10 and ztable='0' else
		b"001" when totalzeros=5 and totalcoeffs=10 and ztable='0' else
		b"001" when totalzeros=6 and totalcoeffs=10 and ztable='0' else
		b"000" when totalzeros=0 and totalcoeffs=11 and ztable='0' else
		b"001" when totalzeros=1 and totalcoeffs=11 and ztable='0' else
		b"001" when totalzeros=2 and totalcoeffs=11 and ztable='0' else
		b"010" when totalzeros=3 and totalcoeffs=11 and ztable='0' else
		b"001" when totalzeros=4 and totalcoeffs=11 and ztable='0' else
		b"011" when totalzeros=5 and totalcoeffs=11 and ztable='0' else
		b"000" when totalzeros=0 and totalcoeffs=12 and ztable='0' else
		b"001" when totalzeros=1 and totalcoeffs=12 and ztable='0' else
		b"001" when totalzeros=2 and totalcoeffs=12 and ztable='0' else
		b"001" when totalzeros=3 and totalcoeffs=12 and ztable='0' else
		b"001" when totalzeros=4 and totalcoeffs=12 and ztable='0' else
		b"000" when totalzeros=0 and totalcoeffs=13 and ztable='0' else
		b"001" when totalzeros=1 and totalcoeffs=13 and ztable='0' else
		b"001" when totalzeros=2 and totalcoeffs=13 and ztable='0' else
		b"001" when totalzeros=3 and totalcoeffs=13 and ztable='0' else
		b"000" when totalzeros=0 and totalcoeffs=14 and ztable='0' else
		b"001" when totalzeros=1 and totalcoeffs=14 and ztable='0' else
		b"001" when totalzeros=2 and totalcoeffs=14 and ztable='0' else
		b"000" when totalzeros=0 and totalcoeffs=15 and ztable='0' else
		b"001" when totalzeros=1 and totalcoeffs=15 and ztable='0' else
		--
		b"001" when totalzeros=0 and totalcoeffs=1 and ztable='1' else
		b"001" when totalzeros=1 and totalcoeffs=1 and ztable='1' else
		b"001" when totalzeros=2 and totalcoeffs=1 and ztable='1' else
		b"000" when totalzeros=3 and totalcoeffs=1 and ztable='1' else
		b"001" when totalzeros=0 and totalcoeffs=2 and ztable='1' else
		b"001" when totalzeros=1 and totalcoeffs=2 and ztable='1' else
		b"000" when totalzeros=2 and totalcoeffs=2 and ztable='1' else
		b"001" when totalzeros=0 and totalcoeffs=3 and ztable='1' else
		b"000"; --  totalzeros=1 and totalcoeffs=3 and ztable='1'
	--
	ztoken_len <=
		b"0001" when totalzeros=0 and totalcoeffs=1 and ztable='0' else
		b"0011" when totalzeros=1 and totalcoeffs=1 and ztable='0' else
		b"0011" when totalzeros=2 and totalcoeffs=1 and ztable='0' else
		b"0100" when totalzeros=3 and totalcoeffs=1 and ztable='0' else
		b"0100" when totalzeros=4 and totalcoeffs=1 and ztable='0' else
		b"0101" when totalzeros=5 and totalcoeffs=1 and ztable='0' else
		b"0101" when totalzeros=6 and totalcoeffs=1 and ztable='0' else
		b"0110" when totalzeros=7 and totalcoeffs=1 and ztable='0' else
		b"0110" when totalzeros=8 and totalcoeffs=1 and ztable='0' else
		b"0111" when totalzeros=9 and totalcoeffs=1 and ztable='0' else
		b"0111" when totalzeros=10 and totalcoeffs=1 and ztable='0' else
		b"1000" when totalzeros=11 and totalcoeffs=1 and ztable='0' else
		b"1000" when totalzeros=12 and totalcoeffs=1 and ztable='0' else
		b"1001" when totalzeros=13 and totalcoeffs=1 and ztable='0' else
		b"1001" when totalzeros=14 and totalcoeffs=1 and ztable='0' else
		b"1001" when totalzeros=15 and totalcoeffs=1 and ztable='0' else
		b"0011" when totalzeros=0 and totalcoeffs=2 and ztable='0' else
		b"0011" when totalzeros=1 and totalcoeffs=2 and ztable='0' else
		b"0011" when totalzeros=2 and totalcoeffs=2 and ztable='0' else
		b"0011" when totalzeros=3 and totalcoeffs=2 and ztable='0' else
		b"0011" when totalzeros=4 and totalcoeffs=2 and ztable='0' else
		b"0100" when totalzeros=5 and totalcoeffs=2 and ztable='0' else
		b"0100" when totalzeros=6 and totalcoeffs=2 and ztable='0' else
		b"0100" when totalzeros=7 and totalcoeffs=2 and ztable='0' else
		b"0100" when totalzeros=8 and totalcoeffs=2 and ztable='0' else
		b"0101" when totalzeros=9 and totalcoeffs=2 and ztable='0' else
		b"0101" when totalzeros=10 and totalcoeffs=2 and ztable='0' else
		b"0110" when totalzeros=11 and totalcoeffs=2 and ztable='0' else
		b"0110" when totalzeros=12 and totalcoeffs=2 and ztable='0' else
		b"0110" when totalzeros=13 and totalcoeffs=2 and ztable='0' else
		b"0110" when totalzeros=14 and totalcoeffs=2 and ztable='0' else
		b"0100" when totalzeros=0 and totalcoeffs=3 and ztable='0' else
		b"0011" when totalzeros=1 and totalcoeffs=3 and ztable='0' else
		b"0011" when totalzeros=2 and totalcoeffs=3 and ztable='0' else
		b"0011" when totalzeros=3 and totalcoeffs=3 and ztable='0' else
		b"0100" when totalzeros=4 and totalcoeffs=3 and ztable='0' else
		b"0100" when totalzeros=5 and totalcoeffs=3 and ztable='0' else
		b"0011" when totalzeros=6 and totalcoeffs=3 and ztable='0' else
		b"0011" when totalzeros=7 and totalcoeffs=3 and ztable='0' else
		b"0100" when totalzeros=8 and totalcoeffs=3 and ztable='0' else
		b"0101" when totalzeros=9 and totalcoeffs=3 and ztable='0' else
		b"0101" when totalzeros=10 and totalcoeffs=3 and ztable='0' else
		b"0110" when totalzeros=11 and totalcoeffs=3 and ztable='0' else
		b"0101" when totalzeros=12 and totalcoeffs=3 and ztable='0' else
		b"0110" when totalzeros=13 and totalcoeffs=3 and ztable='0' else
		b"0101" when totalzeros=0 and totalcoeffs=4 and ztable='0' else
		b"0011" when totalzeros=1 and totalcoeffs=4 and ztable='0' else
		b"0100" when totalzeros=2 and totalcoeffs=4 and ztable='0' else
		b"0100" when totalzeros=3 and totalcoeffs=4 and ztable='0' else
		b"0011" when totalzeros=4 and totalcoeffs=4 and ztable='0' else
		b"0011" when totalzeros=5 and totalcoeffs=4 and ztable='0' else
		b"0011" when totalzeros=6 and totalcoeffs=4 and ztable='0' else
		b"0100" when totalzeros=7 and totalcoeffs=4 and ztable='0' else
		b"0011" when totalzeros=8 and totalcoeffs=4 and ztable='0' else
		b"0100" when totalzeros=9 and totalcoeffs=4 and ztable='0' else
		b"0101" when totalzeros=10 and totalcoeffs=4 and ztable='0' else
		b"0101" when totalzeros=11 and totalcoeffs=4 and ztable='0' else
		b"0101" when totalzeros=12 and totalcoeffs=4 and ztable='0' else
		b"0100" when totalzeros=0 and totalcoeffs=5 and ztable='0' else
		b"0100" when totalzeros=1 and totalcoeffs=5 and ztable='0' else
		b"0100" when totalzeros=2 and totalcoeffs=5 and ztable='0' else
		b"0011" when totalzeros=3 and totalcoeffs=5 and ztable='0' else
		b"0011" when totalzeros=4 and totalcoeffs=5 and ztable='0' else
		b"0011" when totalzeros=5 and totalcoeffs=5 and ztable='0' else
		b"0011" when totalzeros=6 and totalcoeffs=5 and ztable='0' else
		b"0011" when totalzeros=7 and totalcoeffs=5 and ztable='0' else
		b"0100" when totalzeros=8 and totalcoeffs=5 and ztable='0' else
		b"0101" when totalzeros=9 and totalcoeffs=5 and ztable='0' else
		b"0100" when totalzeros=10 and totalcoeffs=5 and ztable='0' else
		b"0101" when totalzeros=11 and totalcoeffs=5 and ztable='0' else
		b"0110" when totalzeros=0 and totalcoeffs=6 and ztable='0' else
		b"0101" when totalzeros=1 and totalcoeffs=6 and ztable='0' else
		b"0011" when totalzeros=2 and totalcoeffs=6 and ztable='0' else
		b"0011" when totalzeros=3 and totalcoeffs=6 and ztable='0' else
		b"0011" when totalzeros=4 and totalcoeffs=6 and ztable='0' else
		b"0011" when totalzeros=5 and totalcoeffs=6 and ztable='0' else
		b"0011" when totalzeros=6 and totalcoeffs=6 and ztable='0' else
		b"0011" when totalzeros=7 and totalcoeffs=6 and ztable='0' else
		b"0100" when totalzeros=8 and totalcoeffs=6 and ztable='0' else
		b"0011" when totalzeros=9 and totalcoeffs=6 and ztable='0' else
		b"0110" when totalzeros=10 and totalcoeffs=6 and ztable='0' else
		b"0110" when totalzeros=0 and totalcoeffs=7 and ztable='0' else
		b"0101" when totalzeros=1 and totalcoeffs=7 and ztable='0' else
		b"0011" when totalzeros=2 and totalcoeffs=7 and ztable='0' else
		b"0011" when totalzeros=3 and totalcoeffs=7 and ztable='0' else
		b"0011" when totalzeros=4 and totalcoeffs=7 and ztable='0' else
		b"0010" when totalzeros=5 and totalcoeffs=7 and ztable='0' else
		b"0011" when totalzeros=6 and totalcoeffs=7 and ztable='0' else
		b"0100" when totalzeros=7 and totalcoeffs=7 and ztable='0' else
		b"0011" when totalzeros=8 and totalcoeffs=7 and ztable='0' else
		b"0110" when totalzeros=9 and totalcoeffs=7 and ztable='0' else
		b"0110" when totalzeros=0 and totalcoeffs=8 and ztable='0' else
		b"0100" when totalzeros=1 and totalcoeffs=8 and ztable='0' else
		b"0101" when totalzeros=2 and totalcoeffs=8 and ztable='0' else
		b"0011" when totalzeros=3 and totalcoeffs=8 and ztable='0' else
		b"0010" when totalzeros=4 and totalcoeffs=8 and ztable='0' else
		b"0010" when totalzeros=5 and totalcoeffs=8 and ztable='0' else
		b"0011" when totalzeros=6 and totalcoeffs=8 and ztable='0' else
		b"0011" when totalzeros=7 and totalcoeffs=8 and ztable='0' else
		b"0110" when totalzeros=8 and totalcoeffs=8 and ztable='0' else
		b"0110" when totalzeros=0 and totalcoeffs=9 and ztable='0' else
		b"0110" when totalzeros=1 and totalcoeffs=9 and ztable='0' else
		b"0100" when totalzeros=2 and totalcoeffs=9 and ztable='0' else
		b"0010" when totalzeros=3 and totalcoeffs=9 and ztable='0' else
		b"0010" when totalzeros=4 and totalcoeffs=9 and ztable='0' else
		b"0011" when totalzeros=5 and totalcoeffs=9 and ztable='0' else
		b"0010" when totalzeros=6 and totalcoeffs=9 and ztable='0' else
		b"0101" when totalzeros=7 and totalcoeffs=9 and ztable='0' else
		b"0101" when totalzeros=0 and totalcoeffs=10 and ztable='0' else
		b"0101" when totalzeros=1 and totalcoeffs=10 and ztable='0' else
		b"0011" when totalzeros=2 and totalcoeffs=10 and ztable='0' else
		b"0010" when totalzeros=3 and totalcoeffs=10 and ztable='0' else
		b"0010" when totalzeros=4 and totalcoeffs=10 and ztable='0' else
		b"0010" when totalzeros=5 and totalcoeffs=10 and ztable='0' else
		b"0100" when totalzeros=6 and totalcoeffs=10 and ztable='0' else
		b"0100" when totalzeros=0 and totalcoeffs=11 and ztable='0' else
		b"0100" when totalzeros=1 and totalcoeffs=11 and ztable='0' else
		b"0011" when totalzeros=2 and totalcoeffs=11 and ztable='0' else
		b"0011" when totalzeros=3 and totalcoeffs=11 and ztable='0' else
		b"0001" when totalzeros=4 and totalcoeffs=11 and ztable='0' else
		b"0011" when totalzeros=5 and totalcoeffs=11 and ztable='0' else
		b"0100" when totalzeros=0 and totalcoeffs=12 and ztable='0' else
		b"0100" when totalzeros=1 and totalcoeffs=12 and ztable='0' else
		b"0010" when totalzeros=2 and totalcoeffs=12 and ztable='0' else
		b"0001" when totalzeros=3 and totalcoeffs=12 and ztable='0' else
		b"0011" when totalzeros=4 and totalcoeffs=12 and ztable='0' else
		b"0011" when totalzeros=0 and totalcoeffs=13 and ztable='0' else
		b"0011" when totalzeros=1 and totalcoeffs=13 and ztable='0' else
		b"0001" when totalzeros=2 and totalcoeffs=13 and ztable='0' else
		b"0010" when totalzeros=3 and totalcoeffs=13 and ztable='0' else
		b"0010" when totalzeros=0 and totalcoeffs=14 and ztable='0' else
		b"0010" when totalzeros=1 and totalcoeffs=14 and ztable='0' else
		b"0001" when totalzeros=2 and totalcoeffs=14 and ztable='0' else
		b"0001" when totalzeros=0 and totalcoeffs=15 and ztable='0' else
		b"0001" when totalzeros=1 and totalcoeffs=15 and ztable='0' else
	--
		b"0001" when totalzeros=0 and totalcoeffs=1 and ztable='1' else
		b"0010" when totalzeros=1 and totalcoeffs=1 and ztable='1' else
		b"0011" when totalzeros=2 and totalcoeffs=1 and ztable='1' else
		b"0011" when totalzeros=3 and totalcoeffs=1 and ztable='1' else
		b"0001" when totalzeros=0 and totalcoeffs=2 and ztable='1' else
		b"0010" when totalzeros=1 and totalcoeffs=2 and ztable='1' else
		b"0010" when totalzeros=2 and totalcoeffs=2 and ztable='1' else
		b"0001" when totalzeros=0 and totalcoeffs=3 and ztable='1' else
		b"0001"; --  totalzeros=1 and totalcoeffs=3 and ztable='1'
	--
	-- tables for run_before, up to 6
	rbtoken <=
		b"111" when runb=0 else
		b"000" when runb=1 and rbzerosleft=1 else
		b"001" when runb=1 and rbzerosleft=2 else
		b"010" when runb=1 and rbzerosleft=3 else
		b"010" when runb=1 and rbzerosleft=4 else
		b"010" when runb=1 and rbzerosleft=5 else
		b"000" when runb=1 and rbzerosleft=6 else
		b"110" when runb=1 else
		b"000" when runb=2 and rbzerosleft=2 else
		b"001" when runb=2 and rbzerosleft=3 else
		b"001" when runb=2 and rbzerosleft=4 else
		b"011" when runb=2 and rbzerosleft=5 else
		b"001" when runb=2 and rbzerosleft=6 else
		b"101" when runb=2 else
		b"000" when runb=3 and rbzerosleft=3 else
		b"001" when runb=3 and rbzerosleft=4 else
		b"010" when runb=3 and rbzerosleft=5 else
		b"011" when runb=3 and rbzerosleft=6 else
		b"100" when runb=3 else
		b"000" when runb=4 and rbzerosleft=4 else
		b"001" when runb=4 and rbzerosleft=5 else
		b"010" when runb=4 and rbzerosleft=6 else
		b"011" when runb=4 else
		b"000" when runb=5 and rbzerosleft=5 else
		b"101" when runb=5 and rbzerosleft=6 else
		b"010" when runb=5 else
		b"100" when runb=6 and rbzerosleft=6 else
		b"001"; --runb=6
	--
	READY <= not eenable;
	NOUT <= etotalcoeffs;
	--
process(CLK2)
begin
	if rising_edge(CLK2) then
		--reading subprocess
		--principle variables start 'e' so are separate pipeline stage from output
		--t1sign is used by output before overwritten here; likewise arrays
		if ENABLE='1' then
			eenable <= '1';
			emaxcoeffs <= emaxcoeffs + 1;	--this is a coefficient
			es <= SIN;
			if VIN /= 0 then
				etotalcoeffs <= etotalcoeffs + 1;	--total nz coefficients
				ecnz <= '1';						--we've seen a non-zero
				if VIN = 1 or VIN = x"FFF" then		-- 1 or -1
					if ecgt1 = '0' and etrailingones /= 3 then
						etrailingones <= etrailingones + 1;
						et1signs <= et1signs(1 downto 0) & VIN(11);	--encode sign
					end if;
				else
					ecgt1 <= '1';		--we've seen a greater-than-1
				end if;
				--put coeffs into array; put runs into array
				--coeff is coded as sign & abscoeff
				if VIN(11)='1' then
					coeffarray(conv_integer(eparity&eindex)) <= '1'&(b"00000000000"-VIN(10 downto 0));
				else
					coeffarray(conv_integer(eparity&eindex)) <= VIN;
				end if;
				runbarray(conv_integer(eparity&eindex)) <= erun;
				erun <= x"0";
				eindex <= eindex+1;
			elsif ecnz='1' then	--VIN=0 and ecnz
				etotalzeros <= etotalzeros + 1;		--totalzeros after first nz coeff
				erun <= erun + 1;
			end if;
			--select table for coeff_token (assume 4x4)
			if NIN < 2 then
				etable <= CTABLE0(1 downto 0);
			elsif NIN < 4 then
				etable <= CTABLE1(1 downto 0);
			elsif NIN < 8 then
				etable <= CTABLE2(1 downto 0);
			else
				etable <= CTABLE3(1 downto 0);
			end if;
		else -- ENABLE=0
			if hvalid='0' and eenable='1' then
				--transfer to holding stage
				hmaxcoeffs <= emaxcoeffs;
				htotalcoeffs <= etotalcoeffs;
				htotalzeros <= etotalzeros;
				htrailingones <= etrailingones;
				htable <= etable;
				hs <= es;
				t1signs <= et1signs;
				hparity <= eparity;
				hvalidi <= '1';
				assert emaxcoeffs=16 or emaxcoeffs=15 or emaxcoeffs=4 
					report "H264CAVLC: maxcoeffs is not a valid value" severity ERROR;
				--
				eenable <= '0';
				emaxcoeffs <= b"00000";
				etotalcoeffs <= b"00000";
				etotalzeros <= b"00000";
				etrailingones <= b"00";
				erun <= x"0";
				eindex <= x"0";
				ecnz <= '0';
				ecgt1 <= '0';
				eparity <= not eparity;
			end if;
		end if;
		if hvalid='1' and state=STATE_COEFFS and cindex > totalcoeffs(4 downto 1) and parity=hparity then
			--ok to clear holding register
			hvalidi <= '0';
		end if;
		hvalid <= hvalidi;	--delay 1 cycle to overcome CLK/CLK2 sync problems
	end if;
end process;
--
process(CLK)
	variable coeff : std_logic_vector(11 downto 0);
	variable tmpindex : std_logic_vector(4 downto 0);
begin
	if rising_edge(CLK) then
		-- maintain state
		if state = STATE_IDLE then
			VALID <= '0';
		end if;
		if (state=STATE_IDLE or (state=STATE_RUNBF and rbstate = '0')) and hvalid='1' then	--done read, start processing
			maxcoeffs <= hmaxcoeffs;
			totalcoeffs <= htotalcoeffs;
			totalzeros <= htotalzeros;
			trailingones <= htrailingones;
			parity <= hparity;
			if hmaxcoeffs=4 then
				ctable <= CTABLE4;	--special table for ChromaDC
				ztable <= '1';		--ditto
			else
				ctable <= '0'&htable;	--normal tables
				ztable <= '0';		--ditto
			end if;
			state <= STATE_CTOKEN;
			cindex <= b"00"&htrailingones;
			if htotalcoeffs>1 then
				rbstate <= '1';	--runbefore processing starts
			end if;
			rbindex <= x"2";
			tmpindex := hparity&x"1";
			runb <= runbarray(conv_integer(tmpindex));
			rbzerosleft <= htotalzeros;
			rbvl <= b"00000";
			rbve <= (others => '0');
		end if;
		if state = STATE_CTOKEN then
			if trailingones /= 0 then
				state <= STATE_T1SIGN;
			else
				state <= STATE_COEFFS;	--skip T1SIGN
			end if;
		end if;
		if state = STATE_T1SIGN then 
			state <= STATE_COEFFS;
		end if;
		if state = STATE_COEFFS and (cindex>=totalcoeffs or cindex=0) then
			if totalcoeffs/=maxcoeffs and totalcoeffs/=0 then
				state <= STATE_TZEROS;
			else
				state <= STATE_RUNBF;	--skip TZEROS
			end if;
		end if;
		if state = STATE_TZEROS then
			state <= STATE_RUNBF;
		end if;
		if state = STATE_RUNBF and rbstate = '1' then		--wait
			VALID <= '0';
		elsif state = STATE_RUNBF and rbstate = '0' then		--all done; reset and get ready to go again
			if hvalid='0' then
				state <= STATE_IDLE;
			end if;
			if rbvl /= 0 and totalzeros /= 0 then
				VALID <= '1';
				VE <= rbve;		--results of runbefore subprocessor
				VL <= rbvl;
			else
				VALID <= '0';
			end if;
		end if;
		--
		--
		--runbefore subprocess
		--uses rbzerosleft, runarray with rbstate,rbindex,runb
		--(runb=runarray(0) when it starts)(no effect if rbzerosleft=0)
		if rbstate = '1' then
			if runb <= 7 then	--normal processing
				runb <= runbarray(conv_integer(parity&rbindex));
				rbindex <= rbindex+1;
				if rbindex=totalcoeffs or rbzerosleft<=runb then
					rbstate <= '0';	--done
				end if;
				--runb is currently runbarray(rbindex-1), since rbindex not yet loaded
				if rbzerosleft + runb <= 2 then		--1 bit code
					rbve <= rbve(23 downto 0) & (not runb(0));
					rbvl <= rbvl + 1;
				elsif rbzerosleft + runb <= 6 then	--2 bit code
					rbve <= rbve(22 downto 0) & rbtoken(1 downto 0);
					rbvl <= rbvl + 2;
				elsif runb <= 6 then				--3 bit code
					rbve <= rbve(21 downto 0) & rbtoken(2 downto 0);
					rbvl <= rbvl + 3;
				else	--runb=7					--4bit code
					rbve <= rbve(20 downto 0) & b"0001";
					rbvl <= rbvl + 4;
				end if;
				rbzerosleft <= rbzerosleft-runb;
			else		--runb > 7, emit a zero and reduce counters by 1
				rbve <= rbve(23 downto 0) & b"0";
				rbvl <= rbvl + 1;
				rbzerosleft <= rbzerosleft-1;
				runb <= runb-1;
			end if;		
		end if;
		assert rbvl <= 25 report "rbve overflow";
		--
		-- output stuff...
		-- CTOKEN
		if state = STATE_CTOKEN then
			--output coeff_token based on (totalcoeffs,trailingones)
			VE <= x"0000" & b"000" & coeff_token;	--from tables above
			VL <= ctoken_len;
			VALID <= '1';
			VS <= hs;
			--setup for COEFFS (do it here 'cos T1SIGN may be skipped)
			--start at cindex=trailingones since we don't need to encode those
			coeff := coeffarray(conv_integer(parity&b"00"&trailingones));
			cindex <= (b"00"&trailingones) + 1;
			signcoeff <= coeff(11);
			abscoeff <= coeff(10 downto 0);
			if trailingones=3 then
				abscoeffa <= coeff(10 downto 0) - 1;	--normal case
			else
				abscoeffa <= coeff(10 downto 0) - 2;	--special case for t1s<3
			end if;
			if totalcoeffs>10 and trailingones/=3 then
				suffixlen <= b"001";	--start at 1
			else
				suffixlen <= b"000";	--start at zero (normal)
			end if;
		end if;
		-- T1SIGN
		if state = STATE_T1SIGN then
			assert trailingones /= 0 severity ERROR;
			VALID <= '1';
			VE <= x"00000" & b"00" & t1signs;
			VL <= b"000" & trailingones;
		end if;
		-- COEFFS
		-- uses suffixlen, lesstwo, coeffarray, abscoeff, signcoeff, cindex
		if state = STATE_COEFFS then
			--uses abscoeff, signcoeff loaded from array last time
			--if "lessone" then already applied to abscoeff
			--and +ve has 1 subtracted from it
			if suffixlen = 0 then
				--three sub-cases depending on size of abscoeff
				if abscoeffa < 7 then
					--normal, just levelprefix which is unary encoded
					VE <= '0'&x"000001";
					VL <= (abscoeffa(3 downto 0)&signcoeff) + 1;
				elsif abscoeffa < 15 then		--7..14
					--use level 14 with 4bit suffix
					--subtract 7 and use 3 bits of abscoeffa (same as add 1)
					VE <= '0'&x"00001" & (abscoeffa(2 downto 0)+1) & signcoeff;
					VL <= b"10011";	--14+1+4 = 19 bits
				else
					--use level 15 with 12bit suffix
					VE <= '0'&x"001" & (abscoeffa-15) & signcoeff;
					VL <= b"11100";	--15+1+12 = 28 bits
				end if;
				if abscoeff > 3 then
					suffixlen <= b"010";	--double increment
				else
					suffixlen <= b"001";	--always increment
				end if;
			else --suffixlen > 0: 1..6
				if (suffixlen=1 and abscoeffa < 15) then
					VE <= '0'&x"00000" & b"001" & signcoeff;
					VL <= abscoeffa(4 downto 0) + 2;
				elsif (suffixlen=2 and abscoeffa < 30) then
					VE <= '0'&x"00000" & b"01" & abscoeffa(0) & signcoeff;
					VL <= abscoeffa(5 downto 1) + 3;
				elsif (suffixlen=3 and abscoeffa < 60) then
					VE <= '0'&x"00000" & b"1" & abscoeffa(1 downto 0) & signcoeff;
					VL <= abscoeffa(6 downto 2) + 4;
				elsif (suffixlen=4 and abscoeffa < 120) then
					VE <= '0'&x"00001" & abscoeffa(2 downto 0) & signcoeff;
					VL <= abscoeffa(7 downto 3) + 5;
				elsif (suffixlen=5 and abscoeffa < 240) then
					VE <= '0'&x"0000" & b"001" & abscoeffa(3 downto 0) & signcoeff;
					VL <= abscoeffa(8 downto 4) + 6;
				elsif (suffixlen=6 and abscoeffa < 480) then
					VE <= '0'&x"0000" & b"01" & abscoeffa(4 downto 0) & signcoeff;
					VL <= abscoeffa(9 downto 5) + 7;
				elsif suffixlen=1 then			--use level 15 with 12bit suffix, VLC1
					VE <= '0'&x"001" & (abscoeffa-15) & signcoeff;
					VL <= b"11100";	--15+1+12 = 28 bits
				elsif suffixlen=2 then			--use level 15 with 12bit suffix, VLC2
					VE <= '0'&x"001" & (abscoeffa-30) & signcoeff;
					VL <= b"11100";	--15+1+12 = 28 bits
				elsif suffixlen=3 then			--use level 15 with 12bit suffix, VLC3
					VE <= '0'&x"001" & (abscoeffa-60) & signcoeff;
					VL <= b"11100";	--15+1+12 = 28 bits
				elsif suffixlen=4 then			--use level 15 with 12bit suffix, VLC4
					VE <= '0'&x"001" & (abscoeffa-120) & signcoeff;
					VL <= b"11100";	--15+1+12 = 28 bits
				elsif suffixlen=5 then			--use level 15 with 12bit suffix, VLC5
					VE <= '0'&x"001" & (abscoeffa-240) & signcoeff;
					VL <= b"11100";	--15+1+12 = 28 bits
				else			--use level 15 with 12bit suffix, VLC6
					VE <= '0'&x"001" & (abscoeffa-480) & signcoeff;
					VL <= b"11100";	--15+1+12 = 28 bits
				end if;
				if (suffixlen=1 and abscoeff > 3) or
				   (suffixlen=2 and abscoeff > 6) or
				   (suffixlen=3 and abscoeff > 12) or
				   (suffixlen=4 and abscoeff > 24) or
				   (suffixlen=5 and abscoeff > 48) then
					suffixlen <= suffixlen + 1;
				end if;
			end if;
			if cindex<=totalcoeffs and totalcoeffs /= 0 then
				VALID <= '1';
			else
				VALID <= '0';
			end if;
			--next coeff
			coeff := coeffarray(conv_integer(parity&cindex));
			signcoeff <= coeff(11);
			abscoeff <= coeff(10 downto 0);
			abscoeffa <= coeff(10 downto 0) - 1;
			cindex <= cindex+1;
		end if;
		-- TZEROS
		if state = STATE_TZEROS then
			assert totalcoeffs/=maxcoeffs and totalcoeffs/=0 severity ERROR;
			VALID <= '1';
			VE <= x"00000" & b"00" & ztoken;
			VL <= b"0" & ztoken_len;
		end if;
		--
	end if;
end process;
	--
end hw;

--#cavlc



--#coretransform


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

--#coretransform


--#dctransform


entity design4 is
	generic (	
		TOGETHER : integer := 0				--1 if output kept together as one block
	);
	port (
		CLK2 : in std_logic;				--fast clock
		RESET : in std_logic;				--reset when 1
		READYI : out std_logic := '0';		--set when ready for ENABLE
		ENABLE : in std_logic;				--values input only when this is 1
		XXIN : in std_logic_vector(15 downto 0);	--input data values (reverse order)
		VALID : out std_logic := '0';				--values output only when this is 1
		YYOUT : out std_logic_vector(15 downto 0);	--output values (reverse order)
		READYO : in std_logic := '0'		--set when ready for ENABLE
	);
end design4;

architecture hw of design4 is
	--
	signal xxii : std_logic_vector(15 downto 0) := (others => '0');
	signal enablei : std_logic := '0';
	signal xx00 : std_logic_vector(15 downto 0) := (others => '0');
	signal xx01 : std_logic_vector(15 downto 0) := (others => '0');
	signal xx10 : std_logic_vector(15 downto 0) := (others => '0');
	signal xx11 : std_logic_vector(15 downto 0) := (others => '0');
	signal ixx : std_logic_vector(1 downto 0) := b"00";
	signal iout : std_logic := '0';
	--
begin
	READYI <= not iout;
	--
process(CLK2)
begin
	if rising_edge(CLK2) then
		if RESET='1' then
			ixx <= b"00";
			iout <= '0';
		end if;
		enablei <= ENABLE;
		xxii <= XXIN;
		if enablei='1' and RESET='0' then	--input in raster scan order
			if ixx=0 then
				xx00 <= xxii;
			elsif ixx=1 then
				xx00 <= xx00 + xxii;	--compute 2nd stage
				xx01 <= xx00 - xxii;
			elsif ixx=2 then
				xx10 <= xxii;
			else
				xx10 <= xx10 + xxii;	--compute 2nd stage
				xx11 <= xx10 - xxii;
				iout <= '1';
			end if;
			ixx <= ixx+1;
		end if;
		if iout='1' and (READYO='1' or (TOGETHER=1 and ixx/=0)) and RESET='0' then
			if ixx=0 then
				YYOUT <= xx00 + xx10;	--out in raster scan order
			elsif ixx=1 then
				YYOUT <= xx01 + xx11;
			elsif ixx=2 then
				YYOUT <= xx00 - xx10;
			else
				YYOUT <= xx01 - xx11;
				iout <= '0';
			end if;
			ixx <= ixx+1;
			VALID <= '1';
		else
			VALID <= '0';
		end if;
	end if;
end process;
	--
end hw; --of h264dctransform



--#dctransform



--#dequantise



entity design4 is
	generic (
		LASTADVANCE : integer := 1
	);
	port (
		CLK : in std_logic;					--pixel clock
		ENABLE : in std_logic;				--values transfered only when this is 1
		QP : in std_logic_vector(5 downto 0);	--0..51 as specified in standard
		ZIN : in std_logic_vector(15 downto 0);
		DCCI : in std_logic;					--2x2 DC chroma in
		LAST : out std_logic := '0';			--set when last coeff about to be input
		WOUT : out std_logic_vector(15 downto 0) := (others=>'0');
		DCCO : out std_logic := '0';			--2x2 DC chroma out
		VALID : out std_logic := '0'			-- enable delayed to same as YOUT timing
	);
end design4;

architecture hw of design4 is
	--
	signal zig : std_logic_vector(3 downto 0) := x"F";
	signal qmf : std_logic_vector(5 downto 0) := (others=>'0');
	signal qmfA : std_logic_vector(4 downto 0) := (others=>'0');
	signal qmfB : std_logic_vector(4 downto 0) := (others=>'0');
	signal qmfC : std_logic_vector(4 downto 0) := (others=>'0');
	signal enab1 : std_logic := '0';
	signal enab2 : std_logic := '0';
	signal dcc1 : std_logic := '0';
	signal dcc2 : std_logic := '0';
	signal z1 : std_logic_vector(15 downto 0) := (others=>'0');
	signal w2 : std_logic_vector(22 downto 0) := (others=>'0');
	--
begin
	--quantisation multiplier factors as per std
	--we need to multiply by qmf and shift by QP/6
	qmfA <=
		CONV_STD_LOGIC_VECTOR(10,5) when ('0'&QP)=0 or ('0'&QP)=6 or ('0'&QP)=12 or ('0'&QP)=18 or ('0'&QP)=24 or ('0'&QP)=30 or ('0'&QP)=36 or ('0'&QP)=42 or ('0'&QP)=48 else
		CONV_STD_LOGIC_VECTOR(11,5) when ('0'&QP)=1 or ('0'&QP)=7 or ('0'&QP)=13 or ('0'&QP)=19 or ('0'&QP)=25 or ('0'&QP)=31 or ('0'&QP)=37 or ('0'&QP)=43 or ('0'&QP)=49 else
		CONV_STD_LOGIC_VECTOR(13,5) when ('0'&QP)=2 or ('0'&QP)=8 or ('0'&QP)=14 or ('0'&QP)=20 or ('0'&QP)=26 or ('0'&QP)=32 or ('0'&QP)=38 or ('0'&QP)=44 or ('0'&QP)=50 else
		CONV_STD_LOGIC_VECTOR(14,5) when ('0'&QP)=3 or ('0'&QP)=9 or ('0'&QP)=15 or ('0'&QP)=21 or ('0'&QP)=27 or ('0'&QP)=33 or ('0'&QP)=39 or ('0'&QP)=45 or ('0'&QP)=51 else
		CONV_STD_LOGIC_VECTOR(16,5) when ('0'&QP)=4 or ('0'&QP)=10 or ('0'&QP)=16 or ('0'&QP)=22 or ('0'&QP)=28 or ('0'&QP)=34 or ('0'&QP)=40 or ('0'&QP)=46 else
		CONV_STD_LOGIC_VECTOR(18,5);
	qmfB <=
		CONV_STD_LOGIC_VECTOR(16,5) when ('0'&QP)=0 or ('0'&QP)=6 or ('0'&QP)=12 or ('0'&QP)=18 or ('0'&QP)=24 or ('0'&QP)=30 or ('0'&QP)=36 or ('0'&QP)=42 or ('0'&QP)=48 else
		CONV_STD_LOGIC_VECTOR(18,5) when ('0'&QP)=1 or ('0'&QP)=7 or ('0'&QP)=13 or ('0'&QP)=19 or ('0'&QP)=25 or ('0'&QP)=31 or ('0'&QP)=37 or ('0'&QP)=43 or ('0'&QP)=49 else
		CONV_STD_LOGIC_VECTOR(20,5) when ('0'&QP)=2 or ('0'&QP)=8 or ('0'&QP)=14 or ('0'&QP)=20 or ('0'&QP)=26 or ('0'&QP)=32 or ('0'&QP)=38 or ('0'&QP)=44 or ('0'&QP)=50 else
		CONV_STD_LOGIC_VECTOR(23,5) when ('0'&QP)=3 or ('0'&QP)=9 or ('0'&QP)=15 or ('0'&QP)=21 or ('0'&QP)=27 or ('0'&QP)=33 or ('0'&QP)=39 or ('0'&QP)=45 or ('0'&QP)=51 else
		CONV_STD_LOGIC_VECTOR(25,5) when ('0'&QP)=4 or ('0'&QP)=10 or ('0'&QP)=16 or ('0'&QP)=22 or ('0'&QP)=28 or ('0'&QP)=34 or ('0'&QP)=40 or ('0'&QP)=46 else
		CONV_STD_LOGIC_VECTOR(29,5);
	qmfC <=
		CONV_STD_LOGIC_VECTOR(13,5) when ('0'&QP)=0 or ('0'&QP)=6 or ('0'&QP)=12 or ('0'&QP)=18 or ('0'&QP)=24 or ('0'&QP)=30 or ('0'&QP)=36 or ('0'&QP)=42 or ('0'&QP)=48 else
		CONV_STD_LOGIC_VECTOR(14,5) when ('0'&QP)=1 or ('0'&QP)=7 or ('0'&QP)=13 or ('0'&QP)=19 or ('0'&QP)=25 or ('0'&QP)=31 or ('0'&QP)=37 or ('0'&QP)=43 or ('0'&QP)=49 else
		CONV_STD_LOGIC_VECTOR(16,5) when ('0'&QP)=2 or ('0'&QP)=8 or ('0'&QP)=14 or ('0'&QP)=20 or ('0'&QP)=26 or ('0'&QP)=32 or ('0'&QP)=38 or ('0'&QP)=44 or ('0'&QP)=50 else
		CONV_STD_LOGIC_VECTOR(18,5) when ('0'&QP)=3 or ('0'&QP)=9 or ('0'&QP)=15 or ('0'&QP)=21 or ('0'&QP)=27 or ('0'&QP)=33 or ('0'&QP)=39 or ('0'&QP)=45 or ('0'&QP)=51 else
		CONV_STD_LOGIC_VECTOR(20,5) when ('0'&QP)=4 or ('0'&QP)=10 or ('0'&QP)=16 or ('0'&QP)=22 or ('0'&QP)=28 or ('0'&QP)=34 or ('0'&QP)=40 or ('0'&QP)=46 else
		CONV_STD_LOGIC_VECTOR(23,5);
	--
process(CLK)
begin
	if rising_edge(CLK) then
		if ENABLE='0' or DCCI='1' then
			zig <= x"F";
		else
			zig <= zig - 1;
		end if;
		--
		if zig=LASTADVANCE then
			LAST <= '1';
		else
			LAST <= '0';
		end if;
		--
		enab1 <= ENABLE;
		enab2 <= enab1;
		VALID <= enab2;
		dcc1 <= DCCI;
		dcc2 <= dcc1;
		DCCO <= dcc2;
		--
		if ENABLE='1' then
			if DCCI='1' then
				--positions 0,0 use table A; x1
				qmf <= '0'&qmfA;
			elsif zig=0 or zig=3 or zig=5 or zig=11 or DCCI='1' then
				--positions 0,0; 0,2; 2,0; 2,2 use table A; x2
				qmf <= qmfA&'0';
			elsif zig=4 or zig=10 or zig=12 or zig=15 then
				--positions 1,1; 1,3; 3,1; 3,3 need table B; x2
				qmf <= qmfB&'0';
			else
				--other positions: table C; x2
				qmf <= qmfC&'0';
			end if;
			z1 <= ZIN;	--data ready for scaling
		end if;
		if enab1='1' then
			w2 <= z1 * ('0'&qmf);		-- quantise
		end if;
		if enab2='1' then
			--here apply ">>1" to undo the x2 above, unless DCC where ">>1" needed
			--we don't clip because the stream is guarranteed to fit in 16bits
			--bit(0) is forced to zero in non-DC cases to meet standard
			if ('0'&QP) < 6 then
				WOUT <= w2(16 downto 1);
			elsif ('0'&QP) < 12 then
				WOUT <= w2(15 downto 1)&(w2(0) and dcc2);
			elsif ('0'&QP) < 18 then
				WOUT <= w2(14 downto 1)&(w2(0) and dcc2)&b"0";
			elsif ('0'&QP) < 24 then
				WOUT <= w2(13 downto 1)&(w2(0) and dcc2)&b"00";
			elsif ('0'&QP) < 30 then
				WOUT <= w2(12 downto 1)&(w2(0) and dcc2)&b"000";
			elsif ('0'&QP) < 36 then
				WOUT <= w2(11 downto 1)&(w2(0) and dcc2)&b"0000";
			elsif ('0'&QP) < 42 then
				WOUT <= w2(10 downto 1)&(w2(0) and dcc2)&b"00000";
			else
				WOUT <= w2(9 downto 1)&(w2(0) and dcc2)&b"000000";
			end if;
		end if;
	end if;
end process;
	--
end hw;

--#dequantise


--#header

entity design4 is
	port (
		CLK : in std_logic;					--clock
		--slice:
		NEWSLICE : in std_logic;			--reset: this is the first in a slice
		LASTSLICE : in std_logic := '1';	--this is last slice in frame
		SINTRA : in std_logic;				--slice I flag
		--macroblock:
		MINTRA : in std_logic;				--macroblock I flag
		LSTROBE : in std_logic;				--luma data here (16 of these)
		CSTROBE : in std_logic;				--chroma data (first latches CMODE)
		QP : in std_logic_vector(5 downto 0);	--0..51 as specified in standard	
		--for intra:
		PMODE : in std_logic;				--luma prev_intra4x4_pred_mode_flag
		RMODE : in std_logic_vector(2 downto 0);	--luma rem_intra4x4_pred_mode_flag
		CMODE : in std_logic_vector(1 downto 0);	--intra_chroma_pred_mode
		--for inter:
		PTYPE : in std_logic_vector(1 downto 0);	--0=P16x16,1=P16x8,2=P8x16,3=subtypes
		PSUBTYPE : in std_logic_vector(1 downto 0) := b"00";	--only if PTYPE=b"11"
		MVDX : in std_logic_vector(11 downto 0);	--signed MVD X (qtr pixel)
		MVDY : in std_logic_vector(11 downto 0);	--signed MVD Y (qtr pixel)
		--out:
		VE : out std_logic_vector(19 downto 0) := (others=>'0');
		VL : out std_logic_vector(4 downto 0) := (others=>'0');
		VALID : out std_logic := '0'	-- VE/VL valid
	);
end design4;
	
architecture hw of design4 is
	--
	signal slicehead1 : std_logic := '0';	-- if we need to emit slice header, part1
	signal slicehead2 : std_logic := '0';	-- if we need to emit slice header, part2
	signal mbhead : std_logic := '0';		-- if we need to emit mb header
	signal idrtwice : std_logic := '0';		-- if 2 IDRs with no P's in middle
	signal lbuf : std_logic_vector(15 downto 0) := (others=>'0');	--accumulator for PMODE/RMODE
	signal lbufc : std_logic_vector(4 downto 0) := (others=>'0');	--count for PMODE/RMODE
	signal cmodei : std_logic_vector(1 downto 0) := (others=>'0');
	signal lcount : std_logic_vector(3 downto 0) := (others=>'0');
	signal ccount : std_logic := '0';
	signal fcount : std_logic_vector(3 downto 0) := (others=>'0');
	signal lstrobed : std_logic := '0';
	signal emit : std_logic_vector(3 downto 0) := x"0";
	signal ix : std_logic_vector(3 downto 0) := x"1";
	signal tailf : std_logic := '0';			-- set if to emit tail
	signal pushf : std_logic := '0';			-- set to push to abuf
	signal sev : std_logic_vector(15 downto 0);
	signal sevf : std_logic := '0';			-- set if to emit sev
	signal uevp1 : std_logic_vector(15 downto 0);	--uev+1
	signal uevf : std_logic := '0';			-- set if to emit uevp1
	--
	type Tabuf is array(15 downto 0) of std_logic_vector(15 downto 0);
	type Tabufc is array(15 downto 0) of std_logic_vector(4 downto 0);
	signal abuf : Tabuf;
	signal abufc : Tabufc;
	--
	constant ZERO :	std_logic_vector(4 downto 0) := (others=>'0');
	--
begin
	--
process(CLK)
	
begin
	if rising_edge(CLK) then
		if NEWSLICE='1' or (emit=ix-1 and emit/=0) then
			slicehead1 <= NEWSLICE;
			slicehead2 <= NEWSLICE;
			mbhead <= '1';
			mbhead <= '1';
			lcount <= (others=>'0');
			ccount <= '0';
			lbufc <= (others=>'0');
			ix <= x"1";
			emit <= x"0";
		elsif emit/=0 then
			emit <= emit+1;
		elsif slicehead1='1' then
			--NAL header byte: IDR or normal:
			if SINTRA='1' then
				lbuf <= x"5525";		--0x25 (8bits)
			else
				lbuf <= x"5521";		--0x21 (8bits)
			end if;
			lbufc <= ZERO+8;
			pushf <= '1';
			slicehead1 <= '0';
		elsif slicehead2='1' and pushf='0' then
			-- Summary: IDR I-frame headers are:
			--   1010100001001 (13 bits) or
			--   101010000010001 (15 bits)
			-- Summary: P-frame headers are:
			--   11111nnnn01 (11 bits)
			if SINTRA='1' and idrtwice='0' then
				--here if I / IDR and previous wasn't IDR
				lbuf <= b"0010101110000100";	--101110000100 (12 bits)
				lbufc <= ZERO+12;
				idrtwice <= '1';
				fcount <= b"000"&LASTSLICE;		--next frame is 1
			elsif SINTRA='1' then
				--here if I / IDR and previous was IDR (different tag)
				lbuf <= b"0010111000001000";	--10111000001000 (14 bits)
				lbufc <= ZERO+14;
				idrtwice <= '0';
				fcount <= b"000"&LASTSLICE;		--next frame is 1
			else
				--here if P
				lbuf <= b"00101011111" & fcount & b"0";	--11111nnnn0 (10 bits)
				lbufc <= ZERO+10;
				idrtwice <= '0';
				assert PTYPE=0;	--only this supported at present
				if LASTSLICE='1' then
					fcount <= fcount+1;		--next frame
				end if;
			end if;
			sev <= sxt(qp-26,16);
			sevf <= '1';
			slicehead2 <= '0';
			pushf <= '1';
		end if;
		if CSTROBE='1' and ccount='0' and NEWSLICE='0' then	--chroma
			ccount <= '1';
			cmodei <= CMODE;
		end if;
		if LSTROBE='0' then
			lstrobed <= LSTROBE;
		end if;
		if LSTROBE='1' and lstrobed='0' and NEWSLICE='0' then	--luma
			if mbhead='1' and pushf='0' then
				--head: mb_skip_run (if SINTRA) and mb_type
				if SINTRA='1' and MINTRA='1' then	--macroblock header
					--mbtype=I4x4 /1/
					lbuf(5 downto 0) <= b"000111";
					lbufc <= ZERO+1;
				elsif SINTRA='0' and MINTRA='1' then
					--mbskiprun=0, mbtype=I4x4 in Pslice /100110/
					lbuf(5 downto 0) <= b"100110";
					lbufc <= ZERO+7;
				else
					--mbskiprun=0, mbtype=P16x16 /11/
					lbuf(5 downto 0) <= b"000111";
					lbufc <= ZERO+2;
				end if;
				mbhead <= '0';
			elsif pushf='0' then
				--normal processing
				lcount <= lcount+1;
				lstrobed <= LSTROBE;
				if MINTRA='1' then
					if PMODE='1' then
						lbuf <= lbuf(14 downto 0) & PMODE;
						lbufc <= lbufc+1;
					else
						lbuf <= lbuf(11 downto 0) & PMODE & RMODE;
						lbufc <= lbufc+4;
					end if;
				else -- P macroblocks
					if lcount=1 or lcount=2 then	--mvx=0 and mvy=0
						assert MVDX=0 and MVDY=0;
						lbuf <= lbuf(14 downto 0) & '1';
						lbufc <= lbufc+1;
					end if;
				end if;
				if lcount=15 then
					tailf <= '1';
					pushf <= '1';
				end if;
			end if;
		end if;
		--
		if sevf='1' then
			--convert 16bit sev to 16bit uev, then add 1
			--these equations have been optimised rather a lot
			if sev(15)='0' and sev/=0 then
				uevp1 <= (sev(14 downto 0))&'0';
			else
				uevp1 <= (ext(b"0",15)-sev(14 downto 0))&'1';
			end if;
			uevf <= sevf;
			sevf <= '0';
		end if;
		if uevf='1' then
			lbuf <= uevp1;
			if uevp1(15 downto 1)=0 then
				lbufc <= ZERO+1;
			elsif uevp1(15 downto 2)=0 then
				lbufc <= ZERO+3;
			elsif uevp1(15 downto 3)=0 then
				lbufc <= ZERO+5;
			elsif uevp1(15 downto 4)=0 then
				lbufc <= ZERO+7;
			elsif uevp1(15 downto 5)=0 then
				lbufc <= ZERO+9;
			elsif uevp1(15 downto 6)=0 then
				lbufc <= ZERO+11;
			elsif uevp1(15 downto 7)=0 then
				lbufc <= ZERO+13;
			elsif uevp1(15 downto 8)=0 then
				lbufc <= ZERO+15;
			elsif uevp1(15 downto 9)=0 then
				lbufc <= ZERO+17;
			elsif uevp1(15 downto 10)=0 then
				lbufc <= ZERO+19;
			elsif uevp1(15 downto 11)=0 then
				lbufc <= ZERO+21;
			elsif uevp1(15 downto 12)=0 then
				lbufc <= ZERO+23;
			elsif uevp1(15 downto 13)=0 then
				lbufc <= ZERO+25;
			elsif uevp1(15 downto 14)=0 then
				lbufc <= ZERO+27;
			elsif uevp1(15)='0' then
				lbufc <= ZERO+29;
			else
				lbufc <= ZERO+31;
			end if;
			uevf <= sevf;
			pushf <= '1';
		end if;
		--
		if pushf='1' and NEWSLICE='0' then
			--emit to buffer
			if lbufc/=0 then
				abuf(conv_integer(ix)) <= lbuf;
				abufc(conv_integer(ix)) <= lbufc;
				lbufc <= ZERO;
				ix <= ix+1;
			end if;
			pushf <= '0';
		elsif lbufc>12 then
			pushf <= '1';
		end if;
		if tailf='1' and pushf='0' and NEWSLICE='0' and emit/=ix then
			--tail: chromatype if I
			--tail: codedblockpattern /1/ or /0001101/; and slice_qp_delta /1/
			if MINTRA='1' then
				if cmodei=0 then
					lbuf <= b"0000000000001111";	--111
					lbufc <= ZERO+3;
				else
					lbuf <= b"000000000010" & (cmodei+1) & b"11";	--0tt11
					lbufc <= ZERO+5;
				end if;
			else	--P
				lbuf <= b"0000000000011011";	--00011011
				lbufc <= ZERO+8;
			end if;
			pushf <= '1';
			tailf <= '0';
			emit <= emit+1;
		end if;
		--
		if emit /= 0 then
			VALID <= '1';
			VE <= x"0" & abuf(conv_integer(emit));
			VL <= abufc(conv_integer(emit));
		else
			VALID <= '0';
		end if;
	end if;
end process;
	--
end hw;

--#header


--#intra4x4

entity design4 is
	port (
		CLK : in std_logic;					--pixel clock
		--
		-- in interface:
		NEWSLICE : in std_logic;			--indication this is the first in a slice
		NEWLINE : in std_logic;				--indication this is the first on a line
		STROBEI : in std_logic;				--data here
		DATAI : in std_logic_vector(31 downto 0);
		READYI : out std_logic := '0';
		--
		-- top interface:
		TOPI : in std_logic_vector(31 downto 0);	--top pixels (to predict against)
		TOPMI : in std_logic_vector(3 downto 0);	--top block's mode (for P/RMODEO)
		XXO : out std_logic_vector(1 downto 0) := b"00";		--which macroblock X
		XXINC : out std_logic := '0';				--when to increment XX macroblock
		--
		-- feedback interface:
		FEEDBI : in std_logic_vector(7 downto 0);	--feedback for pixcol
		FBSTROBE : in std_logic;					--feedback valid
		--
		-- out interface:
		STROBEO : out std_logic := '0';				--data here
		DATAO : out std_logic_vector(35 downto 0) := (others => '0');
		BASEO : out std_logic_vector(31 downto 0) := (others => '0');	--base for reconstruct
		READYO : in std_logic := '1';
		MSTROBEO : out std_logic := '0';			--modeo here
		MODEO : out std_logic_vector(3 downto 0) := (others => '0');	--0..8 prediction type
		PMODEO : out std_logic := '0';				--prev_i4x4_pred_mode_flag
		RMODEO : out std_logic_vector(2 downto 0) := (others => '0');	--rem_i4x4_pred_mode_flag
		--
		CHREADY :  out std_logic := '0'				--ready line to chroma
	);
end design4;

architecture hw of design4 is
	--pixels on left
	type Tpix is array(63 downto 0) of std_logic_vector(31 downto 0);
	signal pix : Tpix := (others => (others => '0'));	--macroblock data
	type Tpixcol is array(15 downto 0) of std_logic_vector(7 downto 0);
	signal pixleft : Tpixcol := (others => x"00");		--previous col
	signal pixlefttop : std_logic_vector(7 downto 0);	--previous top col
	signal lvalid : std_logic := '0';					--set if pixels on left are valid
	signal tvalid : std_logic := '0';					--set if TOP valid (not first line)
	signal dconly : std_logic := '0';					--dconly as per std
	signal topih : std_logic_vector(31 downto 0) := (others=>'0');
	signal topii : std_logic_vector(31 downto 0) := (others=>'0');
	--
	--input states	
	signal statei : std_logic_vector(5 downto 0) := b"000000";	--state(rowcol) for input
	--processing states	
	constant IDLE : std_logic_vector(4 downto 0) := b"00000";
	signal state : std_logic_vector(4 downto 0) := IDLE;	--state/row for processing
	--output state
	signal outf1 : std_logic := '0';						--output flag
	signal outf : std_logic := '0';							--output flag
	signal chreadyi : std_logic := '0';						--chready anticipated
	signal chreadyii : std_logic := '0';					--chready anticipated 2
	signal readyod : std_logic := '0';						--delayed READYO in
	--
	--position of sub macroblock in macroblock
	signal submb : std_logic_vector(3 downto 0) := x"0";	--which of 16 submb in mb
	signal xx : std_logic_vector(1 downto 0) := b"00";
	signal yy : std_logic_vector(1 downto 0) := b"00";
	signal yyfull : std_logic_vector(3 downto 0) := x"0";
	signal oldxx : std_logic_vector(1 downto 0) := b"00";
	signal fbptr : std_logic_vector(3 downto 0) := x"0";
	signal fbpending : std_logic := '0';
	--type out
	signal modeoi : std_logic_vector(3 downto 0) := x"0";
	signal prevmode : std_logic_vector(3 downto 0) := x"0";
	type Tlmode is array(3 downto 0) of std_logic_vector(3 downto 0);
	signal lmode : Tlmode := (others => x"9");
	--data path
	signal dat0 : std_logic_vector(31 downto 0) := (others=>'0');
	--data channels
	alias datai0 : std_logic_vector(7 downto 0) is dat0(7 downto 0);
	alias datai1 : std_logic_vector(7 downto 0) is dat0(15 downto 8);
	alias datai2 : std_logic_vector(7 downto 0) is dat0(23 downto 16);
	alias datai3 : std_logic_vector(7 downto 0) is dat0(31 downto 24);
	--top channels
	alias topi0 : std_logic_vector(7 downto 0) is TOPI(7 downto 0);
	alias topi1 : std_logic_vector(7 downto 0) is TOPI(15 downto 8);
	alias topi2 : std_logic_vector(7 downto 0) is TOPI(23 downto 16);
	alias topi3 : std_logic_vector(7 downto 0) is TOPI(31 downto 24);
	alias topii0 : std_logic_vector(7 downto 0) is topii(7 downto 0);
	alias topii1 : std_logic_vector(7 downto 0) is topii(15 downto 8);
	alias topii2 : std_logic_vector(7 downto 0) is topii(23 downto 16);
	alias topii3 : std_logic_vector(7 downto 0) is topii(31 downto 24);
	--diffs for mode 0 vertical
	signal vdif0 : std_logic_vector(8 downto 0) :=  (others=>'0');
	signal vdif1 : std_logic_vector(8 downto 0) :=  (others=>'0');
	signal vdif2 : std_logic_vector(8 downto 0) :=  (others=>'0');
	signal vdif3 : std_logic_vector(8 downto 0) :=  (others=>'0');
	signal vabsdif0 : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal vabsdif1 : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal vabsdif2 : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal vabsdif3 : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal vtotdif : std_logic_vector(11 downto 0) :=  (others=>'0');
	--diffs for mode 1 horizontal
	signal leftp : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal leftpd : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal hdif0 : std_logic_vector(8 downto 0) :=  (others=>'0');
	signal hdif1 : std_logic_vector(8 downto 0) :=  (others=>'0');
	signal hdif2 : std_logic_vector(8 downto 0) :=  (others=>'0');
	signal hdif3 : std_logic_vector(8 downto 0) :=  (others=>'0');
	signal habsdif0 : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal habsdif1 : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal habsdif2 : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal habsdif3 : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal htotdif : std_logic_vector(11 downto 0) :=  (others=>'0');
	--diffs for mode 2 dc
	signal left0 : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal left1 : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal left2 : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal left3 : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal ddif0 : std_logic_vector(8 downto 0) :=  (others=>'0');
	signal ddif1 : std_logic_vector(8 downto 0) :=  (others=>'0');
	signal ddif2 : std_logic_vector(8 downto 0) :=  (others=>'0');
	signal ddif3 : std_logic_vector(8 downto 0) :=  (others=>'0');
	signal dabsdif0 : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal dabsdif1 : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal dabsdif2 : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal dabsdif3 : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal dtotdif : std_logic_vector(11 downto 0) :=  (others=>'0');
	--averages for mode 2 dc
	signal sumt : std_logic_vector(9 downto 0) :=  (others=>'0');
	signal suml : std_logic_vector(9 downto 0) :=  (others=>'0');
	signal sumtl : std_logic_vector(10 downto 0) :=  (others=>'0');
	alias avg  : std_logic_vector(7 downto 0) is sumtl(10 downto 3);
	--
begin
	--
	xx <= submb(2)&submb(0);
	yy <= submb(3)&submb(1);
	--
	XXO <= xx when state=2 or state=16 else oldxx;
	XXINC <= '1' when state=20 else '0';
	READYI <= '1' when statei(5 downto 4) /= yy-2 and statei(5 downto 4) /= yy-1 else '0';
	--
	yyfull <= yy & state(1 downto 0);
	left0 <= pixleft(conv_integer(yy & b"00"));
	left1 <= pixleft(conv_integer(yy & b"01"));
	left2 <= pixleft(conv_integer(yy & b"10"));
	left3 <= pixleft(conv_integer(yy & b"11"));
	--
	MODEO <= modeoi;
	--
	CHREADY <= chreadyii and READYO;
	--
process(CLK)
	variable xi: integer;
	variable yi: integer;
begin
	if rising_edge(CLK) then
		--
		if STROBEI='1' then
			pix(conv_integer(statei)) <= DATAI;
			statei <= statei + 1;
		elsif NEWLINE='1' then
			statei <= b"000000";
			lvalid <= '0';
			state <= IDLE;
			STROBEO <= '0';
			fbpending <= '0';
		end if;
		if NEWSLICE='1' then
			tvalid <= '0';
		elsif NEWLINE='1' then
			tvalid <= '1';
		end if;
		--
		if state=15 then
			submb <= submb+1;
		end if;
		if state=1 or state=15 then
			oldxx <= xx;
		end if;
		if state=IDLE and statei=0 then
			null;	--wait for some data
		elsif state=3 and statei(5 downto 4)=yy then
			null;	--wait for enough data
		elsif state=11 and (READYO='0' or FBSTROBE='1' or fbpending='1') then
			null;	--wait before output
		elsif state=15 and xx(0)='1' and submb/=15 then
			state <= IDLE+2;	--quickly onto next (no need to await strobe)
		elsif state=19 and (FBSTROBE='1' or fbpending='1' or chreadyi='1' or chreadyii='1') then
			null;	--wait for fb / chready complete
		elsif state=19 and submb/=0 then
			state <= IDLE+3;	--onto next
		elsif state=20 then
			--new macroblock, XXINC is set this state
			state <= IDLE;		--reload new TOP stuff
		else
			state <= state+1;
		end if;
		if state=15 and xx(0)='0' then
			chreadyi <= '1';
		end if;
		if outf='0' and chreadyi='1' and READYO='0' then
			chreadyii <= '1';
			chreadyi <= '0';
		elsif READYO='0' and readyod='1' and chreadyii='1' then
			chreadyii <= '0';
		end if;
		readyod <= READYO;
		--
		if state=2 or state=16 then
			--read TOPMI for this submb (only if tvalid&lvalid)
			if TOPMI < lmode(conv_integer(yy)) then
				prevmode <= TOPMI;
			else
				prevmode <= lmode(conv_integer(yy));
			end if;
			--
			sumt <= (b"00"&topi0) + (b"00"&topi1) + (b"00"&topi2) + (b"00"&topi3);
			topih <= TOPI;
		end if;
		suml <= (b"00"&left0) + (b"00"&left1) + (b"00"&left2) + (b"00"&left3);
		if state=3 then
			-- set avg by setting sumtl
			if lvalid='1' or xx/=0 then	--left valid
				if tvalid='1' or yy/=0 then				--top valid
					sumtl <= ('0'&sumt) + ('0'&suml) + 4;
				else
					sumtl <= (suml&'0') + 4;
				end if;
			else
				if tvalid='1' or yy/=0 then				--top valid
					sumtl <= (sumt&'0') + 4;
				else
					sumtl <= x"80"&b"000";
				end if;
			end if;
			topii <= topih;
		end if;
		--
		-- states 4..7(pass1) 12..15(pass2)
		dat0 <= pix(conv_integer(yy & state(1 downto 0) & xx));
		leftp <= pixleft(conv_integer(yyfull));
		--
		-- states 5..8 (pass1) 13..16 (pass2)
		vdif0 <= ('0'&datai0) - ('0'&topii0);
		vdif1 <= ('0'&datai1) - ('0'&topii1);
		vdif2 <= ('0'&datai2) - ('0'&topii2);
		vdif3 <= ('0'&datai3) - ('0'&topii3);
		--
		hdif0 <= ('0'&datai0) - ('0'&leftp);
		hdif1 <= ('0'&datai1) - ('0'&leftp);
		hdif2 <= ('0'&datai2) - ('0'&leftp);
		hdif3 <= ('0'&datai3) - ('0'&leftp);
		leftpd <= leftp;
		--
		ddif0 <= ('0'&datai0) - ('0'&avg);
		ddif1 <= ('0'&datai1) - ('0'&avg);
		ddif2 <= ('0'&datai2) - ('0'&avg);
		ddif3 <= ('0'&datai3) - ('0'&avg);
		--
		-- states 6..9
		if vdif0(8)='0' then
			vabsdif0 <= vdif0(7 downto 0);
		else
			vabsdif0 <= x"00"-vdif0(7 downto 0);
		end if;
		if vdif1(8)='0' then
			vabsdif1 <= vdif1(7 downto 0);
		else
			vabsdif1 <= x"00"-vdif1(7 downto 0);
		end if;
		if vdif2(8)='0' then
			vabsdif2 <= vdif2(7 downto 0);
		else
			vabsdif2 <= x"00"-vdif2(7 downto 0);
		end if;
		if vdif3(8)='0' then
			vabsdif3 <= vdif3(7 downto 0);
		else
			vabsdif3 <= x"00"-vdif3(7 downto 0);
		end if;
		--
		if hdif0(8)='0' then
			habsdif0 <= hdif0(7 downto 0);
		else
			habsdif0 <= x"00"-hdif0(7 downto 0);
		end if;
		if hdif1(8)='0' then
			habsdif1 <= hdif1(7 downto 0);
		else
			habsdif1 <= x"00"-hdif1(7 downto 0);
		end if;
		if hdif2(8)='0' then
			habsdif2 <= hdif2(7 downto 0);
		else
			habsdif2 <= x"00"-hdif2(7 downto 0);
		end if;
		if hdif3(8)='0' then
			habsdif3 <= hdif3(7 downto 0);
		else
			habsdif3 <= x"00"-hdif3(7 downto 0);
		end if;
		--
		if ddif0(8)='0' then
			dabsdif0 <= ddif0(7 downto 0);
		else
			dabsdif0 <= x"00"-ddif0(7 downto 0);
		end if;
		if ddif1(8)='0' then
			dabsdif1 <= ddif1(7 downto 0);
		else
			dabsdif1 <= x"00"-ddif1(7 downto 0);
		end if;
		if ddif2(8)='0' then
			dabsdif2 <= ddif2(7 downto 0);
		else
			dabsdif2 <= x"00"-ddif2(7 downto 0);
		end if;
		if ddif3(8)='0' then
			dabsdif3 <= ddif3(7 downto 0);
		else
			dabsdif3 <= x"00"-ddif3(7 downto 0);
		end if;
		--
		if state=6 then
			vtotdif <= (others => '0');
			htotdif <= (others => '0');
			dtotdif <= (others => '0');
			if (tvalid='1' or yy/=0) and (lvalid='1' or xx/=0) then
				dconly <= '0';
			else
				dconly <= '1';
			end if;
		end if;
		-- states 7..10
		if state>=7 and state<=10 then
			vtotdif <= (x"0"&vabsdif0) + (x"0"&vabsdif1) + (x"0"&vabsdif2) + (x"0"&vabsdif3) + vtotdif;
			htotdif <= (x"0"&habsdif0) + (x"0"&habsdif1) + (x"0"&habsdif2) + (x"0"&habsdif3) + htotdif;
			dtotdif <= (x"0"&dabsdif0) + (x"0"&dabsdif1) + (x"0"&dabsdif2) + (x"0"&dabsdif3) + dtotdif;
		end if;
		--
		if state=11 then
			if vtotdif <= htotdif and vtotdif <= dtotdif and dconly='0' then
				modeoi <= x"0";		--vertical prefer
			elsif htotdif <= dtotdif and dconly='0' then
				modeoi <= x"1";		--horizontal prefer
			else
				modeoi <= x"2";		--DC
			end if;
		end if;
		if state=12 then
			lmode(conv_integer(yy)) <= modeoi;
			assert modeoi=2 or dconly='0' report "modeoi wrong for dconly";
			if dconly='1' or prevmode = modeoi then
				PMODEO <= '1';
			elsif modeoi < prevmode then
				PMODEO <= '0';
				RMODEO <= modeoi(2 downto 0);
			else
				PMODEO <= '0';
				RMODEO <= modeoi(2 downto 0) - 1;
			end if;
		end if;
		if state>=12 and state<=15 then
			outf1 <= '1';
		else
			outf1 <= '0';
		end if;
		outf <= outf1;
		-- states 14..17
		if outf='1' then
			STROBEO <= '1';
			MSTROBEO <= not outf1;
			if modeoi=0 then
				DATAO <= vdif3&vdif2&vdif1&vdif0;
				BASEO <= topii;
			elsif modeoi=1 then
				DATAO <= hdif3&hdif2&hdif1&hdif0;
				BASEO <= leftpd&leftpd&leftpd&leftpd;
			elsif modeoi=2 then
				DATAO <= ddif3&ddif2&ddif1&ddif0;
				BASEO <= avg&avg&avg&avg;
			end if;
		else
			STROBEO <= '0';
			MSTROBEO <= '0';
		end if;
		if state=15 and FBSTROBE='0' then	--set feedback ptr to get later feedback
			fbptr <= yy & b"00";
			fbpending <= '1';
		end if;
		--
		-- this comes back from transform/quantise/dequant/detransform loop
		-- some time later...
		--
		if FBSTROBE='1' then
			pixleft(conv_integer(fbptr)) <= FEEDBI;
			fbptr <= fbptr + 1;
			fbpending <= '0';
			if (submb=14 or submb=15) and NEWLINE='0' then
				lvalid <= '1';
			end if;
		end if;
		--
	end if;
end process;
	--
end hw;	--h264intra4x4

--#intra4x4


--#intra8x8

entity design4 is
	port (
		CLK2 : in std_logic;				--2x clock
		--
		-- in interface:
		NEWSLICE : in std_logic;			--indication this is the first in a slice
		NEWLINE : in std_logic;				--indication this is the first on a line
		STROBEI : in std_logic;				--data here
		DATAI : in std_logic_vector(31 downto 0);
		READYI : out std_logic := '0';
		--
		-- top interface:
		TOPI : in std_logic_vector(31 downto 0);	--top pixels (to predict against)
		XXO : out std_logic_vector(1 downto 0) := b"00";		--which macroblock X
		XXC : out std_logic := '0';				--carry from XXO, to add to macroblock
		XXINC : out std_logic := '0';			--when to increment XX macroblock
		--
		-- feedback interface:
		FEEDBI : in std_logic_vector(7 downto 0);	--feedback for pixcol
		FBSTROBE : in std_logic;					--feedback valid
		--
		-- out interface:
		STROBEO : out std_logic := '0';				--data here
		DATAO : out std_logic_vector(35 downto 0) := (others => '0');
		BASEO : out std_logic_vector(31 downto 0) := (others => '0');	--base for reconstruct
		READYO : in std_logic := '1';
		DCSTROBEO : out std_logic := '0';			--dc data here
		DCDATAO : out std_logic_vector(15 downto 0) := (others => '0');
		CMODEO : out std_logic_vector(1 downto 0) := (others => '0')	--prediction type
	);
end design4;

architecture hw of design4 is
	--pixels
	type Tpix is array(31 downto 0) of std_logic_vector(31 downto 0);
	signal pix : Tpix := (others => (others => '0'));	--macroblock data; first half is Cb, then Cr
	type Tpixcol is array(15 downto 0) of std_logic_vector(7 downto 0);
	signal pixleft : Tpixcol := (others => x"00");		--previous col, first half is Cb, then Cr
	signal lvalid : std_logic := '0';					--set if pixels on left are valid
	signal tvalid : std_logic := '0';					--set if TOP valid (not first line)
	signal topil : std_logic_vector(31 downto 0) := (others=>'0');
	signal topir : std_logic_vector(31 downto 0) := (others=>'0');
	signal topii : std_logic_vector(31 downto 0) := (others=>'0');
	--input states
	signal istate : std_logic_vector(4 downto 0) := (others=>'0');	--which input word
	--processing states	
	signal crcb : std_logic := '0';			--which of cr/cb
	signal quad : std_logic_vector(1 downto 0) := b"00";	--which of 4 blocks
	constant IDLE : std_logic_vector(3 downto 0) := b"0000";
	signal state : std_logic_vector(3 downto 0) := IDLE;	--state/row for processing
	--output state
	signal oquad : std_logic_vector(1 downto 0) := b"00";	--which of 4 blocks output
	signal fquad : std_logic_vector(1 downto 0) := b"00";	--which of 4 blocks for feedback
	signal ddc1  : std_logic := '0';						--output flag dc
	signal ddc2  : std_logic := '0';						--output flag dc
	signal fbpending : std_logic := '0';					--wait for feedback
	signal fbptr : std_logic_vector(3 downto 0) := b"0000";
	--type out
	--signal cmodeoi : std_logic_vector(1 downto 0) := b"00";	--always DC=0 this version
	--data path
	signal dat0 : std_logic_vector(31 downto 0) := (others=>'0');
	--data channels
	alias datai0 : std_logic_vector(7 downto 0) is dat0(7 downto 0);
	alias datai1 : std_logic_vector(7 downto 0) is dat0(15 downto 8);
	alias datai2 : std_logic_vector(7 downto 0) is dat0(23 downto 16);
	alias datai3 : std_logic_vector(7 downto 0) is dat0(31 downto 24);
	--top channels
	alias topii0 : std_logic_vector(7 downto 0) is topii(7 downto 0);
	alias topii1 : std_logic_vector(7 downto 0) is topii(15 downto 8);
	alias topii2 : std_logic_vector(7 downto 0) is topii(23 downto 16);
	alias topii3 : std_logic_vector(7 downto 0) is topii(31 downto 24);
	--diffs for mode 2 dc
	signal lindex : std_logic_vector(1 downto 0) :=  (others=>'0');
	signal left0 : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal left1 : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal left2 : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal left3 : std_logic_vector(7 downto 0) :=  (others=>'0');
	signal ddif0 : std_logic_vector(8 downto 0) :=  (others=>'0');
	signal ddif1 : std_logic_vector(8 downto 0) :=  (others=>'0');
	signal ddif2 : std_logic_vector(8 downto 0) :=  (others=>'0');
	signal ddif3 : std_logic_vector(8 downto 0) :=  (others=>'0');
	signal dtot : std_logic_vector(12 downto 0) :=  (others=>'0');
	--averages for mode 2 dc
	signal sumt : std_logic_vector(9 downto 0) :=  (others=>'0');
	signal suml : std_logic_vector(9 downto 0) :=  (others=>'0');
	signal sumtl : std_logic_vector(10 downto 0) :=  (others=>'0');
	alias avg  : std_logic_vector(7 downto 0) is sumtl(10 downto 3);
	--
begin
	-- 
	XXO <= crcb & fquad(0);
	XXINC <= '1' when state=15 and crcb='1' else '0';
	READYI <= '1' when state=IDLE or istate(4) /= crcb else '0';
	DCDATAO <= sxt(dtot,16);
	--
	topii <= topil when quad(0)='0' else topir;
	lindex <= crcb & quad(1);
	left0 <= pixleft(conv_integer(lindex & b"00"));
	left1 <= pixleft(conv_integer(lindex & b"01"));
	left2 <= pixleft(conv_integer(lindex & b"10"));
	left3 <= pixleft(conv_integer(lindex & b"11"));
	--
	--CMODEO <= cmodeoi;	--always 00
	--
process(CLK2)
begin
	if rising_edge(CLK2) then
		--
		if STROBEI='1' then
			pix(conv_integer(istate)) <= DATAI;
			istate <= istate + 1;
		elsif NEWLINE='1' then
			istate <= (others=>'0');
			lvalid <= '0';
			state <= IDLE;
			crcb <= '0';
			quad <= b"00";
		end if;
		if NEWSLICE='1' then
			tvalid <= '0';
		elsif NEWLINE='1' then
			tvalid <= '1';
		end if;
		--
		if NEWLINE='0' then
			if state=IDLE and istate(4)=crcb then
				null;	--wait for enough data
			elsif state=7 and oquad/=3 then
				state <= IDLE+4;			--loop to load all DC coeffs
			elsif state=8 and READYO='0' then
				null;	--wait before output
			elsif state=14 and (fbpending='1' or FBSTROBE='1') then
				null;	--wait before feedback
			elsif state=14 and quad/=0 then
				state <= IDLE+8;			--loop for all blocks
			else
				state <= state+1;
			end if;
			--
			if state=15 then
				crcb <= not crcb;
				if crcb='1' then
					lvalid <= '1';	--new macroblk
				end if;
			end if;
			--
			if state=5 or state=9 then
				quad <= quad+1;
			end if;
			if state=7 or state=11 then
				oquad <= quad;
			end if;
			if state=0 or state=1 then
				fquad(0) <= state(0);	--for latching topir/topil
			elsif state=9 then
				fquad <= quad;
			end if;
		end if;
		--
		if state=1 then
			topil <= TOPI;
		elsif state=2 then
			topir <= TOPI;
		end if;
		sumt <= (b"00"&topii0) + (b"00"&topii1) + (b"00"&topii2) + (b"00"&topii3);
		suml <= (b"00"&left0) + (b"00"&left1) + (b"00"&left2) + (b"00"&left3);
		if state=4 or state=8 then
			-- set avg by setting sumtl
			-- note: quad 1 and 2 don't use sumt+suml but prefer sumt or suml if poss
			if lvalid='1' and tvalid='1' and (quad=0 or quad=3) then	--left+top valid
				sumtl <= ('0'&sumt) + ('0'&suml) + 4;
			elsif lvalid='1' and (tvalid='0' or quad=2) then
				sumtl <= (suml&'0') + 4;
			elsif (lvalid='0' or quad=1) and tvalid='1' then
				sumtl <= (sumt&'0') + 4;
			else
				sumtl <= x"80"&b"000";
			end if;
		end if;
		--
		--states 4..7, 8..11
		dat0 <= pix(conv_integer(crcb & oquad(1) & state(1 downto 0) & oquad(0)));
		if state=7 then
			ddc1 <= '1';
		else
			ddc1 <= '0';
		end if;
		--
		--states 5..(8), 9..12
		ddif0 <= ('0'&datai0) - ('0'&avg);
		ddif1 <= ('0'&datai1) - ('0'&avg);
		ddif2 <= ('0'&datai2) - ('0'&avg);
		ddif3 <= ('0'&datai3) - ('0'&avg);
		ddc2 <= ddc1;
		--
		--states 6..(9)
		if state=6 then
			dtot <= sxt(ddif0,13) + sxt(ddif1,13) + sxt(ddif2,13) + sxt(ddif3,13);
		else
			dtot <= dtot + sxt(ddif0,13) + sxt(ddif1,13) + sxt(ddif2,13) + sxt(ddif3,13);
		end if;
		DCSTROBEO <= ddc2;
		--
		--states 10..13
		if state>=10 and state<=13 then
			DATAO <= ddif3 & ddif2 & ddif1 & ddif0;
			BASEO <= avg&avg&avg&avg;
			STROBEO <= '1';
		else
			STROBEO <= '0';
		end if;
		--		
		if state=9 then	--set feedback ptr to get later feedback
			fbptr <= crcb & quad(1) & b"00";
			fbpending <= '1';
		end if;
		--
		-- this comes back from transform/quantise/dequant/detransform loop
		-- some time later... (state=13 waits for it)
		--
		if FBSTROBE='1' and state>=12 then
			if quad(0)='0' then
				pixleft(conv_integer(fbptr)) <= FEEDBI;
			end if;
			fbptr <= fbptr + 1;
			fbpending <= '0';
		end if;
		--
	end if;
end process;
	--
end hw;	--h264intra8x8cc

--#intra8x8


--#invtransform

entity design4 is
	port (
		CLK : in std_logic;					--fast io clock
		ENABLE : in std_logic;				--values input only when this is 1
		WIN : in std_logic_vector(15 downto 0);	--input (reverse zigzag order)
		VALID : out std_logic := '0';				--values output only when this is 1
		XOUT : out std_logic_vector(39 downto 0):= (others => '0')	--4 x 10bit, first px is lsbs
	);
end design4;

architecture hw of design4 is
	--
	--index to the d and f are (y first) as per std d and f
	signal d01 : std_logic_vector(15 downto 0) := (others => '0');
	signal d02 : std_logic_vector(15 downto 0) := (others => '0');
	signal d03 : std_logic_vector(15 downto 0) := (others => '0');
	signal d11 : std_logic_vector(15 downto 0) := (others => '0');
	signal d12 : std_logic_vector(15 downto 0) := (others => '0');
	signal d13 : std_logic_vector(15 downto 0) := (others => '0');
	signal d21 : std_logic_vector(15 downto 0) := (others => '0');
	signal d22 : std_logic_vector(15 downto 0) := (others => '0');
	signal d23 : std_logic_vector(15 downto 0) := (others => '0');
	signal d31 : std_logic_vector(15 downto 0) := (others => '0');
	signal d32 : std_logic_vector(15 downto 0) := (others => '0');
	signal d33 : std_logic_vector(15 downto 0) := (others => '0');
	signal e0 : std_logic_vector(15 downto 0) := (others => '0');
	signal e1 : std_logic_vector(15 downto 0) := (others => '0');
	signal e2 : std_logic_vector(15 downto 0) := (others => '0');
	signal e3 : std_logic_vector(15 downto 0) := (others => '0');
	signal f00 : std_logic_vector(15 downto 0) := (others => '0');
	signal f01 : std_logic_vector(15 downto 0) := (others => '0');
	signal f02 : std_logic_vector(15 downto 0) := (others => '0');
	signal f03 : std_logic_vector(15 downto 0) := (others => '0');
	signal f10 : std_logic_vector(15 downto 0) := (others => '0');
	signal f11 : std_logic_vector(15 downto 0) := (others => '0');
	signal f12 : std_logic_vector(15 downto 0) := (others => '0');
	signal f13 : std_logic_vector(15 downto 0) := (others => '0');
	signal f20 : std_logic_vector(15 downto 0) := (others => '0');
	signal f21 : std_logic_vector(15 downto 0) := (others => '0');
	signal f22 : std_logic_vector(15 downto 0) := (others => '0');
	signal f23 : std_logic_vector(15 downto 0) := (others => '0');
	signal f30 : std_logic_vector(15 downto 0) := (others => '0');
	signal f31 : std_logic_vector(15 downto 0) := (others => '0');
	signal f32 : std_logic_vector(15 downto 0) := (others => '0');
	signal f33 : std_logic_vector(15 downto 0) := (others => '0');
	signal g0 : std_logic_vector(15 downto 0) := (others => '0');
	signal g1 : std_logic_vector(15 downto 0) := (others => '0');
	signal g2 : std_logic_vector(15 downto 0) := (others => '0');
	signal g3 : std_logic_vector(15 downto 0) := (others => '0');
	signal h00 : std_logic_vector(9 downto 0) := (others => '0');
	signal h01 : std_logic_vector(9 downto 0) := (others => '0');
	signal h02 : std_logic_vector(9 downto 0) := (others => '0');
	signal h10 : std_logic_vector(9 downto 0) := (others => '0');
	signal h11 : std_logic_vector(9 downto 0) := (others => '0');
	signal h12 : std_logic_vector(9 downto 0) := (others => '0');
	signal h13 : std_logic_vector(9 downto 0) := (others => '0');
	signal h20 : std_logic_vector(9 downto 0) := (others => '0');
	signal h21 : std_logic_vector(9 downto 0) := (others => '0');
	signal h22 : std_logic_vector(9 downto 0) := (others => '0');
	signal h23 : std_logic_vector(9 downto 0) := (others => '0');
	signal h30 : std_logic_vector(9 downto 0) := (others => '0');
	signal h31 : std_logic_vector(9 downto 0) := (others => '0');
	signal h32 : std_logic_vector(9 downto 0) := (others => '0');
	signal h33 : std_logic_vector(9 downto 0) := (others => '0');
	signal hx0 : std_logic_vector(15 downto 0) := (others => '0');
	signal hx1 : std_logic_vector(15 downto 0) := (others => '0');
	signal hx2 : std_logic_vector(15 downto 0) := (others => '0');
	signal hx3 : std_logic_vector(15 downto 0) := (others => '0');
	--
	signal iww : std_logic_vector(3 downto 0) := b"0000";
	signal ixx : std_logic_vector(3 downto 0) := b"0000";
	--
	alias xout0 : std_logic_vector(9 downto 0) is XOUT(9 downto 0);
	alias xout1 : std_logic_vector(9 downto 0) is XOUT(19 downto 10);
	alias xout2 : std_logic_vector(9 downto 0) is XOUT(29 downto 20);
	alias xout3 : std_logic_vector(9 downto 0) is XOUT(39 downto 30);
begin
	--
process(CLK)
	variable d00 : std_logic_vector(15 downto 0) := (others => '0');
	variable d10 : std_logic_vector(15 downto 0) := (others => '0');
	variable d20 : std_logic_vector(15 downto 0) := (others => '0');
	variable d30 : std_logic_vector(15 downto 0) := (others => '0');
	variable h0 : std_logic_vector(15 downto 0) := (others => '0');
	variable h1 : std_logic_vector(15 downto 0) := (others => '0');
	variable h2 : std_logic_vector(15 downto 0) := (others => '0');
	variable h3 : std_logic_vector(15 downto 0) := (others => '0');
	variable h03 : std_logic_vector(9 downto 0) := (others => '0');
begin
	if rising_edge(CLK) then
		if ENABLE='1' or iww /= 0 then
			iww <= iww + 1;
		end if;
		if iww=15 or ixx /= 0 then
			ixx <= ixx + 1;
		end if;
	end if;
	if rising_edge(CLK) then
		--input: in reverse zigzag order
		if iww = 0 then
			d33 <= WIN;	--ROW3&COL3;
		elsif iww = 1 then
			d32 <= WIN;	--ROW3&COL2 
		elsif iww = 2 then
			d23 <= WIN;	--ROW2&COL3 
		elsif iww = 3 then
			d13 <= WIN;	--ROW1&COL3 
		elsif iww = 4 then
			d22 <= WIN;	--ROW2&COL2 
		elsif iww = 5 then
			d31 <= WIN;	--ROW3&COL1 
		elsif iww = 6 then
			d30 := WIN;	--ROW3&COL0
			e0 <= d30 + d32;	--process ROW3
			e1 <= d30 - d32;
			e2 <= (d31(15)&d31(15 downto 1)) - d33;
			e3 <= d31 + (d33(15)&d33(15 downto 1));
		elsif iww = 7 then
			f30 <= e0 + e3;
			f31 <= e1 + e2;
			f32 <= e1 - e2;
			f33 <= e0 - e3;
			d21 <= WIN;	--ROW2&COL1 
		elsif iww = 8 then
			d12 <= WIN;	--ROW1&COL2 
		elsif iww = 9 then
			d03 <= WIN;	--ROW0&COL3
		elsif iww = 10 then
			d02 <= WIN;	--ROW0&COL2
		elsif iww = 11 then
			d11 <= WIN;	--ROW1&COL1 
		elsif iww = 12 then
			d20 := WIN;	--ROW2&COL0 
			e0 <= d20 + d22;	--process ROW2
			e1 <= d20 - d22;
			e2 <= (d21(15)&d21(15 downto 1)) - d23;
			e3 <= d21 + (d23(15)&d23(15 downto 1));
		elsif iww = 13 then
			f20 <= e0 + e3;
			f21 <= e1 + e2;
			f22 <= e1 - e2;
			f23 <= e0 - e3;
			d10 := WIN;	--ROW1&COL0
			e0 <= d10 + d12;	--process ROW1
			e1 <= d10 - d12;
			e2 <= (d11(15)&d11(15 downto 1)) - d13;
			e3 <= d11 + (d13(15)&d13(15 downto 1));
		elsif iww = 14 then
			f10 <= e0 + e3;
			f11 <= e1 + e2;
			f12 <= e1 - e2;
			f13 <= e0 - e3;
			d01 <= WIN;	--ROW0&COL1
		elsif iww = 15 then
			d00 := WIN;	--ROW0&COL0
			e0 <= d00 + d02;	--process ROW1
			e1 <= d00 - d02;
			e2 <= (d01(15)&d01(15 downto 1)) - d03;
			e3 <= d01 + (d03(15)&d03(15 downto 1));
		end if;
		--output stages (immediately after input stage 15)
		if ixx = 1 then
			f00 <= e0 + e3;	--complete input stage
			f01 <= e1 + e2;
			f02 <= e1 - e2;
			f03 <= e0 - e3;
		elsif ixx = 2 then
			g0 <= f00 + f20;		--col 0
			g1 <= f00 - f20;
			g2 <= (f10(15)&f10(15 downto 1)) - f30;
			g3 <= f10 + (f30(15)&f30(15 downto 1));
		elsif ixx = 3 then
			h0 := (g0 + g3) + 32;	--32 is rounding factor
			h1 := (g1 + g2) + 32;
			h2 := (g1 - g2) + 32;
			h3 := (g0 - g3) + 32;
			h00 <= h0(15 downto 6);
			h10 <= h1(15 downto 6);
			h20 <= h2(15 downto 6);
			h30 <= h3(15 downto 6);
			--VALID <= '1';
			g0 <= f01 + f21;		--col 1
			g1 <= f01 - f21;
			g2 <= (f11(15)&f11(15 downto 1)) - f31;
			g3 <= f11 + (f31(15)&f31(15 downto 1));
			--XOUT <= (see above)
		elsif ixx = 4 then
			h0 := (g0 + g3) + 32;	--32 is rounding factor
			h1 := (g1 + g2) + 32;
			h2 := (g1 - g2) + 32;
			h3 := (g0 - g3) + 32;
			h01 <= h0(15 downto 6);
			h11 <= h1(15 downto 6);
			h21 <= h2(15 downto 6);
			h31 <= h3(15 downto 6);
			g0 <= f02 + f22;		--col 2
			g1 <= f02 - f22;
			g2 <= (f12(15)&f12(15 downto 1)) - f32;
			g3 <= f12 + (f32(15)&f32(15 downto 1));
		elsif ixx = 5 then
			h0 := (g0 + g3) + 32;	--32 is rounding factor
			h1 := (g1 + g2) + 32;
			h2 := (g1 - g2) + 32;
			h3 := (g0 - g3) + 32;
			h02 <= h0(15 downto 6);
			h12 <= h1(15 downto 6);
			h22 <= h2(15 downto 6);
			h32 <= h3(15 downto 6);
			g0 <= f03 + f23;		--col 3
			g1 <= f03 - f23;
			g2 <= (f13(15)&f13(15 downto 1)) - f33;
			g3 <= f13 + (f33(15)&f33(15 downto 1));
		elsif ixx = 6 then
			h0 := (g0 + g3) + 32;	--32 is rounding factor
			h1 := (g1 + g2) + 32;
			h2 := (g1 - g2) + 32;
			h3 := (g0 - g3) + 32;
			h03 := h0(15 downto 6);
			h13 <= h1(15 downto 6);
			h23 <= h2(15 downto 6);
			h33 <= h3(15 downto 6);
			VALID <= '1';
			xout0 <= h00;
			xout1 <= h01;
			xout2 <= h02;
			xout3 <= h03;
		elsif ixx=7 then
			xout0 <= h10;
			xout1 <= h11;
			xout2 <= h12;
			xout3 <= h13;
		elsif ixx=8 then
			xout0 <= h20;
			xout1 <= h21;
			xout2 <= h22;
			xout3 <= h23;
		elsif ixx=9 then
			xout0 <= h30;
			xout1 <= h31;
			xout2 <= h32;
			xout3 <= h33;
		elsif ixx=10 then
			VALID <= '0';
		end if;
		hx0 <= h0;--DEBUG
		hx1 <= h1;
		hx2 <= h2;
		hx3 <= h3;
	end if;
end process;
	--
end hw; --of h264invtransform;

--#invtransform


--#quantise

entity design4 is
	port (
		CLK : in std_logic;					--pixel clock
		ENABLE : in std_logic;				--values transfered only when this is 1
		QP : in std_logic_vector(5 downto 0);	--0..51 as specified in standard
		DCCI : in std_logic;					--2x2 DC chroma in
		YNIN : in std_logic_vector(15 downto 0);
		ZOUT : out std_logic_vector(11 downto 0) := (others=>'0');
		DCCO : out std_logic;					--2x2 DC chroma out
		VALID : out std_logic := '0'			-- enable delayed to same as YOUT timing
	);
end design4;

architecture hw of design4 is
	--
	signal zig : std_logic_vector(3 downto 0) := x"F";
	signal qmf : std_logic_vector(13 downto 0) := (others=>'0');
	signal qmfA : std_logic_vector(13 downto 0) := (others=>'0');
	signal qmfB : std_logic_vector(13 downto 0) := (others=>'0');
	signal qmfC : std_logic_vector(13 downto 0) := (others=>'0');
	signal enab1 : std_logic := '0';
	signal enab2 : std_logic := '0';
	signal enab3 : std_logic := '0';
	signal dcc1 : std_logic := '0';
	signal dcc2 : std_logic := '0';
	signal dcc3 : std_logic := '0';
	signal yn1 : std_logic_vector(15 downto 0);
	signal zr : std_logic_vector(30 downto 0);
	signal zz : std_logic_vector(15 downto 0);
	--
begin
	--quantisation multiplier factors
	--we need to multiply by PF (to complete transform) and divide by quantisation qstep (ie QP rescaled)
	--so we transform it PF/qstep(QP) to qmf/2^n and do a single multiply
	qmfA <=
		CONV_STD_LOGIC_VECTOR(13107,14) when ('0'&QP)=0 or ('0'&QP)=6 or ('0'&QP)=12 or ('0'&QP)=18 or ('0'&QP)=24 or ('0'&QP)=30 or ('0'&QP)=36 or ('0'&QP)=42 or ('0'&QP)=48 else
		CONV_STD_LOGIC_VECTOR(11916,14) when ('0'&QP)=1 or ('0'&QP)=7 or ('0'&QP)=13 or ('0'&QP)=19 or ('0'&QP)=25 or ('0'&QP)=31 or ('0'&QP)=37 or ('0'&QP)=43 or ('0'&QP)=49 else
		CONV_STD_LOGIC_VECTOR(10082,14) when ('0'&QP)=2 or ('0'&QP)=8 or ('0'&QP)=14 or ('0'&QP)=20 or ('0'&QP)=26 or ('0'&QP)=32 or ('0'&QP)=38 or ('0'&QP)=44 or ('0'&QP)=50 else
		CONV_STD_LOGIC_VECTOR(9362,14) when ('0'&QP)=3 or ('0'&QP)=9 or ('0'&QP)=15 or ('0'&QP)=21 or ('0'&QP)=27 or ('0'&QP)=33 or ('0'&QP)=39 or ('0'&QP)=45 or ('0'&QP)=51 else
		CONV_STD_LOGIC_VECTOR(8192,14) when ('0'&QP)=4 or ('0'&QP)=10 or ('0'&QP)=16 or ('0'&QP)=22 or ('0'&QP)=28 or ('0'&QP)=34 or ('0'&QP)=40 or ('0'&QP)=46 else
		CONV_STD_LOGIC_VECTOR(7282,14);
	qmfB <=
		CONV_STD_LOGIC_VECTOR(5243,14) when ('0'&QP)=0 or ('0'&QP)=6 or ('0'&QP)=12 or ('0'&QP)=18 or ('0'&QP)=24 or ('0'&QP)=30 or ('0'&QP)=36 or ('0'&QP)=42 or ('0'&QP)=48 else
		CONV_STD_LOGIC_VECTOR(4660,14) when ('0'&QP)=1 or ('0'&QP)=7 or ('0'&QP)=13 or ('0'&QP)=19 or ('0'&QP)=25 or ('0'&QP)=31 or ('0'&QP)=37 or ('0'&QP)=43 or ('0'&QP)=49 else
		CONV_STD_LOGIC_VECTOR(4194,14) when ('0'&QP)=2 or ('0'&QP)=8 or ('0'&QP)=14 or ('0'&QP)=20 or ('0'&QP)=26 or ('0'&QP)=32 or ('0'&QP)=38 or ('0'&QP)=44 or ('0'&QP)=50 else
		CONV_STD_LOGIC_VECTOR(3647,14) when ('0'&QP)=3 or ('0'&QP)=9 or ('0'&QP)=15 or ('0'&QP)=21 or ('0'&QP)=27 or ('0'&QP)=33 or ('0'&QP)=39 or ('0'&QP)=45 or ('0'&QP)=51 else
		CONV_STD_LOGIC_VECTOR(3355,14) when ('0'&QP)=4 or ('0'&QP)=10 or ('0'&QP)=16 or ('0'&QP)=22 or ('0'&QP)=28 or ('0'&QP)=34 or ('0'&QP)=40 or ('0'&QP)=46 else
		CONV_STD_LOGIC_VECTOR(2893,14);
	qmfC <=
		CONV_STD_LOGIC_VECTOR(8066,14) when ('0'&QP)=0 or ('0'&QP)=6 or ('0'&QP)=12 or ('0'&QP)=18 or ('0'&QP)=24 or ('0'&QP)=30 or ('0'&QP)=36 or ('0'&QP)=42 or ('0'&QP)=48 else
		CONV_STD_LOGIC_VECTOR(7490,14) when ('0'&QP)=1 or ('0'&QP)=7 or ('0'&QP)=13 or ('0'&QP)=19 or ('0'&QP)=25 or ('0'&QP)=31 or ('0'&QP)=37 or ('0'&QP)=43 or ('0'&QP)=49 else
		CONV_STD_LOGIC_VECTOR(6554,14) when ('0'&QP)=2 or ('0'&QP)=8 or ('0'&QP)=14 or ('0'&QP)=20 or ('0'&QP)=26 or ('0'&QP)=32 or ('0'&QP)=38 or ('0'&QP)=44 or ('0'&QP)=50 else
		CONV_STD_LOGIC_VECTOR(5825,14) when ('0'&QP)=3 or ('0'&QP)=9 or ('0'&QP)=15 or ('0'&QP)=21 or ('0'&QP)=27 or ('0'&QP)=33 or ('0'&QP)=39 or ('0'&QP)=45 or ('0'&QP)=51 else
		CONV_STD_LOGIC_VECTOR(5243,14) when ('0'&QP)=4 or ('0'&QP)=10 or ('0'&QP)=16 or ('0'&QP)=22 or ('0'&QP)=28 or ('0'&QP)=34 or ('0'&QP)=40 or ('0'&QP)=46 else
		CONV_STD_LOGIC_VECTOR(4559,14);
	--
process(CLK)
	variable rr : std_logic_vector(2 downto 0);
begin
	if rising_edge(CLK) then
		if ENABLE='0' or DCCI='1' then
			zig <= x"F";
		else
			zig <= zig - 1;
		end if;
		--
		enab1 <= ENABLE;
		enab2 <= enab1;
		enab3 <= enab2;
		VALID <= enab3;
		--
		dcc1 <= DCCI;
		dcc2 <= dcc1;
		dcc3 <= dcc2;
		DCCO <= dcc3;
		--
		if ENABLE='1' then
			if DCCI='1' then
				--dc uses 0,0 parameters div 2
				qmf <= '0'&qmfA(13 downto 1);
			elsif zig=0 or zig=3 or zig=5 or zig=11 then
				--positions 0,0; 0,2; 2,0; 2,2 need one set of parameters
				qmf <= qmfA;
			elsif zig=4 or zig=10 or zig=12 or zig=15 then
				--positions 1,1; 1,3; 3,1; 3,3 need another set of parameters
				qmf <= qmfB;
			else
				--other positions: default parameters
				qmf <= qmfC;
			end if;
			yn1 <= YNIN;	--data ready for scaling
		end if;
		if enab1='1' then
			zr <= yn1 * ('0'&qmf);		--quantise
		end if;
		--two bits of rounding (and leading zero)
		--rr := b"010";			--simple round-to-middle
		--rr := b"000";			--no rounding (=> -ve numbers round away from zero)
		rr := b"0"&zr(29)&'1';	--round to zero if <0.75
		if enab2='1' then
			if ('0'&QP) < 6 then
				zz <= zr(28 downto 13) + rr;
			elsif ('0'&QP) < 12 then
				zz <= zr(29 downto 14) + rr;
			elsif ('0'&QP) < 18 then
				zz <= zr(30 downto 15) + rr;
			elsif ('0'&QP) < 24 then
				zz <= sxt(zr(30 downto 16),16) + rr;
			elsif ('0'&QP) < 30 then
				zz <= sxt(zr(30 downto 17),16) + rr;
			elsif ('0'&QP) < 36 then
				zz <= sxt(zr(30 downto 18),16) + rr;
			elsif ('0'&QP) < 42 then
				zz <= sxt(zr(30 downto 19),16) + rr;
			else
				zz <= sxt(zr(30 downto 20),16) + rr;
			end if;
		end if;
		if enab3='1' then
			if zz(15)=zz(14) and zz(15)=zz(13) and zz(13 downto 2)/=x"800" then
				ZOUT <= zz(13 downto 2);
			elsif zz(15)='0' then
				ZOUT <= x"7FF";		--clip max
			else
				ZOUT <= x"801";		--clip min
			end if;
		end if;
	end if;
end process;
	--
end hw;

--#quantise


--#recon

entity design4 is
	port (
		CLK2 : in std_logic;				--x2 clock
		--
		-- in interface:
		NEWSLICE : in std_logic;			--reset
		STROBEI : in std_logic;				--data here
		DATAI : in std_logic_vector(39 downto 0);		--4x10bit
		BSTROBEI : in std_logic;				--base data here
		BCHROMAI : in std_logic;				--set if base is chroma
		BASEI : in std_logic_vector(31 downto 0);		--4x8bit
		--
		-- out interface:
		STROBEO : out std_logic := '0';				--data here (luma)
		CSTROBEO : out std_logic := '0';			--data here (chroma)
		DATAO : out std_logic_vector(31 downto 0) := (others => '0')
	);
end design4;

architecture hw of design4 is
	type Tbase is array(7 downto 0) of std_logic_vector(31 downto 0);
	signal chromaf : std_logic_vector(1 downto 0);
	signal basevec : Tbase := (others=>(others=>'0'));
	signal basex : std_logic_vector(31 downto 0);
	signal basein : std_logic_vector(3 downto 0) := b"0000";
	signal baseout : std_logic_vector(3 downto 0) := b"0000";
	signal byte0 : std_logic_vector(9 downto 0) := (others=>'0');
	signal byte1 : std_logic_vector(9 downto 0) := (others=>'0');
	signal byte2 : std_logic_vector(9 downto 0) := (others=>'0');
	signal byte3 : std_logic_vector(9 downto 0) := (others=>'0');
	signal strobex : std_logic := '0';
	signal chromax : std_logic := '0';
begin
	basex <= basevec(conv_integer(baseout(2 downto 0)));
	--
process(CLK2)
begin
	if rising_edge(CLK2) then
		if NEWSLICE='1' then	--reset
			basein <= b"0000";
			baseout <= b"0000";
		end if;
		--load in base
		if BSTROBEI='1' and NEWSLICE='0' then
			basevec(conv_integer(basein(2 downto 0))) <= BASEI;
			chromaf(conv_integer(basein(2))) <= BCHROMAI;
			basein <= basein + 1;
			assert basein+8 /= baseout report "basein wrapped";
		else
			assert basein(1 downto 0)=0 report "basein not aligned when strobe falls";
		end if;
		--reconstruct +0: add
		byte0 <= (b"00"&basex(7 downto 0))   + DATAI(9 downto 0);
		byte1 <= (b"00"&basex(15 downto 8))  + DATAI(19 downto 10);
		byte2 <= (b"00"&basex(23 downto 16)) + DATAI(29 downto 20);
		byte3 <= (b"00"&basex(31 downto 24)) + DATAI(39 downto 30);
		chromax <= chromaf(conv_integer(baseout(2)));
		strobex <= STROBEI;
		if STROBEI='1' and NEWSLICE='0' then
			baseout <= baseout + 1;
			assert baseout /= basein report "baseout wrapped";
		else
			assert baseout(1 downto 0)=0 report "baseout not aligned when strobe falls";
		end if;
		--reconstruct +1: clip to [0,255]
		if byte0(9 downto 8) = b"01" or byte0(9 downto 7) = b"100" then
			DATAO(7 downto 0) <= x"FF";
		elsif byte0(9) = '1' and byte0(9 downto 7) /= b"100" then
			DATAO(7 downto 0) <= x"00";
		else
			DATAO(7 downto 0) <= byte0(7 downto 0);
		end if;
		if byte1(9 downto 8) = b"01" or byte1(9 downto 7) = b"100" then
			DATAO(15 downto 8) <= x"FF";
		elsif byte1(9) = '1' and byte1(9 downto 7) /= b"100" then
			DATAO(15 downto 8) <= x"00";
		else
			DATAO(15 downto 8) <= byte1(7 downto 0);
		end if;
		if byte2(9 downto 8) = b"01" or byte2(9 downto 7) = b"100" then
			DATAO(23 downto 16) <= x"FF";
		elsif byte2(9) = '1' and byte2(9 downto 7) /= b"100" then
			DATAO(23 downto 16) <= x"00";
		else
			DATAO(23 downto 16) <= byte2(7 downto 0);
		end if;
		if byte3(9 downto 8) = b"01" or byte3(9 downto 7) = b"100" then
			DATAO(31 downto 24) <= x"FF";
		elsif byte3(9) = '1' and byte3(9 downto 7) /= b"100" then
			DATAO(31 downto 24) <= x"00";
		else
			DATAO(31 downto 24) <= byte3(7 downto 0);
		end if;
		STROBEO <= strobex and not chromax;
		CSTROBEO <= strobex and chromax;
	end if;	
end process;
	--
end hw;

--#recon


--#tobytes

entity design4 is
	port (
		CLK : in std_logic;					--pixel clock
		VALID : in std_logic;				--data ready to be read
		READY : out std_logic := '1';		--soft ready signal (can accept 40 more words when clear)
		VE : in std_logic_vector(24 downto 0) := (others=>'0');
		VL : in std_logic_vector(4 downto 0) := (others=>'0');
		BYTE : out std_logic_vector(7 downto 0) := (others=>'0');
		STROBE : out std_logic := '0';			--set when BYTE valid
		DONE : out std_logic := '0'				--set after aligned with DONE flag (end of NAL)
	);
end design4;

architecture hw of design4 is
	--
	type Tave is array(63 downto 0) of std_logic_vector(24 downto 0);
	type Tavl is array(63 downto 0) of std_logic_vector(4 downto 0);
	signal aVE : Tave;
	signal aVL : Tavl;
	signal ain : std_logic_vector(5 downto 0) := (others => '0');
	signal aout : std_logic_vector(5 downto 0) := (others => '0');
	signal adiff : std_logic_vector(5 downto 0) := (others => '0');
	signal VE1 : std_logic_vector(24 downto 0) := (others=>'0');
	signal VL1 : std_logic_vector(4 downto 0) := (others=>'0');
	--
	signal ptr : std_logic_vector(4 downto 0) := (others => '0');	--ptr, initally VL
	signal sel : std_logic_vector(2 downto 0) := (others => '0');	--part of VL
	signal vbuf : std_logic_vector(24 downto 0) := (others=>'0');	--initially VE
	signal bbuf : std_logic_vector(10 downto 0) := (others => '0');	--buffer for byte
	signal count : std_logic_vector(3 downto 0) := (others => '0');	--count of valid bits
	signal alignflg : std_logic := '0';
	signal doneflg : std_logic := '0';
	signal pbyte : std_logic_vector(7 downto 0) := (others => '0');	--output (pre stuffing)
	signal pstrobe : std_logic := '0';
	signal pzeros : std_logic_vector(1 downto 0) := (others => '0');
	signal vbufsel : std_logic_vector(3 downto 0) := (others=>'0');	--selection of vbuf
	signal pop : std_logic := '0';
	--
begin
	--
	vbufsel <=  vbuf(3 downto 0) when sel=0 else
				vbuf(7 downto 4) when sel=1 else
				vbuf(11 downto 8) when sel=2 else
				vbuf(15 downto 12) when sel=3 else
				vbuf(19 downto 16) when sel=4 else
				vbuf(23 downto 20) when sel=5 else
				b"000"&vbuf(24) when sel=6 else
				x"0";
	--
	adiff <= ain - aout;
	ready <= '1' when adiff < 24 else '0';
	pop <= '1' when ain/=aout and ptr<=4 and alignflg='0' else '0';
	VE1 <= aVE(conv_integer(aout));
	VL1 <= aVL(conv_integer(aout));
	--
process(CLK)
begin
	if rising_edge(CLK) then
		--fifo
		if VALID='1' then
			aVE(conv_integer(ain)) <= VE;
			aVL(conv_integer(ain)) <= VL;
			ain <= ain + 1;
			assert adiff /= 63 report "fifo overflow" severity ERROR;
		end if;
		if POP='1' then
			aout <= aout + 1;
		end if;
		--convert to bytes
		if ptr>0 then
			--process up to 4 bits
			if ptr(1 downto 0) = 0 then
				bbuf <= bbuf(6 downto 0) & vbufsel(3 downto 0);		--process 4 bits
				count <= ('0'&count(2 downto 0)) + 4;
			elsif ptr(1 downto 0) = 3 then
				bbuf <= bbuf(7 downto 0) & vbufsel(2 downto 0);		--process 3 bits
				count <= ('0'&count(2 downto 0)) + 3;
			elsif ptr(1 downto 0) = 2 then
				bbuf <= bbuf(8 downto 0) & vbufsel(1 downto 0);		--process 2 bits
				count <= ('0'&count(2 downto 0)) + 2;
			else --1
				bbuf <= bbuf(9 downto 0) & vbufsel(0);		--process 1 bit
				count <= ('0'&count(2 downto 0)) + 1;
			end if;
		else --nothing to process
			count(3) <= '0';	--keep low 3 bits, but this (the "available byte") clears
		end if;
		--
		if ptr<=4 and alignflg='1' then
			if ptr=0 and pstrobe='0' and count(3)='0' then
				count(2 downto 0) <= b"000";	--waste a cycle for alignment
				alignflg <= '0';
				DONE <= doneflg;
			else
				ptr <= b"00000";
			end if;
		elsif POP='1' then	--here to POP
			ptr <= VL1;
			vbuf <= VE1;
			alignflg <= VE1(16) and not VL1(4);	--if VL<16 and VE(16) set
			doneflg <= VE1(17) and not VL1(4);	--if VL<16 and VE(17) set
			if VL1(1 downto 0) = 0 then
				sel <= VL1(4 downto 2)-1;
			else
				sel <= VL1(4 downto 2);
			end if;
		else		--process stuff in register
			if ptr(1 downto 0) /= 0 then
				ptr(1 downto 0) <= b"00";
				sel <= ptr(4 downto 2)-1;
			elsif ptr/=0 then
				ptr(4 downto 2) <= ptr(4 downto 2)-1;
				sel <= ptr(4 downto 2)-2;
			end if;
		end if;
		--
		if count(3)='1' then
			if count(1 downto 0)=0 then
				pbyte <= bbuf(7 downto 0);
			elsif count(1 downto 0)=1 then
				pbyte <= bbuf(8 downto 1);
			elsif count(1 downto 0)=2 then
				pbyte <= bbuf(9 downto 2);
			else
				pbyte <= bbuf(10 downto 3);
			end if;
		end if;
		if pstrobe='1' and pzeros<2 and pbyte=0 then
			pzeros <= pzeros + 1;
		elsif pstrobe='1' then
			pzeros <= b"00";	--either because stuffed or non-zero
		end if;
		if pstrobe='1' and pzeros=2 and pbyte<4 then	
			BYTE <= x"03";			--stuff!!
			--leave pstrobe unchanged
		else
			BYTE <= pbyte;
			pstrobe <= count(3);
		end if;
		if alignflg='0' and doneflg='1' then
			DONE <= '0';
			doneflg <= '0';
		end if;
		STROBE <= pstrobe;
	end if;
end process;
	--
end hw;

--#tobytes

