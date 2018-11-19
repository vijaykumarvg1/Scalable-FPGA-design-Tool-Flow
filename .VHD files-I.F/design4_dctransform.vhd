

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use ieee.numeric_std.ALL;










--#dctransform


entity design4_dctransform is
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
end design4_dctransform;

architecture hw of design4_dctransform is
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


















