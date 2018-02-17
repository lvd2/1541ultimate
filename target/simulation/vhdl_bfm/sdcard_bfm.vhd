-------------------------------------------------------------------------------
--
-- (C) COPYRIGHT Gideon's Logic Architectures
--
-------------------------------------------------------------------------------
-- Title      : sdcard_bfm
-- Author     : Gideon Zweijtzer <gideon.zweijtzer@gmail.com>
-------------------------------------------------------------------------------
-- Description: Primitive BFM of SD card
-------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
use work.tl_string_util_pkg.all;
    
library work;
    use work.sdcard_pkg.all;

entity sdcard_bfm is
port (
    clock           : in  std_logic;
    ss_n            : in  std_logic;
    mosi            : in  std_logic;
    miso            : out std_logic );

end entity;

architecture gideon of sdcard_bfm is
    signal input_byte   : std_logic_vector(7 downto 0);
    signal input_dav    : std_logic;
    
    shared variable output_message  : t_sdrom_array(0 to 1023);
    shared variable output_length   : natural := 0;
    shared variable output_pointer  : natural := 0;
    shared variable output_busy     : boolean := false;

    impure function get_byte return std_logic_vector is
        variable ret    : std_logic_vector(7 downto 0);
    begin
        if output_pointer >= output_length then
            output_busy := false;
        end if;
        if not output_busy then
            output_pointer := 0;
            return X"FF";
        end if;
        ret := output_message(output_pointer);
        output_pointer := output_pointer + 1;
        if output_pointer >= output_length then
            output_busy := false;
            output_pointer := 0;
        end if;
        return ret;        
    end function;

    type t_state is (idle, param1, param2, param3, param4, crc, reply);
    signal state    : t_state := idle;
    signal command  : std_logic_vector(7 downto 0) := X"00";
    signal param_x  : std_logic_vector(15 downto 0) := X"0000"; 
    signal param_y  : std_logic_vector(15 downto 0) := X"0000"; 

    procedure execute_command(command : std_logic_vector(7 downto 0); param_x, param_y : std_logic_vector(15 downto 0)) is
    begin
        output_pointer := 0;
        case command is
        when X"00" | X"37" => -- reset, ACMD55
            output_message(0 to 2) := (X"FF", X"FF", X"01");
            output_length := 3;
            output_busy := true;
        when X"29" =>
            output_message(0 to 2) := (X"FF", X"FF", X"00");
            output_length := 3;
            output_busy := true;
        when X"3A" =>
            output_message(0 to 6) := (X"FF", X"FF", X"00", X"40", X"F8", X"00", X"00");
            output_length := 7;
            output_busy := true;
        when X"08" =>
            output_message(0 to 2) := (X"FF", X"FF", X"01");
            output_message(3) := param_x(15 downto 8);                
            output_message(4) := param_x(7 downto 0);                
            output_message(5) := param_y(15 downto 8);                
            output_message(6) := param_y(7 downto 0);
            output_length := 7;
            output_busy := true;
        when X"09" | X"0A" =>
            output_message(0 to 2) := (X"FF", X"FF", X"FE");
            output_message(3 to 15+3) := (X"00", X"01", X"02", X"03", X"04", X"05", X"06", X"07",
                                          X"08", X"09", X"0A", X"0B", X"0C", X"0D", X"0E", X"0F" );
            output_length := 19;
            output_busy := true;

        when X"11" => -- read block
            output_message(0 to 2) := (X"00", X"FF", X"FE");
            case param_y is
            when X"0000" =>
                output_message(3 to 511+3) := sector0;
            when X"2000" =>
                output_message(3 to 511+3) := sector8192;
            when others =>
                output_message(3 to 511+3) := (others => X"00");
            end case;
            output_length := 512 + 3;
            output_busy := true;                            
        when others =>
            report "Unknown command " & hstr(command);
        end case;
    end procedure;
begin
    process(clock, ss_n)
        variable bit_cnt : natural := 0;
        variable out_byte   : std_logic_vector(7 downto 0) := X"FF";
        variable input_data : std_logic_vector(7 downto 0) := X"FF";
    begin
        if falling_edge(ss_n) then
            bit_cnt := 7;
            input_dav <= '0';
            out_byte := get_byte;
            miso <= out_byte(7);
            out_byte := out_byte(6 downto 0) & '1';
        end if;            
                        
        if rising_edge(clock) then
            input_data(bit_cnt) := mosi;
            input_dav <= '0';
            if bit_cnt = 0 then
                input_dav  <= '1';
                input_byte <= input_data;
                bit_cnt := 7;
            else
                bit_cnt := bit_cnt - 1;
            end if; 
        end if;
        if falling_edge(clock) then
            miso <= out_byte(7);         
            out_byte := out_byte(6 downto 0) & '1';
        end if;
    end process;
    

    process(input_dav, input_byte) 
    begin
        if rising_edge(input_dav) then
            case state is
            when idle =>
                if input_byte(7 downto 6) = "01" then
                    command(5 downto 0) <= input_byte(5 downto 0);
                    state <= param1;
                end if;
            when param1 =>
                param_x(15 downto 8) <= input_byte;
                state <= param2;
            when param2 =>
                param_x(7 downto 0) <= input_byte;
                state <= param3;
            when param3 =>
                param_y(15 downto 8) <= input_byte;
                state <= param4;
            when param4 =>
                param_y(7 downto 0) <= input_byte;
                state <= crc;
            when crc =>
                execute_command(command, param_x, param_y);
                state <= idle;
            when reply =>
                if not output_busy then
                    state <= idle;
                end if;
            when others =>
                null;                                
            end case;                                
        end if; 
    end process;
end architecture;