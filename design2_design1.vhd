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

entity design2_design1 is
port(	I:	in std_logic_vector(1 downto 0);
	O:	out std_logic_vector(3 downto 0)
);
end design2_design1;

-------------------------------------------------

architecture behv of design2_design1 is
begin

    -- process statement
--#design1
    process (I)
    begin
    
        -- use case statement 

        case I is
	    when "00" => O <= "0001";
	    when "01" => O <= "0010";
	    when "10" => O <= "0100";
	    when "11" => O <= "1000";
	    when others => O <= "XXXX";
	end case;

    end process;
--#design1

 -- process statement
    
	
  
	    
    
    
	
end behv;



--------------------------------------------------
