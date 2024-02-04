-------------------------------------------------------------------
--                        eth_header
-------------------------------------------------------------------
-- 
--      Insert Ethernet Header to recieved payload packet
--      No input or output backpressure
--      Payload length can be any number from 1 byte
--   
--          Iput Packet           
--  ----------------------------------
--  |  D0 | D1 | D2|  D3 | ??? |  DN |
--  ----------------------------------
--  |        packet_len              |
--  ----------------------------------
-- 
--          Output Packet           
--  -----------------------------------------------------------------
--  | MAC_DST | MAC_SRC | ETH_TYPE |  D0 | D1 | D2|  D3 | ??? |  DN |
--  ----------------------------------------------------------------
--  |  6B     |  6B     |  2B     |           packet_len            |
--  -----------------------------------------------------------------
-- 
--                     +------------+
--                     |            |
--  == AXI_STREAM ===> | eth_header | == AXI_STREAM ===>
--                     |            |       
--                     +------------+       
                                            
library ieee, work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library ieee, work;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Import utility functions and datatypes
use work.byte_arr_pkg.all;

entity eth_header is
  generic (
      DST_MAC           : std_logic_vector(8*6 -1 downto 0) := x"12345678ABCD" 
                                                   -- Equivalent 12:34:56:78:AB:CD
    ; SRC_MAC           : std_logic_vector(8*6 -1 downto 0) := x"FF33221100EE"
    ; ETH_TYPE          : std_logic_vector(8*2 -1 downto 0) := x"04D2"
  );
  port (
    clk                     : in  std_logic;
    rst                     : in  std_logic;

    data_in_tdata           : in  std_logic_vector(63 downto 0);
    data_in_tvalid          : in  std_logic;
    data_in_tlast           : in  std_logic;
    data_in_tkeep           : in  std_logic_vector(7 downto 0);

    data_out_tdata          : out std_logic_vector(63 downto 0);
    data_out_tvalid         : out std_logic;
    data_out_tlast          : out std_logic;
    data_out_tkeep          : out std_logic_vector(7 downto 0)

  );
end entity eth_header;

