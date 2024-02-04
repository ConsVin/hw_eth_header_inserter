
-- eth_header_tb

library ieee, work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity eth_header_tb is
end entity eth_header_tb;

architecture bhv of eth_header_tb is
  constant C_TEST_LENGTH  : integer := 1000;
  constant C_DST_MAC      : std_logic_vector(47 downto 0) := x"ABCDEF123456";
  constant C_SRC_MAC      : std_logic_vector(47 downto 0) := x"123456ABCDEF";
  constant C_ETH_TYPE     : std_logic_vector(15 downto 0) := x"0800";

  signal clk              : std_logic := '0';
  signal rst              : std_logic := '1';
  signal data_in          : std_logic_vector(63 downto 0) := (others => '0');
  signal data_in_valid    : std_logic := '0';
  signal data_in_last     : std_logic := '0';
  signal data_in_keep     : std_logic_vector(7 downto 0) := (others => '0');
  signal data_out         : std_logic_vector(63 downto 0);
  signal data_out_valid   : std_logic;
  signal data_out_last    : std_logic;
  signal data_out_keep    : std_logic_vector(7 downto 0);

begin
  ----------------------------
  -- my tb logic
  ----------------------------
  my_tb : entity work.my_tb
    generic map (
      TEST_LEN  => C_TEST_LENGTH,
      DST_MAC   => C_DST_MAC,
      SRC_MAC   => C_SRC_MAC,
      ETH_TYPE  => C_ETH_TYPE
    )
    port map (
      clk_o               => clk,
      rst_o               => rst,
      data_in             => data_in,
      data_in_valid       => data_in_valid,
      data_in_last        => data_in_last,
      data_in_keep        => data_in_keep,
      data_out            => data_out,
      data_out_valid      => data_out_valid,
      data_out_last       => data_out_last,
      data_out_keep       => data_out_keep
    );

  ----------------------------
  -- DUT
  ----------------------------
  dut : entity work.eth_header
    generic map (
      DST_MAC   => C_DST_MAC,
      SRC_MAC   => C_SRC_MAC,
      ETH_TYPE  => C_ETH_TYPE
    )
    port map (
      clk                 => clk,
      rst                 => rst,
      data_in             => data_in,
      data_in_valid       => data_in_valid,
      data_in_last        => data_in_last,
      data_in_keep        => data_in_keep,
      data_out            => data_out,
      data_out_valid      => data_out_valid,
      data_out_last       => data_out_last,
      data_out_keep       => data_out_keep
    );

end architecture bhv;

