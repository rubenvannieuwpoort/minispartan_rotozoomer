library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_gen is
	port (
		clk75   : in  std_logic;
		pclk    : out std_logic;
		red	  : out std_logic_vector (7 downto 0) := (others => '0');
		green   : out std_logic_vector (7 downto 0) := (others => '0');
		blue    : out std_logic_vector (7 downto 0) := (others => '0');
		blank   : out std_logic := '0';
		hsync   : out std_logic := '0';
		vsync   : out std_logic := '0'
	);
end vga_gen;

architecture Behavioral of vga_gen is
	constant width             : natural := 1280;
	constant halfwidth         : signed  := to_signed(640, 25);
	constant minushalfwidth    : signed  := to_signed(-640, 25);
	constant width_sync_start  : natural := 1280 + 72;
	constant width_sync_end	   : natural := 1280 + 80;
	constant width_max		   : natural := 1647;
	
	constant height		      : natural := 720;
	constant halfheight        : signed  := to_signed(360, 25);
	constant minushalfheight   : signed  := to_signed(-360, 25);
	constant height_sync_start : natural := 720 + 3;
	constant height_sync_end	: natural := 720 + 3 + 5;
	constant height_max		   : natural := 720 + 29;
	
	constant offset            : natural := 127 * 16384; -- offset to center the image: half times texture size times 2^frac_bits
	constant int_bits          : natural := 12;
	constant frac_bits         : natural := 14;
	constant total_bits        : natural := int_bits + frac_bits;
	constant tex_bits          : natural := 8;
	constant data_width        : natural := 8;
	
	
	signal x, xx        : unsigned(11 downto 0) := (others => '0');
	signal counter      : unsigned(8 downto 0) := (others => '0');
	signal y, yy        : unsigned(11 downto 0) := (others => '0');
	signal u, v, yu, yv : signed(total_bits - 1 downto 0) := (others => '0');
	signal sin, cos     : signed(2 + frac_bits - 1 downto 0);
	signal Y_next       : std_logic_vector(7 downto 0);
	signal UV_next      : std_logic_vector(15 downto 0);
	signal y_address    : std_logic_vector(15 downto 0);
	signal uv_address   : std_logic_vector(13 downto 0);	
	
	component texture_y_lut is port(clk: std_logic; address: in std_logic_vector(15 downto 0); data: out std_logic_vector(7 downto 0)); end component;
	component texture_uv_lut is port(clk: std_logic; address: in std_logic_vector(13 downto 0); data: out std_logic_vector(15 downto 0)); end component;
	component lut is
		generic(frac_bits: natural; lut_size: natural);
		port(angle: in unsigned(8 downto 0); sin: out signed(frac_bits + 2 - 1 downto 0); cos: out signed(frac_bits + 2 - 1 downto 0));
	end component;

begin
	pclk <= clk75;
	triglut: lut generic map(frac_bits => frac_bits, lut_size => 512) port map(angle => counter, sin => sin, cos => cos); 
	
	y_address <= std_logic_vector(v(frac_bits + tex_bits - 1 downto frac_bits) & u(frac_bits + tex_bits - 1 downto frac_bits));
	uv_address <= std_logic_vector(v(frac_bits + tex_bits - 1 downto frac_bits + 1) & u(frac_bits + tex_bits - 1 downto frac_bits + 1));
	texture_y : texture_y_lut port map(clk => clk75, address => y_address, data => Y_next);
	texture_uv: texture_uv_lut port map(clk => clk75, address => uv_address, data => UV_next);
	
process(clk75)
		variable col_Y : unsigned(15 downto 0);
		variable col_U, col_V : unsigned(15 downto 0);
		variable bigred, biggreen, bigblue : std_logic_vector(16 downto 0);
	begin
		
		if rising_edge(clk75) then
			xx <= x;
			yy <= y;
			
			col_Y := resize(unsigned(Y_next), 16) sll 8;
			col_U := unsigned("00000000" & UV_next(15 downto 8));
			col_V := unsigned("00000000" & UV_next( 7 downto 0));
			
			if xx < width and yy < height then
				blank <= '0';
				
				if u(total_bits - 1 downto frac_bits + tex_bits) /= 0 or v(total_bits - 1 downto frac_bits + tex_bits) /= 0 then
					red <= (others => '1');
					green <= (others => '1');
					blue <= (others => '1');
				else
					bigred := std_logic_vector(resize(col_Y + (col_U - 127) * 340, 17));
					if bigred(16) = '1' then red <= (others => not(bigred(15))); else red <= bigred(15 downto 8); end if;
					
					biggreen := std_logic_vector(resize(col_Y + (col_V - 127) * 340, 17));
					if biggreen(16) = '1' then green <= (others => not(biggreen(15))); else green <= biggreen(15 downto 8); end if;
					
					bigblue := std_logic_vector(resize(col_Y - (col_U - 127) * 340 - (col_V - 127) * 340, 17));
					if bigblue(16) = '1' then blue <= (others => not(bigblue(15))); else blue <= bigblue(15 downto 8); end if;
					
				end if;
			else
				blank <= '1';
				red	<= (others => '0');
				green <= (others => '0');
				blue  <= (others => '0');
			end if;
			
			if xx >= width_sync_start and xx < width_sync_end then hsync <= '1'; else hsync <= '0'; end if;
			if yy >= height_sync_start and yy < height_sync_end then vsync <= '1'; else vsync <= '0'; end if;
			if x = width_max then
				x <= (others => '0');
				if y = height_max then
					y <= (others => '0');
					counter <= counter + 1;
					yu <= to_signed(to_integer(cos * minushalfwidth) + to_integer(sin * minushalfheight) + offset, total_bits);
					yv <= to_signed(to_integer(sin * halfwidth) + to_integer(cos * minushalfheight) + offset, total_bits);
					u <= to_signed(to_integer(cos * minushalfwidth) + to_integer(sin * minushalfheight) + offset, total_bits);
					v <= to_signed(to_integer(sin * halfwidth) + to_integer(cos * minushalfheight) + offset, total_bits);
				else
					yu <= yu + sin;
					yv <= yv + cos;
					u <= yu + sin;
					v <= yv + cos;
					y <= y + 1;
				end if;
			else
				x <= x + 1;
				u <= u + cos;
				v <= v - sin;
			end if;
		end if;
	end process;
end Behavioral;