architecture rtl of eth_header is
  -- Utility function
  function or_reduce(a : std_logic_vector) return std_logic is
    variable ret : std_logic := '0';
  begin
    for i in a'range loop
        ret := ret or a(i);
    end loop;
    return ret;
  end function or_reduce;

  -- Represent MAC addresses and EtherType as bytes  
  signal w_dst_mac, 
         w_src_mac   : byte_arr_t(6-1 downto 0);
  signal w_type      : byte_arr_t(2-1 downto 0);  
  -- Same for the data
  signal w_in_tdata,
         w_out_tdata   : byte_arr_t(8-1 downto 0);
  signal w_out_tvalid : std_logic;

  signal first_word : std_ulogic;
  
  type buf_arr_t is array(natural range<>) of byte_arr_t(8-1 downto 0);
  subtype tkeep_t  is std_logic_vector(data_in_tkeep'range);
  signal w_out_tkeep : tkeep_t;
  type tkeep_arr_t is array(natural range<>) of tkeep_t;
  
  signal  data_arr  :        buf_arr_t(3-1 downto 0) := (others=>(others=>(others=>'0')));
  signal  keep_arr :       tkeep_arr_t(3-1 downto 0);
  
  -- Control signals
  signal packet_end_sent: std_logic;
  signal packet_start_rx, packet_start_rx_d0, packet_start_rx_d1: std_logic;
  signal first_word_d: std_logic;
  signal shift_buf : std_logic;
  signal  data_in_tvalid_d0,
          data_in_tvalid_d1,
          w_out_tlast : std_logic;

  signal  i_last_d0,
          i_last_d1,
          i_last_d2 : std_logic;
  signal extra_last : std_logic;
begin
    -- Reverse byte-order
    w_dst_mac  <= reverse(to_arr( DST_MAC));
    w_src_mac  <= reverse(to_arr( SRC_MAC));
    w_type     <= reverse(to_arr( ETH_TYPE));
    --
    w_in_tdata <= to_arr(data_in_tdata);

    packet_start_rx <= (data_in_tvalid ) and (first_word);

    process(clk)
    begin 
         if(rising_edge(clk)) then
          packet_start_rx_d0 <= packet_start_rx;
          packet_start_rx_d1 <= packet_start_rx_d0;

          data_in_tvalid_d0 <= data_in_tvalid;
          data_in_tvalid_d1 <= data_in_tvalid_d0;

          i_last_d0 <= data_in_tlast;
          i_last_d1 <= i_last_d0;
          i_last_d2 <= i_last_d1;


          if (packet_start_rx='1') then
            first_word_d <= '0';
          elsif (packet_end_sent = '1') then
            first_word_d <= '1';
          end if;
          if (rst = '1') then
            first_word_d <= '1';
          end if;
      end if;
    end process;
      --      RX valid     __/***\___/*********\_____________
      --      RX  last     ________________/***\_____________
      --      TX valid     ______/*********\___/*********\___
      --      RX  last     __________________________/***\___
      
      --      first_word_d ******\___________________/*******
      --                         |                    | Set back to 1 at the end of TX
      --                         |
      --                         | Drop to 0 at start of rx
      first_word      <=  packet_end_sent OR first_word_d;

  shift_buf <= data_in_tvalid  OR data_in_tvalid_d0  OR data_in_tvalid_d1;
  process(clk)
  begin 
     if(rising_edge(clk)) then
        if (packet_start_rx='1') then -- First word arrived, so inject header values
          -- Header [0] word
          data_arr(0)(8-1 downto 2) <= w_dst_mac(6-1 downto 0);
          data_arr(1)(2-1 downto 0) <= w_src_mac(2-1 downto 0);
          data_arr(1)(6-1 downto 2) <= w_src_mac(6-1 downto 2);
          data_arr(1)(8-1 downto 6) <= w_type;

          keep_arr(0)(8-1 downto 2) <= (others=>'1');
          keep_arr(1)(2-1 downto 0) <= (others=>'1');
          keep_arr(1)(6-1 downto 2) <= (others=>'1');
          keep_arr(1)(8-1 downto 6) <= (others=>'1');

          data_arr(2)  <= w_in_tdata;
          keep_arr(2)  <= data_in_tkeep;
        elsif (shift_buf = '1') then
          keep_arr(2-1 downto 0)  <= keep_arr(3-1 downto 1);
          data_arr(2-1 downto 0)  <= data_arr(3-1 downto 1);
          data_arr(2)  <= w_in_tdata;
          keep_arr(2)  <= data_in_tkeep;
        end if;
        -- Output Valid logic
          if (i_last_d0 = '1') then
            if (or_reduce(keep_arr(2)(8-1 downto 2)) = '0') then
              extra_last <= '0';
            else
                extra_last <= '1';
            end if;
          end if;
        w_out_tvalid <= data_in_tvalid_d0 OR packet_start_rx;

      if (rst = '1') then
          -- Drop control signals only 
          -- keep_arr is used to produce valid, so also need to be cleared
          keep_arr     <=(others=>(others=>'0'));
          extra_last <= '0';
      end if;
     end if;       
  end process; 
  w_out_tlast  <= i_last_d2 when extra_last='1' else  i_last_d1;

  -- Output interface is directly taken from output buffer
  w_out_tdata(6-1 downto 0)  <=  data_arr(0)(8-1 downto 2);
  w_out_tdata(8-1 downto 6)  <=  data_arr(1)(2-1 downto 0);
  w_out_tkeep(6-1 downto 0)  <=  keep_arr(0)(8-1 downto 2);
  w_out_tkeep(8-1 downto 6)  <=  (others=>'0') 
                                when ((w_out_tlast ='1') and (extra_last='1')) else keep_arr(1)(2-1 downto 0) ;
  
  data_out_tdata     <= to_slv( w_out_tdata);
  data_out_tkeep     <= w_out_tkeep;--  when w_out_tlast='1' else (others=>'1');
  data_out_tlast     <=   w_out_tlast; 
  data_out_tvalid    <=   w_out_tvalid OR w_out_tlast;
  packet_end_sent    <= w_out_tlast;

  -- Optional section, signals are accessed from cocotb
  -- These signals will be pruned on synthethis
  DBG: block
    signal rx_pkt_cnt : integer := 0;
    
    signal c_dst_mac   : std_logic_vector(8*6 -1 downto 0) := DST_MAC;
    signal c_src_mac   : std_logic_vector(8*6 -1 downto 0) := SRC_MAC;
    signal c_eth_type  : std_logic_vector(8*2 -1 downto 0) := ETH_TYPE;

    begin
      process(clk)
      begin 
        if(rising_edge(clk)) then
          if (w_out_tlast ='1') then
            rx_pkt_cnt <= rx_pkt_cnt + 1;
          end if;
          if (rst = '1') then
            rx_pkt_cnt <= 0;
          end if;
        end if;
      end process;
    end block DBG;

end architecture rtl;
