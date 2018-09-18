-------------------------------------------------
-- 2:4 Decoder (ESD figure 2.5)
-- by Weijun Zhang, 04/2001
--
-- decoder is a kind of inverse process
-- of multiplexor
-------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

-------------------------------------------------

entity design2_design2 is
port(	I:	in std_logic_vector(1 downto 0);
	O:	out std_logic_vector(3 downto 0)
);
end design2_design2;

-------------------------------------------------

architecture behv of design2_design2 is
begin

    -- process statement

 -- process statement
    
--#design2

    O <= 	"0001" when I = "00" else
		"0010" when I = "01" else
		"0100" when I = "10" else
		"1000" when I = "11" else
		"XXXX";
  
  
--#design2
	
  
	    
    
    
	
end behv;



--------------------------------------------------
