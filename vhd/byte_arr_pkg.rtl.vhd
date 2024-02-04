library ieee, work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package byte_arr_pkg is
    
    subtype byte_t  is std_logic_vector(8-1 downto 0);
    type byte_arr_t is array(natural range<>) of byte_t;
    
    function to_slv(arr : byte_arr_t) return std_logic_vector ;
    function to_arr(slv : std_logic_vector ) return  byte_arr_t ;
    function reverse(arr_i : byte_arr_t) return  byte_arr_t ;

end package byte_arr_pkg;
    
package body byte_arr_pkg is
  function to_slv(arr : byte_arr_t) return std_logic_vector is
    variable slv : std_logic_vector((arr'length * 8) - 1 downto 0);
  begin
    for i in arr'range loop
      slv((i * 8) + 7 downto (i * 8)):= arr(i);
    end loop;
    return slv;
  end function;

  function to_arr(slv : std_logic_vector ) return  byte_arr_t is
      variable arr : byte_arr_t(slv'length/8-1 downto 0);
  begin
    for i in arr'range loop
      arr(i) := slv((i * 8) + 7 downto (i * 8));
    end loop;
    return arr;
  end function;

  function reverse(arr_i : byte_arr_t) return  byte_arr_t is
    variable arr_o : byte_arr_t(arr_i'range);
  begin
    for i in arr_i'range loop
      arr_o(i) := arr_i(arr_i'high - i);
    end loop;
    return arr_o;
  end function;

end package body byte_arr_pkg;
