-- sdvideo.lua : Conversion fichier video en fichier sd-drive
--
-- Version $Version$ $Date$ par Samuel DEVULDER 
--
-- Ici la résolution est plus fine que dans conv_sd.lua (de 320x200
-- N/B à 80x66 avec 216 couleurs.) Les fichiers vidéo sont en partie
-- différents entre les gammes d'ordinateurs thomson. Reférez vous au
-- README.html pour avoir tous les détails.
--
-- Le son joue à 5.9 kHz.
--
-- Variables d'environnement:
-- ==========================
--
-- FPS=<nombre d'images par secondes souhaité>
--    La taille écran s'ajuste pour maintenir le débit souhaité si la
--    vidéo est complexe. Si en revanche elle est simple, le débit
--    peut dépasser celui souhaité pour amméliorer la fluidité.
--
--    Si l'on indique une valeur négative, le débit souhaité sera la
--    valeur absolue de ce nombre. Si la vidéo est complexe et que le 
--    débit de la carte SD ne permet pas d'encoder la vidéo, la taille
--    de l'image ne sera pas réduite. En revanche le débit sera réduite
--    par rapport à celui souhaité.
--
--    Avec le débit de la carte SD dans SD-drive, la valeur de 11
--    images/secondes est un bon compromis. C'est la valeur par défaut.
--
-- MODE=0..22 (défaut: 7)
--    Mode de sortie. Regardez le README.html pour les détails.
--
-- Work in progress!
-- =================
-- De nouveaux modes peuvent apparaitre et d'anciens disparaitre.
-- Le code doit être nettoye et rendu plus amical pour l'utilisateur.
--
-- Travail débuté en Oct 2018.

-- ===========================================================================
-- helper functions
if not unpack then unpack = table.unpack end
local function round(x)
	return math.floor(x+.5)
end
local function exists(file)
   local ok, err, code = file and os.rename(file, file)
   if not ok then
      if code == 13 then
         -- Permission denied, but it exists
         return true
      end
   end
   return ok, err
end
local function isdir(file)
	return exists(file..'/')
end
local function env(var, default)
	return loadstring('return ' .. (os.getenv(var) or default))();
end
local function locate(file,...)
	-- look locally
	local pwd = arg[0]:match("(.*[/\\])") or ''
	for _,ext in ipairs{'','.exe'} do
		for _,sep in ipairs{'\\','/'} do
			for _,root in ipairs{pwd, pwd .. '..' .. sep} do
				for _,dir in ipairs{'', ...} do
					dir = dir=='' and dir or dir..sep
					local tmp = root .. dir .. file .. ext
					if exists(tmp) then return tmp end
				end
			end
		end
	end
	-- else try if system knows about the file
	local IN = io.popen('which ' .. file, 'r')
	if IN then
		local found, line
		for line in IN:lines() do
			if not line:match(" ") then found = line end
		end	
		IN:close()
		if found then return found end
	end
	error('Cannot locate "' .. file .. '"')
end

-- ===========================================================================
-- utiliser un fps<0 si la taille 100% doit etre conservee
local MODE          = env('MODE',7)
local FPS           = env('FPS',13)
-- MODE=21

local FFMPEG        = locate('ffmpeg', 'tools')
local YT_DL         = locate('yt-dlp', 'tools')
local BIN           = locate('bin/')

local POPEN_READBIN = FFMPEG:match(".*%.exe") and "rb" or "r"

-- constants
local CYCLES        = 169 -- CYCLES per audio sample
local FPS_MAX       = 30
local FILTER_DEPTH  = 2
local FILTER_THRES  = 0.005*0 + .02*0 + .03*0 + 1/24*0 + 1/48
local FILTER_ALPHA  = env('ALPHA',0)
local EXPONENTIAL   = true
local ZIGZAG        = true
local BUFFER_SIZE   = 4096
local CONFIG        = nil
-- local GRAY_R		= 0.30
-- local GRAY_G		= 0.59
-- local GRAY_B		= 0.11
local GRAY_R		= 0.2126
local GRAY_G		= 0.7152
local GRAY_B		= 0.0722

-- ===========================================================================

local function percent(x)
    -- convert x in 0..1+ to 0..100
    return round(math.min(1,x)*100)
end
local function hms(secs, fmt)
    -- return a formated version of secs seconds (fmt is optional)
    secs = round(secs)
    return string.format(fmt or "%d:%02d:%02d",
            math.floor(secs/3600), math.floor(secs/60)%60, math.floor(secs)%60)
end
function basename(file)
    return file:gsub('^/cygdrive/(%w)/','%1:/'):gsub('.*[/\\]',''):gsub('%.[%a%d]+','')
end

-- ===========================================================================
-- dithering helpers
local function bayer(t)
    local m=#t
    local n=#t[1]
    local d={}
    for i=1,2*m do
        d[i] = {}
        for j=1,2*n do
            d[i][j] = 0
        end
    end
    for i=1,m do
        for j=1,n do
            local z = 4*t[i][j]
            d[m*0+i][n*0+j] = z-3
            d[m*1+i][n*1+j] = z-2
            d[m*1+i][n*0+j] = z-1
            d[m*0+i][n*1+j] = z-0
        end
    end
    return d
end
local function vac(n,m)
    math.randomseed(os.time())
    local function mat(w,h)
        local t={}
        for i=1,h do
            local r={}
            for j=1,w do
                table.insert(r,0)
            end
            table.insert(t,r)
        end
        t.mt={}
        setmetatable(t, t.mt)
        function t.mt.__tostring(t)
            local s,f='',0
			for i=1,#t do for j=1,#t[1] do
				local x = t[i][j]
				x = x-math.floor(x)
				if x>f then f=x end
			end end
			f = f>0 and "%9.6f" or "%3d"
            for i=1,#t do
                for j=1,#t[1] do
                    if j>1 then s=s..',' end
                    s = s..string.format(f,t[i][j])
                end
                s = s..'\n'
            end
            return s
        end
        return t
    end
    local function rangexy(w,h)
        local l = {}
        for y=1,h do
            for x=1,w do
                table.insert(l,{x,y})
            end
        end
        local size = #l
        for i = size, 2, -1 do
            local j = math.random(i)
            l[i], l[j] = l[j], l[i]
        end
        local i=0
        return function()
            i = i + 1
            if i<=size then
                -- print(i, l[i][1], l[i][2]    )
                return l[i][1], l[i][2]
            else
                -- print("")
            end
        end
    end
    local function makegauss(w,h)
        local w2 = math.ceil(w/2)
        local h2 = math.ceil(h/2)
        local m = mat(w,h)
        for x,y in rangexy(w, h) do
            -- local i = x-1-(w-1)/2
            -- local j = y-1-(h-1)/2
			local i = x-1-math.floor(w/2)
            local j = y-1-math.floor(h/2)           
            -- local i = x-w2-.5
            -- local j = y-h2-.5
			
            -- m[y][x] = math.exp(-40*(i^2+j^2)/(w*h))
			-- local i = ((x-1+w2)%w)/w2-1  -- -1..1
            -- local j = ((y-1+h2)%h)/h2-1  -- -1..1
			
			i,j = i*CONFIG.px_size[1],j*CONFIG.px_size[2]
			-- print(x,y,'-->',i,j)
			m[((y-1+h2)%h)+1][((x-1+w2)%w)+1] = math.exp(-(i^2+j^2)/(2*1.5^2))
			
			-- i,j = i*3,j*3 -- i*3*CONFIG.px_size[2],j*3*CONFIG.px_size[1]
            -- m[y][x] = .01/((i^2+j^2)+.01)
		end
        -- print(m)
        return m
    end
    local function countones(m)
        local t=0
        for _,l in ipairs(m) do
            for _,x in ipairs(l) do
                if x>0.5 then t=t+1 end
            end
        end
        return t
    end
    local GAUSS = makegauss(n,m)
    local function getminmax(m, c)
        local min,max,max_x,max_y,min_x,min_y=1e38,0
        local h,w = #m, #m[1]
        local z = mat(w,h)
        for x,y in rangexy(w,h) do
            if math.abs(m[y][x]-c)<0.5 then
                local t=0
                for i,j in rangexy(w,h) do
                    if m[1+((y+j-2)%h)][1+((x+i-2)%w)]>0.5 then
                        t = t + GAUSS[j][i]
                    end
                end
                z[y][x] = t
                if t>max then max,max_x,max_y = t,x,y end
                if t<min then min,min_x,min_y = t,x,y end
            end
        end
        -- print(m)
        -- print(z)
        -- print(max,max_y,max_x, c)
        -- print(min,min_y,min_x)
        return min_x, min_y, max_x, max_y
    end
    local function makeuniform(n,m)
        local t = mat(n,m)
        for i=0,math.min(m,n)-1 do -- math.floor(m*n/10) do
            t[math.random(m)][math.random(n)] = 1
        end
        for i=1,m*n*100 do
            local a1,b1,x1,y1 = getminmax(t,1)
            t[y1][x1] = 0
            local x2,y2,a2,b2 = getminmax(t,0)
            t[y2][x2] = 1
            -- print(t)
            if x1==x2 and y1==y2 then break end
        end
        return t
    end

    local vnc = mat(n,m)
    local m2  = mat(n,m)
    local m1  = makeuniform(n,m)
    local rank = countones(m1)
    for x,y in rangexy(n,m) do m2[y][x] = m1[y][x] end
    for r=rank,1,-1 do
        local a,b,x,y = getminmax(m1,1)
        m1[y][x] = 0
        -- print(m1)
        vnc[y][x] = r
    end
    for r=rank+1,n*m do
        local x,y,a,b = getminmax(m2,0)
        m2[y][x] = 1
        -- print(m2)
        vnc[y][x] = r
    end
	-- if n==8 and m==8 then print(vnc) end
    return vnc
end
local function norm(t)
    local m,n,z=#t,#t[1],1
    for i=1,m do
        for j=1,n do
            z = math.max(z,t[i][j])
        end
    end
    z = 1/(z+1)
    for i=1,m do
        for j=1,n do
            t[i][j] = t[i][j]*z
        end
    end
    return t
end
local function compo(f,g,...) -- let's do functionnal programming
    if g==nil then
		if type(f)=='function' then
			return f
		else
			return f==nil 
			and function(...) return ... end 
			or	function() return f end
		end
    elseif type(g)=='number' then
        if g<=0 then
            return compo(...)
        else
            return compo(f,g-1,f,...)
        end
    else
        local h = compo(g,...)
        return function(...) return f(h(...)) end
    end
end

-- ===========================================================================
-- init global data
CONFIG = {
    interlace   = 'p',
	asm_mode    = (MODE<6 and MODE) or (MODE%2==0 and 4 or 5),
    px_size     = {1,1},
    dither      = {1},
    palette     = compo{0x000,0x00F,0x0F0,0x0FF,
                        0xF00,0xF0F,0xFF0,0xFFF,
                        0x666,0x338,0x383,0x388,
                        0x833,0x838,0x883,0x069}
}

local PALETTE = {ef={}}
-- thomson levels in PC world
for i=0,15 do PALETTE.ef[i+1]=round(255*(i/15)^(1/2.8)) end
function PALETTE.linear(u)
	if not PALETTE.__linear then 
		PALETTE.__linear = {}
		for u=0,255 do
			PALETTE.__linear[u] = u<10.31475 and u/3294.6 or (((u+14.025)/269.025)^2.4)
		end
	end
	return PALETTE.__linear[u]
	-- return (u/255)^2.2
end
-- for i = 0,15 do
	-- pc = math.floor(0.5 + 255*(i/15)^(1/3))
	-- print(i,pc, PALETTE.linear(pc))
-- end
function PALETTE.unlinear(u)
    return u<0 and 0 or u>1 and 255 or u<0.00313 and (u*3294.6) or ((u^(1/2.4))*269.025-14.025)
    -- return u<0 and 0 or u>1 and 255 or (u^(1/2.2))*255
end
    
if MODE==0 then
    CONFIG.interlace = 'I' -- 'p' -- 'i' -- 'i3' -- 'i' -- 'iii' -- 'i3'
    CONFIG.dither    = 
	-- compo(norm,vac)(8,8)
	-- compo(norm,vac)(16,16)
	-- compo(norm,bayer,4){{1}}
	-- norm{
	-- {  6, 35, 49,  8, 39, 55, 13, 61},
	-- { 26, 54, 19, 58, 24,  2, 51, 33},
	-- { 45,  3, 41, 14, 44, 28, 38, 11},
	-- { 21, 63, 29, 53,  7, 62, 17, 56},
	-- { 47, 27,  9, 34, 46, 20, 42,  5},
	-- { 15, 40, 57, 23, 12, 59, 25, 52},
	-- { 60, 32,  1, 36, 50,  4, 37, 10},
	-- { 43, 16, 30, 64, 18, 31, 48, 22}}
	compo(norm,vac)(7,7)
	-- compo(norm,vac)(13,13)
elseif MODE==1 then
    CONFIG.px_size   = {1,3}
    CONFIG.interlace = 'I' -- 'i' -- 'iii'
    CONFIG.dither    = --compo(norm,bayer,3){{1,2,3}}
		-- compo(norm,vac)(13,5)
		compo(norm,vac)(9,3)
		-- compo(norm,vac)(23,7)
		-- compo(norm,vac)(17,5)
		-- compo(norm,vac)(16,5)
elseif MODE==2 or MODE==3 then
    CONFIG.px_size   = {4,1}
    CONFIG.interlace = 'i3'
    CONFIG.dither    = --bayer{{1,4},{9,12},{5,8},{13,16},{3,2},{11,10},{7,6},{15,14}}
			--bayer{{1,2},{9,10},{5,6},{13,14},{3,4},{11,12},{7,8},{15,16}}
			compo(bayer,2){{1},{3},{2},{4}}
			-- vac(5,19) -- (7,29)
			-- vac(4,17)
elseif MODE==4 or MODE==5 then
    CONFIG.px_size   = {4,1}
    CONFIG.interlace = 'ii'
    CONFIG.dither    = --bayer{{1,4},{9,12},{5,8},{13,16},{3,2},{11,10},{7,6},{15,14}}
		compo(bayer,2){{1},{3},{2},{4}}
		-- vac(5,17) 
		-- vac(7,29)
    CONFIG.palette   = compo(
        -- EXPONENTIAL and
            -- {0x000,0x00F,0x0F0,0xF00,
			 -- 0x0CC,0xC0C,0xCC0,0xFFF,
             -- 0x001,0x010,0x100,0x111,
             -- 0x005,0x050,0x500,0x555}
        EXPONENTIAL and
            {0x000,0x00E,0x0E0,0xE00,
			 0x0BB,0xB0B,0xBB0,0xFFF,
             0x001,0x010,0x100,0x111,
             0x004,0x040,0x400,0x555}
        or
            {0x000,0x444,0x999,0xFFF,
             0x001,0x004,0x009,0x00F,
             0x010,0x040,0x090,0x0F0,
             0x100,0x400,0x900,0xF00})
elseif MODE==6 or MODE==7 then
    CONFIG.px_size   = {4,2}
    CONFIG.interlace = 'I' -- ZIGZAG and 'i3' or 'p'
    CONFIG.dither    = 
		compo(norm,bayer){{1,4},{5,8},{3,2},{7,6}}
		
	-- b: 0     3   14
	-- r: 0     1   6   15
	-- g: 0     1   4   8       15

	
    CONFIG.palette   = compo(
        EXPONENTIAL and
            {0x000,0x100,0xD00,
             0x001,0x101,0xD01,
             0x004,0x104,0xD04,
             0x00D,0x10D,0xD0D,
             0x010,0x030,0x060,0x0D0}
			 -- {0x000,0x300,0xE00,
			  -- 0x001,0x301,0xE01,
			  -- 0x006,0x306,0xE06,
			  -- 0x00F,0x30F,0xE0F,
			  -- 0x010,0x040,0x080,0x0F0}
        or
            {0x000,0x600,0xF00,
             0x004,0x604,0xF04,
             0x008,0x608,0xF08,
             0x00F,0x60F,0xF0F,
             0x030,0x060,0x090,0x0F0})
elseif MODE==8 or MODE==9 then
    CONFIG.px_size   = {4,3}
    CONFIG.interlace = ZIGZAG and 'ii' or 'p'
    CONFIG.dither    = compo(norm,bayer,2){{1}}
    CONFIG.palette   = compo(
        EXPONENTIAL and
            {0x000,
             0x001,0x002,0x004,0x008,0x00F,
             0x010,0x020,0x040,0x080,0x0F0,
             0x100,0x200,0x400,0x800,0xF00}
        or
            {0x000,
             0X002,0x004,0x007,0x00A,0x00F,
             0X020,0x040,0x070,0x0A0,0x0F0,
             0X200,0x400,0x700,0xA00,0xF00})
elseif MODE==10 or MODE==11 then
    CONFIG.px_size   = {4,1}
    CONFIG.interlace = 'i3'
    CONFIG.dither    = --compo(bayer){{1,4},{9,12},{5,8},{13,16},{3,2},{11,10},{7,6},{15,14}}
		-- compo(bayer,2){{1},{3},{2},{4}}
		-- compo(bayer){{1},{3},{2},{4}}
		-- vac(5,19) --(7,29)
		-- vac(5,17)
		vac(3,13)
	for match in (package.path..';'):gmatch("(.-)?.lua;") do
		package.path = package.path .. ';' .. match ..           "./lib/?.lua"
		package.path = package.path .. ';' .. match ..          "../lib/?.lua"
		package.path = package.path .. ';' .. match ..    "../tools/lib/?.lua"
		package.path = package.path .. ';' .. match .. "../../tools/lib/?.lua"
	end
    function getpicturesize() return 80,50 end
    function waitbreak() end
    run = function(name) require(name:gsub('%..*','')) end
    run("color_reduction.lua")
    CONFIG.palette   = function(CONVERTER,VIDEO)
        local reducer = ColorReducer:new()
        for i,f in ipairs(arg) do
            local TMP = CONVERTER:new(f,nil,3)
            if TMP then
                local stat = VIDEO:new(TMP.file,TMP.fps,80,50,80,50,TMP.interlace,
					function(self, x,y, r,g,b)
                    local col = Color:new(r,g,b):toLinear()
                    -- for i=1,1+1000*math.exp(-(x-40)^2/100) do
                        reducer:add(col)
                    -- end
                end)
                stat.super_next_image = stat.next_image
                stat.mill = {'|', '/', '-', '\\'}
                stat.mill[0] = stat.mill[4]
                function stat:next_image()
                    self:super_next_image()
                    io.stderr:write(string.format('> analyzing colors...%s %d%%\r',
                                    self.mill[self.cpt % 4],
                                    percent((i-1+self.cpt/self.fps/TMP.duration)/#arg)))
                    io.stderr:flush()
                end
                while stat.running do stat:next_image() end
            end
        end
		reducer:boostBorderColors()
		reducer:boostBorderColors()					 
		-- for i=1,16 do reducer:boostBorderColors() end
        io.stderr:write(string.rep(' ',79)..'\r')
        io.stderr:flush()
        local pal = reducer:buildPalette(16, true)
        return pal
    end
elseif MODE==12 or MODE==13 then
	CONFIG.asm_mode	 = MODE%2==0 and 2 or 3
    CONFIG.px_size   = {4,1}
    CONFIG.interlace = 'iii' -- 'i3'
    CONFIG.dither    = --compo(norm,bayer,2){{1,4},{9,12},{5,8},{13,16},{3,2},{11,10},{7,6},{15,14}}
			-- compo(norm,bayer,3){{1},{3},{2},{4}}
			compo(norm,vac)(7,29)
elseif MODE==14 or MODE==15 then
	CONFIG.asm_mode	 = MODE%2==0 and 4 or 5
    CONFIG.px_size   = {4,1}
    CONFIG.interlace = 'i3'
    CONFIG.dither    = --compo(bayer,2){{1,4},{9,12},{5,8},{13,16},{3,2},{11,10},{7,6},{15,14}}
		-- compo(bayer,2){{1},{3},{2},{4}}
		-- vac(5,19) -- (7,29)
		vac(5,17)
	CONFIG.palette   = compo{
		0x000, 0x111, 0x101, 0x013, 
		0x510, 0x130, 0x772, 0xf11, 
	    0x25f, 0xf50, 0xea0, 0x579, 
		0xfa8, 0x3ff, 0xff2, 0xfff} -- Dawnbriger16
elseif MODE==16 or MODE==17 then
	CONFIG.asm_mode	 = MODE%2==0 and 4 or 5
    CONFIG.px_size   = {4,1}
    CONFIG.interlace = 'p' -- 'i3'
    CONFIG.dither    = 
		-- compo(norm,bayer,1){{1},{3},{2},{4}}
		-- compo(norm,vac)(7,29)
		-- compo(norm,vac)(5,19)
		compo(norm,vac)(3,11)
		-- compo(norm){{1}}
		-- compo(norm,bayer,1){{1,4},{9,12},{5,8},{13,16},{3,2},{11,10},{7,6},{15,14}}
	CONFIG.palette   = compo{
		0x000, 0x111, 0x222, 0x333,
		0x444, 0x555, 0x666, 0x777,
		0x888, 0x999, 0xAAA, 0xBBB,
		0xCCC, 0xDDD, 0xEEE, 0xFFF}
elseif MODE==18 or MODE==19 then
	CONFIG.asm_mode	 = MODE%2==0 and 4 or 5
    CONFIG.px_size   = {4,1}
    CONFIG.interlace = 'i3'
    CONFIG.dither    = 
	-- compo(bayer,1){{1},{3},{2},{4}}
	-- vac(5,19) -- (7,29)
	-- vac(7,29)
	-- vac(5,17) --
	vac(3,11)
	-- vac(3,13)
	-- vac(4,16)
	CONFIG.palette   = compo{
		-- 0 1 4 7 14
		-- 0x000, 
		-- 0x100,0x400,0x700,
		-- 0x010,0x040,0x070,
		-- 0x001,0x004,0x007,
		-- 0x07E,0xE07,0xE70,
		-- 0x414,0x747,0xEEE
		
		-- 0x000,0x100,0x010,0x001,
		-- 0x111,0x400,0x040,0x004,
		-- 0x777,0xF00,0x0F0,0xFF0,
		-- 0x00F,0xF0F,0x0FF,0xFFF

		0x000,0x400,0x040,0x004,
		0x111,0x044,0x404,0x440,
		0x777,0xE00,0x0E0,0xEE0,
		0x00E,0xE0E,0x0EE,0xEEE
		
		-- 0x000,0xd00,0x0d0,0xdd0,
		-- 0x00d,0xd0d,0x0dd,0xddd,
		-- 0x100,0x010,0x001,
		-- 0x400,0x040,0x004,
		-- 0x444,0x888
		
		-- 0x000,0x0DD,0xD0D,0xDD0,
        -- 0x001,0x004,0x007,0x00D,
        -- 0x010,0x040,0x070,0x0D0,
        -- 0x100,0x400,0x700,0xD00
	}
elseif MODE==20 or MODE==21 then
	CONFIG.asm_mode	 = MODE%2==0 and 4 or 5
    CONFIG.px_size   = {4,1}
    CONFIG.interlace = 'I' -- 'i3'
    CONFIG.dither    = 
	-- compo(bayer,1){{1},{3},{2},{4}}
	
	-- {{1},{3},{2},{4}}
	-- {{8,6,7},{3,1,5},{4,2,9}}
	
	---- x--- x--- x--- x-x- xxx- xxx- xxx- xxxx
	---- ---- --x- -x-x -x-x -x-x x-xx xxxx xxxx
	---- --x- x--- --x- x-x- x-xx xxx- x-xx xxxx
	---- ---- --x- -x-x -x-x -x-x x-xx xxxx xxxx 
	---       ~~~~                ~~~~  
--	0	 2	  4	   6	8	 10	  12	14	16
	               
	---- x--- x---
	---- ---- -x--
	---- x--- --x-
	---- ---- ---x
	
	-- {{1,2},{2,1}}
	-- vac(5,19) -- (7,29)
	-- vac(7,29)
	-- vac(5,17) --
	-- vac(3,11)
	vac(3,9)
			 
	-- vac(4,16)
	-- vac(3,13)
			 
			
	-- vac(4,16)
			 
	CONFIG.palette   = compo{
		-- 0 1 4 7 14
		-- 0x000, 
		-- 0x100,0x400,0x700,
		-- 0x010,0x040,0x070,
		-- 0x001,0x004,0x007,
		-- 0x07E,0xE07,0xE70,
		-- 0x414,0x747,0xEEE
		
		-- 0x000,0x100,0x010,0x001,
		-- 0x111,0x400,0x040,0x004,
		-- 0x777,0xF00,0x0F0,0xFF0,
		-- 0x00F,0xF0F,0x0FF,0xFFF

		-- 0x000,0x100,0x010,0x001,
		-- 0x222,0x200,0x020,0x002,
		-- 0x666,0x400,0x040,0x004,
		-- 0xCCC,0x800,0x080,0x008
		
		-- 0 1 2
		
		-- 000 100 200 010 110 210 020 120 220 
		-- 001 101 201 011 111 211 021 121 221
		-- 002 102 202 012 112 212	022 122 222
		
		-- 000 200 020 220 002 202 022 222
		
		-- 000 100 200 010     210 020 120 220 
		                                   
		-- 002 102 202 012     212	022 122 222
		
		
-- 0       0       0
-- 1       103     0.13563332965521
-- 2       130     0.22322795731681
-- 3       149     0.30054379441578
-- 4       164     0.37123768047415
-- 5       177     0.43965717384092
-- 6       188     0.50288645803257
-- 7       198     0.56471150570493
-- 8       207     0.62396039167508
-- 9       215     0.67954246963309
-- 10      223     0.73791040877273
-- 11      230     0.79129794033263
-- 12      237     0.84687323150986
-- 13      243     0.89626935337427
-- 14      249     0.9473065367332
-- 15      255     1
		
		
		-- 3*4+5
		-- 0 2 5 13=d
		-- 2*3+4
		-- 0x000,0x00d,0x0d0,0x0dd,0xd00,0xd0d,0xdd0,0xDDD,
		
		-- 0x000, 0x008, 0x080, 0x088, 0x800, 0x808, 0x880, 0x888, -- 8
		-- 0x100, 0x300,
		-- 0x010, 0x030,
		-- 0x001, 0x003,
		-- 0x222, 0x555
		
		-- 0x000,0x800,0x080,0x880,
		-- 0x008,0x808,0x088,0x888,
		      -- 0x001,0x003,
		-- 0x300,0x301,0x303,
		-- 0x010,0x030,0x222
		
		-- dune:
		-- 0x000,0x111,0x333,0x880,
		-- 0x100,0x010,0x001,0x808,
		-- 0x300,0x030,0x003,0x088,
		-- 0x800,0x080,0x008,0x888
		
		0x000,0x222,0x666,0xcc0,
		0x200,0x020,0x002,0xc0c,
		0x600,0x060,0x006,0x0cc,
		0xc00,0x0c0,0x00c,0xccc
	
		
		-- 0x100,0x010,0x001,
		-- 0x400,0x040,0x004,
		-- 0x444,0x888
		
		-- 0x000,0x0DD,0xD0D,0xDD0,
        -- 0x001,0x004,0x007,0x00D,
        -- 0x010,0x040,0x070,0x0D0,
        -- 0x100,0x400,0x700,0xD00
		
		-- ok:
		-- 0x000,0x0DD,0xD0D,0xDD0,
        -- 0x001,0x003,0x006,0x00D,
        -- 0x010,0x030,0x060,0x0D0,
        -- 0x100,0xDDD,0x600,0xD00
	}
	CONFIG.palette   = function(CONVERTER,VIDEO)
		local H = {r={},g={},b={},w={}}
		for i=0,255 do H.r[i]=0; H.g[i]=0; H.b[i]=0; H.w[i]=0 end		local function map(vals, histo)
			local t={}; t[0] = 0
			local k,v0,v1=1,0,PALETTE.linear(vals[1])
			local e,h=0,{}
			local avg = 0; for i=0,255 do avg = avg + histo[i]/256 end
			for i=0,255 do h[i]=histo[i]/avg + 1/16 end
			for i=0,255 do
				local v = PALETTE.linear(i)
				if v>=v1 and vals[k+1] then 
					k,v0,v1=k+1,v1,PALETTE.linear(vals[k+1]) 
				end
				local f = (v-v0)/(v1-v0); if f>=1 then f=1 end
				t[i] = k-1 + f
				if histo then
				 
					local DIV=2
					f = round(f*DIV)/DIV
					e = e + h[i]*math.abs(v0 + f*(v1-v0) - v)^2
				end
			end
			return t,math.abs(e)
		end

        for i,f in ipairs(arg) do
            local TMP = CONVERTER:new(f,nil,3)
            if TMP then
                local stat = VIDEO:new(TMP.file,TMP.fps,80,50,80,50,TMP.interlace,
					function(self, x,y, r,g,b)
					H.r[r], H.g[g], H.b[b] = H.r[r]+1, H.g[g]+1, H.b[b]+1
					local t = math.floor(r*.30 + g*.59 + b*.11)
					H.w[t] = H.w[t]+1
				end)
                stat.super_next_image = stat.next_image
                stat.mill = {'|', '/', '-', '\\'}
                stat.mill[0] = stat.mill[4]
                function stat:next_image()
                    self:super_next_image()
                    io.stderr:write(string.format('> analyzing colors...%s %d%%\r',
                                    self.mill[self.cpt % 4],
                                    percent((i-1+self.cpt/self.fps/TMP.duration)/#arg)))
                    io.stderr:flush()
                end
                while stat.running do stat:next_image() end
            end
        end
		local ef = {}; for i=0,15 do ef[i] = PALETTE.ef[1+i] end
		local r,g,b,w,t,e
		for i=1,13 do for j=i+1,14 do for k=j+1,15 do
			t,e = map({ef[i],ef[j],ef[k]}, H.r)
			if r==nil or e<=r.err then r = {err=e, base={0,i,j,k}} end
			t,e = map({ef[i],ef[j],ef[k]}, H.g)
			if g==nil or e<=g.err then g = {err=e, base={0,i,j,k}} end
			t,e = map({ef[i],ef[j],ef[k]}, H.b)
			if b==nil or e<=b.err then b = {err=e, base={0,i,j,k}} end
			t,e = map({ef[i],ef[j],ef[k]}, H.w)
			if w==nil or e<=w.err then w = {err=e, base={0,i,j,k}} end
		end end end
		io.stderr:write(string.rep(' ',79)..'\r')
        io.stderr:flush()

		print('b', unpack(b.base))
		print('r', unpack(r.base))
		print('g', unpack(g.base))
		print('w', unpack(w.base))

		return {
		-- 0x000,0x111,0x333,0x880,
		-- 0x100,0x010,0x001,0x808,
		-- 0x300,0x030,0x003,0x088,
		-- 0x800,0x080,0x008,0x888
		0x000*w.base[1],0x111*w.base[2],0x111*w.base[3],0x110*w.base[4],
		0x100*b.base[2],0x010*g.base[2],0x001*r.base[2],0x101*w.base[4],
		0x100*b.base[3],0x010*g.base[3],0x001*r.base[3],0x011*w.base[4],
		0x100*b.base[4],0x010*g.base[4],0x001*r.base[4],0x111*w.base[4]
		}
    end
elseif MODE==22 then
	CONFIG.asm_mode	 = 6
    CONFIG.px_size   = {2,1}
    CONFIG.interlace = 'I'
    CONFIG.dither    = 
						norm(vac(7,13))
						-- norm(vac(5,11))
						-- compo(norm,bayer,3){{1},{2}} 
						-- norm(vac(4,7)) -- norm(vac(7,13)) -- compo(norm,bayer,2){{1},{2}} --  compo(norm,bayer,2){{1},{2}} -- norm(vac(4,8)) -- 
	CONFIG.palette   = function(CONVERTER,VIDEO)
		local H = {w={}} for i=0,255 do H.w[i]=0 end		
		local function map(vals, histo)
			local t={}; t[0] = 0
			local k,v0,v1=1,0,PALETTE.linear(vals[1])
			local e,h=0,{}
			local avg = 0; for i=0,255 do avg = avg + histo[i]/256 end
			for i=0,255 do h[i]=histo[i]/avg + 0.5*1/16 end
			for i=0,255 do
				local v = PALETTE.linear(i)
				if v>=v1 and vals[k+1] then 
					k,v0,v1=k+1,v1,PALETTE.linear(vals[k+1]) 
				end
				local f = (v-v0)/(v1-v0); if f>=1 then f=1 end
				t[i] = k-1 + f
				if histo then
					local DIV=1
					f = round(f*DIV)/DIV
					e = e + h[i]*math.abs(v0 + f*(v1-v0) - v)^2
				end
			end
			return t,math.abs(e)
		end

        for i,f in ipairs(arg) do
            local TMP = CONVERTER:new(f,nil,3)
            if TMP then
                local stat = VIDEO:new(TMP.file,TMP.fps,80,100,80,100,TMP.interlace,
					function(self, x,y, r,g,b)
					local t = math.floor(r*GRAY_R + g*GRAY_G + b*GRAY_B)
					H.w[t] = H.w[t]+1
				end)
                stat.super_next_image = stat.next_image
                stat.mill = {'|', '/', '-', '\\'}
                stat.mill[0] = stat.mill[4]
                function stat:next_image()
                    self:super_next_image()
                    io.stderr:write(string.format('> analyzing colors...%s %d%%\r',
                                    self.mill[self.cpt % 4],
                                    percent((i-1+self.cpt/self.fps/TMP.duration)/#arg)))
                    io.stderr:flush()
                end
                while stat.running do stat:next_image() end
            end
        end
		local ef = {}; for i=0,15 do ef[i] = PALETTE.ef[1+i] end
		local r,g,b,w,t,e
		for i=1,13 do for j=i+1,14 do for k=j+1,15 do
			t,e = map({ef[i],ef[j],ef[k]}, H.w)
			if w==nil or e<=w.err then w = {err=e, base={0,i,j,k}} end
		end end end
		io.stderr:write(string.rep(' ',79)..'\r')
        io.stderr:flush()

		print('w', unpack(w.base))

		return {
			0x000*w.base[1],0x111*w.base[2],0x111*w.base[3],0x111*w.base[4],
			0,0,0,0,0,0,0,0,0,0,0,0
		}
    end
else
    error("Invalid MODE="..MODE)
end

-- ===========================================================================
-- PALETTE support
-- local PALETTE = {}
function PALETTE:init(pal)
    self.thomson = pal -- palette to use (thomson world)
    for i,p in ipairs(pal) do -- palette in PC world
        self[i] = {self.ef[1+(p%16)],
                   self.ef[1+(math.floor(p/16)%16)],
                   self.ef[1+math.floor(p/256)]}
    end
end
function PALETTE.exp_lin(n)
    return n<=PALETTE.ef[2]
           -- and -(n/PALETTE.ef[2])^1.27
           -- and -(n/PALETTE.ef[2])^2.2
           -- and -n/PALETTE.ef[2]
           and -PALETTE.linear(n)/PALETTE.linear(PALETTE.ef[2]) -- -1..0
           or  1-math.log(n/255)/math.log(PALETTE.ef[2]/255)    -- 0..1
end
function PALETTE:file_content()
    local buf = ''
    for _,v in ipairs(self.thomson) do
        buf = buf .. string.char(math.floor(v/256), v%256)
    end
    return buf
end
-- print(PALETTE.unlinear(.2), PALETTE.unlinear(.4), PALETTE.unlinear(.6), PALETTE.unlinear(.8))
function PALETTE:intens(i)
    local p,f = self[i], PALETTE.linear
    return .2126*f(p[1]) + .7152*f(p[2]) + .0722*f(p[3])
end
function PALETTE.key(r,g,b)
    return string.char(round(r/4),round(g/4),round(b/8))
end
function PALETTE:compute(n, r,g,b)
	-- for i,p in ipairs(self) do print(i,'=',unpack(p)) end
-- r=255 g=255 b=255
	local EPS,push = 1e-12,table.insert
	local tetras = self.tetras
	local function dbg(n,p,z)
		print(string.format("%s\t%.3f %.3f %.3f %.3f", n,p[1],p[2],p[3],p[4] or z or 0/0))
	end
	if not tetras then
		tetras = {}
		self.tetras = tetras
		local function tetra(a,b,c,d) 
			local function sub(a,b) return {a[1]-b[1],a[2]-b[2],a[3]-b[3]} end
			local function mul(a,x) return {a[1]*x, a[2]*x, a[3]*x} end
			local function dot(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end
			local function prd(a,b) return {a[2]*b[3]-a[3]*b[2],a[3]*b[1]-a[1]*b[3],a[1]*b[2]-a[2]*b[1]} end
			local function nrm(a) return mul(a,dot(a,a)^-.5) end
			--  |d
			--  |____c
			-- a\
			--   \b
			local ba,ca,da = sub(b,a),sub(c,a),sub(d,a)
			local na,nb,nc,nd = 
				prd(sub(d,b),sub(c,b)),
				prd(ca,da),
				prd(da,ba),
				prd(ba,ca)
			local proj3 = function(point, v0,v1,v2)
			-- https://www.geometrictools.com/Documentation/DistancePoint3Triangle3.pdf
				local diff,edge0,edge1 = sub(point,v0),sub(v1,v0),sub(v2,v0)
				local a00,a01,a11 = dot(edge0,edge0),dot(edge0,edge1),dot(edge1,edge1)
				local b0,b1= -dot(diff,edge0),-dot(diff,edge1)
				local det,t0,t1 = a00 * a11 - a01 * a01,  a01 * b1 - a11 * b0, a01 * b0 - a00 * b1
				
				if t0 + t1 <= det then
					if t0 < 0 then 
						if t1<0 then -- region 4
							if b0<0 then
								t0,t1 = -b0>=a00 and 1 or -b0/a00,0
							else
								t0,t1 = 0,b1>=0 and 0 or -b1>=a11 and 1 or -b1/a11
							end
						else  -- region 3
							t0,t1 = 0,b1>=0 and 0 or -b1>=a11 and 1 or -b1/a11	
						end
					elseif t1<0 then -- region 5
						t0,t1 = b0>=0 and 0 or -b0>=a00 and 1 or -b0/a00,0
					else -- region 0, interior
						t0,t1 = t0/det,t1/det
					end
				else
					local tmp0,tmp1, numer,denom
					if t0<0 then -- region 2
						tmp0,tmp1 = a01+b0,a11+b1
						if tmp1>tmp0 then
							numer,denom = tmp1-tmp0,a00-a01-a01+a11
							t0 = numer>=denom and 1 or numer/denom
							t1 = 1-t0
						else
							t0,t1 = 0,tmp1<=0 and 1 or b1>=0 and 0 or -b1/a11
						end
					elseif t1<0 then -- region 6
						tmp0,tmp1 = a01 + b1,a00 + b0
						if tmp1>tmp0 then
							numer,denom = tmp1-tmp0,a00-a01-a01+a11
							t1 = numer>=denom and 1 or numer/denom
							t0 = 1-t1
						else
							t1,t0 = 0,tmp1<=0 and 1 or b0>=0 and 0 or -b0/a00
						end
					else -- region 1
						numer,denom = a11 + b1 - a01 - b0,a00 - a01 - a01 + a11
						t0 = numer<=0 and 0 or numer>=denom and 1 or numer/denom
						t1 = 1-t0
					end
				end
			   
				return 1-t0-t1,t0,t1
			end
			local proj2 = function(p, v0,v1)
				local v10 = sub(v1,v0)
				local t = dot(v10,v10)
				if t<=EPS then return 1,0 end
				t = dot(sub(p,v0),v10)/t
				t = t<=EPS and 0 or t>1 and 1 or t
				return 1-t,t
			end
			local coord = function(p)
				local pa,pb = sub(p,a),sub(p,b)
				local x,y,z,t,D = dot(pb,na),dot(pa,nb),dot(pa,nc),dot(pa,nd)
				if x>=-EPS and y>=-EPS and z>=-EPS and t>=-EPS then
					x,y,z,t = x<=EPS and 0 or x, y<=EPS and 0 or y, z<=EPS and 0 or z, t<=EPS and 0 or t
					D = x+y+z+t; D=D>0 and 1/D or 0
					return x*D,y*D,z*D,t*D
				end
				return nil
			end
			local t = {v=0,a=a,b=b,c=c,d=d,
			basic_coord = function(p)
				local pa,pb = sub(p,a),sub(p,b)
				return dot(pb,na),dot(pa,nb),dot(pa,nc),dot(pa,nd)
			end,
			coord=(a.__supertriangle or b.__supertriangle or c.__supertriangle or d.__supertriangle) and function(p)
				local x,y,z,t = coord(p)
				if x then
					-- print("super:", x,y,z,t)
					-- print(a[1],b[1],c[1],d[1])
					-- print(a[2],b[2],c[2],d[2])
					-- print(a[3],b[3],c[3],d[3])
					
					x,y,z,t = 0,0,0,0
					if a.__supertriangle then
						if b.__supertriangle then
							if c.__supertriangle then
								t = 1
							elseif d.__supertriangle then
								z = 1
							else
								z,t = proj2(p,c,d)
							end
						elseif c.__supertriangle then
							if d.__supertriangle then
								y = 1
							else
								y,t = proj2(p,b,d)
							end
						elseif d.__supertriangle then
							y,z = proj2(p,b,c)
						else
							y,z,t = proj3(p,b,c,d)
						end
					elseif b.__supertriangle then
						if c.__supertriangle then
							if d.__supertriangle then
								x = 1
							else
								x,t = proj2(p,a,d)
							end
						elseif d.__supertriangle then
							x,z = proj2(p,a,c)
						else
							x,z,t = proj3(p,a,c,d)
						end
					elseif c.__supertriangle then
						if d.__supertriangle then
							x,y = proj2(p,a,b)
						else
							x,y,t = proj3(p,a,b,d)
						end
					elseif d.__supertriangle then
						x,y,z = proj3(p,a,b,c)
					end
				end
				return x,y,z,t
			end	or coord}
			t.v = dot(ba,na)
			if t.v>EPS         then na = mul(na,-1) else t.v = -t.v end
			if dot(ba,nb)<-EPS then nb = mul(nb,-1) end
			if dot(ca,nc)<-EPS then nc = mul(nc,-1) end
			if dot(da,nd)<-EPS then nd = mul(nd,-1) end
			return t
		end
		local function BowyerWatson()
			-- https://en.wikipedia.org/wiki/Bowyer%E2%80%93Watson_algorithm
			local push = table.insert
			local function sub(U,V) return {U[1]-V[1],U[2]-V[2],U[3]-V[3]} end
			local function dot(U,V) return U[1]*V[1] + U[2]*V[2] + U[3]*V[3] end
			local function dist2(U,V) local T=sub(U,V) return dot(T,T) end
			local function det(M)
				local det,n,abs = 1,#M,math.abs
				for i=1,n do
					for j=i+1,n do
						if abs(M[j][i])>abs(M[i][i]) then
							det,M[i],M[j] = -det,M[j],M[i]
						end
					end
					if M[i][i]==0 then return 0 end
					for j=i+1,n do
						local c = M[j][i]/M[i][i]
						for k=i,n do
							M[j][k] = M[j][k] - c*M[i][k]
						end
					end
				end
				for i=1,n do det = det*M[i][i] end
				return det
			end
			local function circumSphere(tetra)
				local sphere = tetra.__circumSphere
				if not sphere then
					-- https://mathworld.wolfram.com/Circumsphere.html
					local x1,y1,z1 = tetra[1][1],tetra[1][2],tetra[1][3]
					local x2,y2,z2 = tetra[2][1],tetra[2][2],tetra[2][3]
					local x3,y3,z3 = tetra[3][1],tetra[3][2],tetra[3][3]
					local x4,y4,z4 = tetra[4][1],tetra[4][2],tetra[4][3]
					local a =   det{{x1, y1, z1, 1},
									{x2, y2, z2, 1},
									{x3, y3, z3, 1},
									{x4, y4, z4, 1}}
					if math.abs(a)<=EPS then return nil end -- coplanar
					local s1 = x1^2 + y1^2 + z1^2
					local s2 = x2^2 + y2^2 + z2^2
					local s3 = x3^2 + y3^2 + z3^2
					local s4 = x4^2 + y4^2 + z4^2
					local Dx =  det{{s1, y1, z1, 1},
									{s2, y2, z2, 1},
									{s3, y3, z3, 1},
									{s4, y4, z4, 1}}              		
					local Dy = -det{{s1, x1, z1, 1},
									{s2, x2, z2, 1},
									{s3, x3, z3, 1},
									{s4, x4, z4, 1}}              		
					local Dz =  det{{s1, x1, y1, 1},
									{s2, x2, y2, 1},
									{s3, x3, y3, 1},
									{s4, x4, y4, 1}}    
					local c =   det{{s1, x1, y1, z1},
									{s2, x2, y2, z2},
									{s3, x3, y3, z3},
									{s4, x4, y4, z4}}
					local ia2 = 1/(2*a)
					sphere = {{Dx*ia2, Dy*ia2, Dz*ia2},(Dx^2+Dy^2+Dz^2 - 4*a*c)*ia2^2}
					tetra.__circumSphere = sphere
				end
				return sphere[1],sphere[2]
			end
			local function boundary(tetras)
				local code={n=0}
				local encode = function(pts)
					local t = {}
					for _,pt in ipairs(pts) do
						local k = code[pt]
						if not k then 
							k = code.n+1
							code[k],code[pt],code.n = pt,k,k
						end
						table.insert(t,k)
					end
					table.sort(t)
					return table.concat(t,',')
				end
				local function decode(str)
					local t,i,j = {},1,str:find(',')
					while j do
						push(t, code[tonumber(str:sub(i,j-1))])
						i,j = j+1,str:find(',',j+1)
					end
					push(t, code[tonumber(str:sub(i))])
					return t
				end
				local set = {}
				local function inc(pts)
					local k = encode(pts)
					set[k] = (set[k] or 0)+1
				end
				for T in pairs(tetras) do
					inc{T[1],T[2],T[3]}
					inc{T[1],T[2],T[4]}
					inc{T[1],T[3],T[4]}
					inc{T[2],T[3],T[4]}
				end
				local t = {}
				for k,v in pairs(set) do
					if v==1 then table.insert(t, decode(k)) end
				end
				return t
			end
			return {
				vertices = {},
				cleanup = function(self)
					local facets = self.facets or {}
					for i=#facets,1,-1 do
						local tetra = facets[i]
						tetra.__circumSphere = nil
						if tetra[1].__supertriangle
						or tetra[2].__supertriangle
						or tetra[3].__supertriangle
						or tetra[4].__supertriangle
						then table.remove(facets,i) end
					end
				end,
				add = function(self,pt) 
					local vertices,facets = self.vertices,self.facets
					if vertices then
						push(vertices, pt)
						if #vertices==4 then
							for i=1,4 do vertices[i].__supertriangle = true end
							self.facets = { {vertices[1],vertices[2],vertices[3],vertices[4]} }
							self.vertices = nil
						end
					else
						-- print("adding ", pt[1], pt[2], pt[3], pt[4])
						local badTetras = {}
						for _,tetra in ipairs(facets) do
							local c,r2 = circumSphere(tetra)
							if dist2(c,pt)<=r2 then badTetras[tetra] = true end
						end
						local poly = boundary(badTetras)
						for i=#facets,1,-1 do
							if badTetras[facets[i]] then table.remove(facets,i) end
						end
						for i,tri in ipairs(poly) do
							push(tri,pt)
							push(facets, tri)	
							if not circumSphere(tri) then
								for j=1,i do table.remove(facets,#facets) end
								for f in pairs(badTetras) do push(facets,f) end
								local pert = {}
								for k,v in pairs(pt) do pert[k]=v end
								for j=1,3 do pert[j] = pert[j]*(1 + (pert[j]>=1 and -1 or 1)*math.random()/100000) end
								-- print("pert", pt[1],pt[2],pt[3],"\n=>",pert[1],pert[2],pert[3])
								return self:add(pert)
							end
						end
					end
					return self
				end
			}
		end
		local h = BowyerWatson():add{-2,-2,-2}:add{10,-2,-2}:add{-2,10,-2}:add{-2,-2,10}
		for i,p in ipairs(self) do p.index=i-1; h:add{self.linear(p[1]),self.linear(p[2]),self.linear(p[3]),index=i-1} end
		for _,F in ipairs(h.facets) do
			local t = tetra(F[1],F[2],F[3],F[4])
			push(tetras, t) 
		end	
		local function mark_opp(tetras)
			local code,tet={n=0},{}
			local encode = function(pts)
				local t = {}
				for _,pt in ipairs(pts) do
					local k = code[pt]
					if not k then 
						k = code.n+1
						code[pt],code.n = pt,k,k
					end
					table.insert(t,k)
				end
				table.sort(t)
				return table.concat(t,',')
			end
			local process = function(tetra, a,b,c, d)
				local k = encode(a,b,c)
				local t = tet[k]
				if t then
					t.tet[t.face] = tetra
					tetra[d] = t.tet
				else
					tet[k] = {face=d, tet=tetra}
				end
			end
			local triangles = {}
			for i,tetra in ipairs(tetras) do
				tetra.no = i
				process(tetra, tetra.a, tetra.b, tetra.c, "opp_d")
				process(tetra, tetra.a, tetra.b, tetra.d, "opp_c")
				process(tetra, tetra.a, tetra.c, tetra.d, "opp_b")
				process(tetra, tetra.b, tetra.c, tetra.d, "opp_a")
			end
		end	
		-- mark_opp(tetras)
		h = nil
	end
	local p = {self.linear(r),self.linear(g),self.linear(b)}
	for i,tetra in ipairs(tetras) do
		local x,y,z,t = tetra.coord(p)
		if x then 
			if i>4 then table.insert(tetras,1,table.remove(tetras,i)) end
			local sorted = {
				{x,tetra.a.index},{y,tetra.b.index},
				{z,tetra.c.index},{t,tetra.d.index}
			}
			table.sort(sorted, function(a,b) return a[1]>b[1] end)
			x,y,z,t = sorted[1][1],sorted[2][1],sorted[3][1],sorted[4][1]
			x,y,z,t = x*n,(x+y)*n,(x+y+z)*n,{}
			while #t<x do push(t,sorted[1][2]) end
			while #t<y do push(t,sorted[2][2]) end
			while #t<z do push(t,sorted[3][2]) end
			while #t<n do push(t,sorted[4][2]) end
			table.sort(t, function(a,b) return self:intens(a+1)<self:intens(b+1) end)
			return string.char(unpack(t))
		end
	end
	error("no match for " .. p[1].." "..p[2].." "..p[3])
end
if false then
	function PALETTE:index(r,g,b) 
		local k=self.key(self.unlinear(r),self.unlinear(g),self.unlinear(b))
		if not self.icache then self.icache = {} end
		local i=self.icache[k]
		if true or not i then
			if not self.linearized then
				local f=self.linear
				self.linearized = {}
				for i,p in ipairs(self) do
					self.linearized[i] = {f(p[1]),f(p[2]),f(p[3])}
				end
			end
			local d=1e38
			for j,p in ipairs(self.linearized) do
				local t = (r-p[1])^2 + (g-p[2])^2 + (b-p[3])^2
				if t<d then d,i=t,j end
			end
			print(k,'=>',i)
			self.icache[k] = i
		end
		return i
	end
	PALETTE.compute_ = PALETTE.compute
	function PALETTE:compute(n, r,g,b)
		local R,G,B = r,g,b
		r,g,b = self.linear(r),self.linear(g),self.linear(b)
		local k = 0.7
		local x,y,z=0,0,0
		local t = {}
		for i=1,n do
			local j = self:index(r+x*k, g+y*k, b+z*k)
			local p = self[j]
			x,y,z = x+r-p[1],y+g-p[2],z+b-p[3]
			t[i] = j-1
		end
		table.sort(t, function(a,b) return self:intens(a+1)<self:intens(b+1) end)
		
		local z = self:compute_(n, R,G,B)
		for i,v in ipairs(t) do
			local b = z:byte(i)
			if v~=b then
				print(R,G,B)
				for i,v in ipairs(t) do	print('***' , i, v, z:byte(i)) end
				error()
			end
		end
		
		return string.char(unpack(t))
	end
end
-- ===========================================================================-- PALETTE support
-- flux audio
local AUDIO = {}
function AUDIO:new(file)
	-- value such that group_size*1000000/cycles is the most integer
	local size = 25 -- 6
	if false then
		local min = 10
		for i=1,16 do
			local x = i*1000000/CYCLES
			x = math.abs(x-round(x))
			if x<min then size,min = i,x end
			print(i,x,size)
		end
	end
	
	local hz = round(size*1000000/CYCLES)
	local I='I=-8' -- volume final -24=superbas, -16=fable
	local LRA='LRA=11'
	local tp='tp=-1'
	local norm = '-af loudnorm='..I..':'..LRA..' '
	norm = '-filter:a dynaudnorm=p=0.9:s=5 '
	if false then
		io.stderr:write('> analyzing audio...')
		io.stderr:flush()
		local measured={}
		local IN,line = assert(io.popen(FFMPEG..' -i "'..file ..'" -ar '..hz..' -af loudnorm=print_format=json -ac 1 -vn -f null x 2>&1', 'r'))
		for line in IN:lines() do
			-- print(line)
			local k,v = line:match('"([^"]+)" : "([^"]+)"')
			if k then
				measured[k] = v
				-- print(k,v)
			-- elseif line:match('speed=') then -- debug
				-- io.stderr:write(line)
				-- io.stderr:flush()
			end
		end
		IN:close()	
		io.stderr:write('\r                                     \r')
		io.stderr:flush()
		norm = '-af loudnorm=linear=true:'..I..':'..LRA..':'..tp.. 
		':measured_I=' .. measured['input_i'] ..
		':measured_LRA=' .. measured['input_lra'] ..
		':measured_tp=' .. measured['input_tp'] ..
		':measured_thresh=' .. measured['input_thresh'] ..
		':offset=' .. measured['target_offset'].. 
		' '
		-- print(norm)
	end
	
	local o = {
		hz = hz,
		stream = assert(io.popen(FFMPEG..' -i "'..file ..'" -v 0 ' ..
		-- 'dynaudnorm=f=8000:c:b:s=10:m=4 ' ..
		-- 'dynaudnorm=p=0.71:m=100:s=10:g=15 ' ..
		-- 'dynaudnorm=p=0.71:m=6:s=10:g=15 ' ..
		-- 'dynaudnorm=p=0.71:s=12:g=15:m=12:f=8000 ' ..
		-- 'loudnorm=I=-16:LRA=11:TP=-1.5 ' ..
		-- '-af loudnorm=I=-16:LRA=11 ' ..
		norm ..
		'-ac 1 -ar '..hz..' -f s8 -c:a pcm_s8 pipe:', POPEN_READBIN)),
		size = size,
		mute = '',
		buf = '', -- buffer
		vol = 1.9,
		running = true
	}
	for i=1,size do o.mute = o.mute .. string.char(0) end
	setmetatable(o, self)
	self.__index = self
	return o
end
function AUDIO:close()
	self.stream:close()
end
function AUDIO:next_sample()
	local buf,siz = self.buf,self.size
	if buf:len()<=siz then
		local t = self.stream:read(BUFFER_SIZE)
		if not t then 
			self.running,t = false, self.mute
		end
		buf = buf .. t
	end
	local v = 0
	for i=1,siz do v = v + ((buf:byte(i)+128)%256)-128 end
	self.buf,v = buf:sub(siz+1),self.vol*v/(siz*4) + 32 + math.random()
	if v<0 then v=0 elseif v>63 then v=63 end
	return math.floor(v)
end

-- ===========================================================================-- PALETTE support
-- VIDEO filter aimed at mixing dropped frammes
local FILTER = {}
function FILTER:new()
    local o = {t={},cur={},map={}}
    setmetatable(o, self)
    self.__index = self
	for i=0,320*200*3-1 do o.cur[i] = 0 end
	local alpha = FILTER_ALPHA
	for i=0,255 do
		local x = PALETTE.linear(i)
		o.map[i] = {}
		for j=0,255 do
			local y = PALETTE.linear(j)
			local z = x*alpha + (1-alpha)*y
			o.map[i][j] = round(PALETTE.unlinear(z))
		end
	end
    return o
end
function FILTER:push(bytecode)
    local t = {}
    for i=1,bytecode:len() do t[i] = bytecode:byte(i) end
    table.insert(self.t, t)
    return self
end
if FILTER_ALPHA>0 then
function FILTER:push(bytecode)
    local t,map,cur = {},self.map,self.cur
    for i=1,bytecode:len() do 
		local x =map[cur[i]][bytecode:byte(i)] 
		t[i], cur[i] = x, x
	end
    -- table.insert(self.t, t)
	self.t[1] = t
    return self
end
end
function FILTER:flush()
    for i=FILTER_DEPTH,#self.t do table.remove(self.t,1) end
end
function FILTER:byte(offset)
    local m,t = #self.t, self.t
    if true or m==1 then
        return t[1][offset]
	elseif true then	
		local v,d = 0,0
        for i=1,m do v,d = v + t[i][offset]*i,d+i end
        return round(v/d)
    elseif m==2 then
        -- do return round((self.t[1][offset]+2*self.t[2][offset])*.3333333) end

        -- new strategy to improve compression: if change is small, keep previous value
        local a,b = t[1][offset],t[2][offset]
        local la,lb =
            -- (a/255)^2.2,(b/255)^2.2
            PALETTE.linear(a),PALETTE.linear(b)
		-- if math.abs(la-lb)>0 and la+lb>0 then print (math.abs(la-lb)/math.max(la,lb)) end
        if la~=lb 
		and	math.abs(la-lb)<FILTER_THRES*math.max(la,lb)
		and math.random()>.001
		then
            b,t[2][offset]=a,a
        end
        return b
    elseif m==3 then
        return round((t[1][offset] + 
		            2*t[2][offset] +
					3*t[3][offset])*.16666666)
    else
        local v,d = 0,0
        for i=1,m do v,d = v + t[i][offset]*i,d+i end
        return round(v/d)
    end
end
--  o.filter:new{1,4,10,30,10,4,1} -- {1,2,4,2,1} -- {1,4,10,4,1} -- {1,2,6,2,1} -- {1,1,2,4,2,1,1} -- {1,2,3,6,3,2,1} -- ,2,4,8,16,32}

-- ===========================================================================-- PALETTE support
-- flux video
local VIDEO = {}
function VIDEO:new(file, fps, w, h, screen_width, screen_height, interlace, pset)
    local o = {
        file = file,
        cpt = 1, -- compteur image
        width = w,
        height = h,
        screen_width = screen_width or w,
        screen_height = screen_height or h,
        interlace = interlace,
        fps = fps or 10,
        image = {},
        dither = nil,
        expected_size = 3*h*w, -- --54 + h*(math.floor((w*3+3)/4)*4),
        running=true,
        img_pattern=img_pattern,
        input = assert(io.popen(FFMPEG..
			' -i "'..file..'" -v 0 -r '..fps..
			' -s '..w..'x'..h..
			' -an -f rawvideo -pix_fmt rgb24 pipe:', 
			POPEN_READBIN)),
		pset = pset
    }
    setmetatable(o, self)
    self.__index = self

    -- initialise la progression dans les octets de l'image
    local function inside(x,min,max) return min<=x and x<max end
    local indices = {}
	local function fill(steps)
		local mod = 40*steps[#steps]
		for _,k in ipairs(steps) do -- {1,5,3,7,2,6,4,8} do
			k = k*40
			for i=0,7999 do if inside(i%mod,k-40,k) then table.insert(indices, i) end end
		end
	end
    if interlace=='p' or interlace=='a' then
		fill{1}
    elseif interlace=='i' then
        fill{1,2}
		local i1={}
		for j=0,7999 do if inside(j%80,40,44) then table.insert(i1,j) end end
		o.indices = function(prev,curr)
			local i,bak = 0,{}
			return function()
				i = i+1
				local val = indices[i]
				if val==1 then
					for _,j in ipairs(i1) do
						bak[j],curr[j] = curr[j],prev[j] 
					end
				elseif val==40 then
					for _,j in ipairs(i1) do
						curr[j] = bak[j]
					end
				elseif val==nil then
					i = nil
				end
				return i,val
			end
		end
    elseif interlace=='I' then
  		local dist = {}		
		for i=0,255 do for j=0,255 do
			local a,b,d = i,j,0
			for k=0,3 do
				d = d + math.abs((a % 4)-(b % 4))^2
				a,b = math.floor(a/4),math.floor(b/4)
			end
			dist[i*256+j] = d
		end end
		local cpt,i2l = 0,{}
		for i=0,7999 do i2l[i] = math.floor(i/40/CONFIG.px_size[2]) end
		o.indices = function(prev,curr)
			cpt = cpt + 1
			-- 11fps /4 --> 71%
			-- 13fps /4 --> 66%
			-- 17fps /4 --> 60%
			local t,THR = {},math.floor(8000/5)
			THR = math.floor(1.2*2000000/CYCLES/math.abs(FPS))
			for i=0,7999 do if prev[i]~=curr[i] then table.insert(t,i) end end
			-- print('+', m, #t)
			for _,m in ipairs{2,4} do
				if t[THR] then   
					local j = cpt%m
					for i=#t,0,-1 do t[i]=nil end
					for i=0,7999 do if prev[i]~=curr[i] and (i2l[i]%m)==j then table.insert(t,i) end end
				end
			end
			if false and t[THR] and t[math.floor(THR*1.6)] then
				m = 6
				local j = cpt%m
				for i=#t,0,-1 do t[i]=nil end
				for i=0,7999 do if prev[i]~=curr[i] and (i2l[i]%m)==j then table.insert(t,i) end end
			end
			if false and t[THR] and t[math.floor(THR*1.3)] then
				for i=#t,0,-1 do t[i]=nil end
				local m = 0
				for i=0,7999 do 
					local d = MODE==22 and 100 or dist[prev[i]*256+curr[i]]
					if (d or 0)>m then m=d else d = 1000 end
					if d > m/8 then table.insert(t,i) end
				end
			end
			local bak = {}
			for _,v in ipairs(t) do 
				if (v%40)==0 then bak[v],curr[v] = curr[v],prev[v] end
			end
			return function(a, i)
				i=i+1
				local v = a[i]
				if v then 
					if (v%40)==0 then curr[v] = bak[v] end
					return i,v 
				end
			end, t, 0
		end
    elseif interlace=='8x8' then
  		local dist = {}		
		for i=0,255 do for j=0,255 do
			local a,b,d = i,j,0
			for k=0,3 do
				d = d + math.abs((a % 4)-(b % 4))^2
				a,b = math.floor(a/4),math.floor(b/4)
			end
			dist[i*256+j] = d
		end end
		o.indices = function(prev,curr)
			local t,THR = {},math.floor(1000/4)
			for y=0,24 do for x=0,39 do
				local i = x+y*320
				local d = 0
				for j=i,i+319,40 do
					d = d + (dist[prev[j]*256+curr[j]] or 1000)
				end
				if d>0 then
					table.insert(t, {i=i,e=d})  
				end
			end end 
			if t[THR] then
				table.sort(t, function(i,j)	return i.e>j.e end)
				for i=#t,THR,-1 do t[i] = nil end
			end
			local l = {}
			for _,t in ipairs(t) do for i=t.i,t.i+319,40 do l[i]=true end end
			local ll = {}
			for i=0,7999 do if l[i] then table.insert(ll,i) end end
			return pairs(ll)
		end
    elseif interlace=='I' then
        local i1,i2,i3,i4={},{},{},{}
		for j=0,7999 do 
			if inside(j%120,0,40) then table.insert(i1,j) 
			elseif inside(j%120,40,80) then table.insert(i2,j) 
			else table.insert(i3,j) end 
		end
		indices = i1
		o.indices = function(prev,curr)
			local i = 0
			return function()
				i = i+1
				local val = indices[i]
				if not val then
					i = nil;
					if     indices==i1 then indices=i2
					elseif indices==i2 then indices=i3
					else                    indices=i1 end
				end
				return i,val
			end
		end
    elseif interlace=='i3' then
		fill{1,2,3}
		local i1,i2={},{}
		for j=0,7999 do 
			if     inside(j%120,40,44) then	table.insert(i1,j)
			elseif inside(j%120,80,84) then table.insert(i2,j)
			end
		end
		o.indices = function(prev,curr)
			local i,bak = 0,{}
			return function()
				i = i+1
				local val = indices[i]
				-- print(i,val); io.stdout:flush()
				if val==1 then
					for _,j in ipairs(i1) do
						bak[j],curr[j] = curr[j],prev[j] 
					end
				elseif val==40 then
					for _,j in ipairs(i2) do
						bak[j],curr[j-40],curr[j] = curr[j],bak[j-40],prev[j]
					end
				elseif val==80 then
					for _,j in ipairs(i2) do
						curr[j] = bak[j]
					end
				elseif val==nil then
					return nil
				end
				return i,val
			end
		end
    elseif interlace=='ii' then
		fill{1,2,3,4}
		local i1,i2,i3={},{},{}
		for j=0,7999 do 
			if     inside(j%160, 40, 44) then table.insert(i1,j)
			elseif inside(j%160, 80, 84) then table.insert(i2,j)
			elseif inside(j%160,120,124) then table.insert(i3,j)
			end
		end
		o.indices = function(prev,curr)
			local i,bak = 0,{}
			return function()
				i = i+1
				local val = indices[i]
				-- print(i,val); io.stdout:flush()
				if val==1 then
					for _,j in ipairs(i1) do
						bak[j],curr[j] = curr[j],prev[j] 
					end
				elseif val==40 then
					for _,j in ipairs(i2) do
						bak[j],curr[j-40],curr[j] = curr[j],bak[j-40],prev[j]
					end
				elseif val==80 then
					for _,j in ipairs(i3) do
						bak[j],curr[j-40],curr[j] = curr[j],bak[j-40],prev[j]
					end
				elseif val==120 then
					for _,j in ipairs(i3) do
						curr[j] = bak[j]
					end
				elseif val==nil then
					return nil
				end
				return i,val
			end
		end
    elseif interlace=='iii' then
		fill{2,4}
        for i=0,7999 do if inside(i%80,00,40) then table.insert(indices, i) end end
		local i1={}
		for j=0,7999 do if inside(j%80,0,4) then table.insert(i1,j) end end
		o.indices = function(prev,curr)
			local i,bak = 0,{}
			return function()
				i = i+1
				local val = indices[i]
				if val==40 then
					for _,j in ipairs(i1) do
						bak[j],curr[j] = curr[j],prev[j] 
					end
				elseif val==0 then
					for _,j in ipairs(i1) do
						curr[j] = bak[j]
					end
				elseif val==nil then
					i = nil
				end
				return i,val
			end
		end
    elseif interlace=='iiii' then
		fill{1,5,3,7,2,6,4,8}
    else
        error('Unknown interlace: ' .. interlace)
    end

	if not o.indices then o.indices = function(prev,curr) return ipairs(indices) end end

	o.zero = (MODE>=3) and ((MODE%2)==1) and 0xC0 or 0x00
    for i=0,7999+3 do o.image[i]=o.zero end

    o.filter = FILTER:new()

	o:pset(0,0,0,0,0)

    return o
end
function VIDEO:close()
    if io.type(self.input)=='file' then self.input:close() end
end
function VIDEO:init_dither()
    local m=CONFIG.dither
    m.w = #m[1]
    m.h = #m
    m.wh = m.w*m.h
    function m:get(i,j)
        return self[1+(j % self.h)][1+(i % self.w)]
    end
    self.dither = m
end
function VIDEO:transcode(p, o, v)
	if not self._transcode then
		self._transcode = {}
		for t=0,255 do 
			local tab = {}
			for v_=0,31 do
				local v = v_ % 16
				v = v + (v>=8 and -8 or 8)
				if v_<16 then
					v = v*8+t-(math.floor(t/8)%16)*8
				else
					v = (v>=8 and 128 or 0)+(v%8)+(math.floor(t/8)%16)*8
				end
				tab[v_] = v
			end
			self._transcode[t] = tab
		end
	end
	self.image[p] = self._transcode[self.image[p]][v + (o==0 and 0 or 16)]
end
if MODE==0 then
    -- GRAY
	local function pset(self, x,y, r,g,b)
		if self._r[r]+self._g[g]+self._b[b]>=self.dither:get(x,y) then
			local f = math.floor((x+y*320)/8)
			self.image[f] = self.image[f] + self._mask[x]
		end
	end
    function VIDEO:pset(x,y, r,g,b)
        if not self.dither then 
			self:init_dither()
            self._linear = {}
            for i=0,255 do self._linear[i]=PALETTE.linear(i) end
            self._mask = {}
            for i=0,319 do self._mask[i]=2^(7-(i%8)) end
			-- local dith = {}
			-- for x=0,319 do for y=0,199 do
				-- dith[x + 320*y] = self.dither:get(x,y)
			-- end end
			-- self.dither = dith
			self._r = {}
			self._g = {}
			self._b = {}
			for i=0,255 do
				self._r[i] = self._linear[i]*GRAY_R
				self._g[i] = self._linear[i]*GRAY_G
				self._b[i] = self._linear[i]*GRAY_B
			end
        end
		pset(self,x,y,r,g,b)
		self.pset = pset
    end
elseif MODE==1 then
    -- RGB
	local function pset(self, x,y, r,g,b)
		local f,d = self._linear,self.dither:get(x,y)
        local m,p,q = self._mask[x],math.floor((x+y*960)/8),self.image
        if f[r]>=d then q[p]    = q[p]    + m end
        if f[g]>=d then q[p+40] = q[p+40] + m end
        if f[b]>=d then q[p+80] = q[p+80] + m end
	end
    function VIDEO:pset(x,y, r,g,b)
        if not self.dither then 
			self:init_dither()
            self._linear = {}
            for i=0,255 do self._linear[i]=PALETTE.linear(i) end
            self._mask = {}
            for i=0,319 do self._mask[i]=2^(7-(i%8)) end
        end
		pset(self, x,y, r,g,b)
		self.pset = pset
    end
elseif MODE==2 or MODE==4 or MODE==10 or MODE==14 or MODE==18 or MODE==20 then
    -- MO (not transcode)
    function VIDEO:pset(x,y, r,g,b)
        if not self.dither then	self:init_dither(); self._cache = {} end
        local k = PALETTE.key(r,g,b)
        local t = self._cache[k]
        if not t then
            t = PALETTE:compute(self.dither.wh,r,g,b)
            self._cache[k] = t
        end
        local o,p,v = (x%2),math.floor(x/2) + y*40,t:byte(self.dither:get(x,y))
        if o==0 then v=v*16 end
        self.image[p] = self.image[p] + v
    end
elseif MODE==3 or MODE==5 or MODE==11 or MODE==15 or MODE==19 or MODE==21 then
    -- TO (transcode)
    function VIDEO:pset(x,y, r,g,b)
        if not self.dither then self:init_dither(); self._cache = {} end
        local k = PALETTE.key(r,g,b)
        local t = self._cache[k]
        if not t then
            t = PALETTE:compute(self.dither.wh,r,g,b)
            self._cache[k] = t
        end
        self:transcode(math.floor(x/2) + y*40,x%2,t:byte(self.dither:get(x,y)))
    end
elseif MODE==6 or MODE==7 then
    if MODE%2==0 then
        -- MO (not transcode)
        function VIDEO:plot(p,o,r,g,b)
            local p1,p2,img = p,p+40,self.image
            if ZIGZAG and o==1 then p1,p2=p2,p1 end
            o = o==0 and 16 or 1
            local t = b+r*3
            if t>0 then img[p1] = img[p1] +      t*o end
            if g>0 then img[p2] = img[p2] + (g+11)*o end
        end
    else
        -- TO (transcode)
        function VIDEO:plot(p,o,r,g,b)
            local t,o1,o2 = b+r*3,0,40
            if ZIGZAG and o==1 then o1,o2=o2,o1 end
            if t>0 then self:transcode(p+o1,o,t) end
            if g>0 then self:transcode(p+o2,o,g+11) end
        end
    end
	local function pset(self, x,y, r,g,b)
		local f,d = self._linear,self.dither:get(x,y)
        r,g,b = f[r][1],f[g][2],f[b][3]
        r = math.floor(r) +
        -- (r%1>self.dither:get(x,3*y+0) and 1 or 0)
        (r%1>=(r>=1 and d or self.dither:get(x,3*y+0)) and 1 or 0)
        -- (r%1>d and 1 or 0)
        g = math.floor(g) +
        -- (g%1>self.dither:get(x,3*y+1) and 1 or 0)
        (g%1>=(g>=1 and d or self.dither:get(x,3*y+1)) and 1 or 0)
        -- (g%1>d and 1 or 0)
        b = math.floor(b) +
        -- (b%1>self.dither:get(x,3*y+2) and 1 or 0)
        (b%1>=(b>=1 and d or self.dither:get(x,3*y+2)) and 1 or 0)
        -- (b%1>d and 1 or 0)

        self:plot(math.floor(x/2) + y*80,x%2,r,g,b)
	end
    function VIDEO:pset(x,y, r,g,b)
        if not self.dither then 
			self:init_dither()
            self._linear = {}
            for i=0,255 do
                local t = PALETTE.linear(i)
                self._linear[i]={t*3,t*4,t*2}
            end
            if EXPONENTIAL then
                for i=0,255 do
                    local t = PALETTE.exp_lin(i)
                    self._linear[i]={
                        t<=0 and -t or 1+t*2,
                        t<=0 and -t or 1+t*3,
                        t<=0 and -t or 1+t
                    }
                end
            end
        end
		pset(self, x,y, r,g,b)
		self.pset = pset
    end
elseif MODE==8 or MODE==9 then
    if MODE%2==0 then
        -- MO (not transcode)
        function VIDEO:plot(p,o,r,g,b)
            o = o==0 and 16 or 1
			local img = self.image
            if r>0 then img[p] = img[p] + r*o end p=p+40
            if g>0 then img[p] = img[p] + g*o end p=p+40
            if b>0 then img[p] = img[p] + b*o end
        end
    else
        -- TO (transcode)
        function VIDEO:plot(p,o,r,g,b)
            if r>0 then self:transcode(p   ,o,r) end
            if g>0 then self:transcode(p+40,o,g) end
            if b>0 then self:transcode(p+80,o,b) end
        end
    end
	local function pset(self, x,y, r,g,b)
		local f,d,int = self._linear,self.dither:get(x,y),math.floor
        r,g,b = f[r],f[g],f[b]
        r = int(r) + 
			(r%1>(r>=1 and d or self.dither:get(x,3*y+0)) and 1 or 0)
			-- (r%1>self.dither:get(x,3*y+0) and 1 or 0)
        g = int(g) + 
			(g%1>(g>=1 and d or self.dither:get(x,3*y+1)) and 1 or 0)
			-- (g%1>self.dither:get(x,3*y+1) and 1 or 0)
        b = int(b) + 
			(b%1>(b>=1 and d or self.dither:get(x,3*y+2)) and 1 or 0)
			-- (b%1>self.dither:get(x,3*y+2) and 1 or 0)
        if g>0 then g=g+5  end
        if b>0 then b=b+10 end
        if ZIGZAG then
            local z=x%4
            if z==0 then
                r,g,b = g,b,r
            elseif z==2 then
                r,g,b = b,r,g
            end
        end
        self:plot(math.floor(x/2) + y*120, x%2, r,g,b)
	end
    function VIDEO:pset(x,y, r,g,b)
        if not self.dither then 
			self:init_dither()
            self._linear = {}
            local f = function (i)
                return PALETTE.linear(i)*5
            end
            if true and EXPONENTIAL then
                f = function(i)
                    local t = PALETTE.exp_lin(i)
                    return t<=0 and -t or 1+t*4
                end
            end
            for i=0,255 do self._linear[i]=f(i) end
        end
        pset(self,x,y,r,g,b)
		self.pset = pset
    end
elseif MODE==12 or MODE==13 then
    if MODE%2==0 then
        -- MO (not transcode)
        function VIDEO:plot(p,o,v)
            self.image[p] = self.image[p] + (o==0 and 16*v or v)
        end
    else
        -- TO (transcode)
        function VIDEO:plot(p,o,v)
            self:transcode(p,o,v)
        end
    end
    function VIDEO:pset(x,y, r,g,b)
        if not self.dither then 
			self:init_dither()
            self._linear = {}
            for i=0,255 do self._linear[i]=PALETTE.linear(i) end
        end
        local f,d = self._linear,self.dither:get(x,y)
		local c = (f[r]>d and 1 or 0) + (f[g]>d and 2 or 0) + (f[b]>d and 4 or 0)
		-- if f[r]>d then c = c + 1 end
		-- if f[g]>d then c = c + 2 end
		-- if f[b]>d then c = c + 4 end
		if c>0 then self:plot(math.floor(x/2) + y*40, x%2, c) end
    end
elseif MODE==16 or MODE==17 then
	VIDEO.plot = MODE%2==0 
	and -- MO (not transcode)
        function(self,p,o,c)
			self.image[p] = self.image[p] + c*(o==0 and 16 or 1)
        end 
	or
		function(self,p,o,c)
            self:transcode(p,o,c)
        end
	local function pset(self, x,y, r,g,b)
		local l,f = self._l_R[r]+self._l_G[r]+self._l_B[b],math.floor
		self:plot(f(x/2) + y*40, x%2, f(l) +
			(((l%1)>=self.dither:get(x,y)) and 1 or 0))
	end
    function VIDEO:pset(x,y, r,g,b)
        if not self.dither then 
			self:init_dither()
            self._l_R = {}
			self._l_G = {}
			self._l_B = {}
            local f = PALETTE.linear
            for i=0,255 do
				self._l_R[i]=f(i)*15*GRAY_R
				self._l_G[i]=f(i)*15*GRAY_G
				self._l_B[i]=f(i)*15*GRAY_B
			end
        end
		pset(self,x,y,r,g,b)
		self.pset = pset
    end
elseif MODE==22 then
	local otab = {}
	for i=0,159 do otab[i] = 4^(3-(i%4)) end
	VIDEO.plot = function(self,p,o,c)
			self.image[p] = self.image[p] + c*o
        end 
	local function pset(self, x,y, r,g,b)
		local l,f = self._l_R[r]+self._l_G[r]+self._l_B[b],math.floor
		self:plot(f(x/4) + y*40, otab[x], f(l) +
			(((l%1)>=self.dither:get(x,y)) and 1 or 0))
	end
    function VIDEO:pset(x,y, r,g,b)
        if not self.dither then 
			self:init_dither()
            self._l_R = {}
			self._l_G = {}
			self._l_B = {}
            local f = PALETTE.linear
            for i=0,255 do
				self._l_R[i]=f(i)*3*GRAY_R
				self._l_G[i]=f(i)*3*GRAY_G
				self._l_B[i]=f(i)*3*GRAY_B
			end
        end
		pset(self,x,y,r,g,b)
		self.pset = pset
    end
else
    error('Invalid MODE: ' .. MODE)
end	
function VIDEO:clear()
    for p=0,#self.image do self.image[p] = self.zero end
end
function VIDEO:read_rgb24(raw)
	self:clear()
	local i,w,b,p = math.floor,self.width,FILTER.byte,self.pset
	local ox = i((self.screen_width - w)/2)
	local oy = i((self.screen_height - self.height)/2)
	local pr = self.filter:push(raw)
	for o=0,w*self.height-1 do
		local x,y,o = ox+(o % w), i(o/w)+oy,o*3
		p(self, x, y,
			b(pr,o+1), -- r
			b(pr,o+2), -- g
			b(pr,o+3)  -- b
		)
	end
	self.filter:flush()
end
function VIDEO:next_image()
    if not self.running then return end
	self.cpt = self.cpt + 1
	local buf,len = '', self.expected_size
	while len>0 do
		local b = self.input:read(len)
		if not b then break end
		buf,len = buf .. b,len - b:len()
	end
	-- print(self.cpt, len) io.stdout:flush()
	if len==0 then
		self:read_rgb24(buf)
	else
		self.running = false
		self.input:close()
		self.input = nil
	end
end
function VIDEO:skip_image()
    local bak = self.read_rgb24
    function self:read_rgb24(raw)
        self.filter:push(raw)
    end
    self:next_image()
    self.read_rgb24 = bak
end

local CONVERTER = {}
function CONVERTER:new(file, out, fps)
    file = file:gsub('^/cygdrive/(%w)/','%1:/')
    if not exists(file) then return nil end

    local o = {
        file      = file,
        out       = out,
        fps       = fps,
        interlace = CONFIG.interlace
    }

    -- recherche la bonne taille d'image
    local x,y = 80,45
    local IN,line = assert(io.popen(FFMPEG..' -i "'..file ..'" 2>&1', 'r'))
    for line in IN:lines() do
        local h,m,s = line:match('Duration: (%d+):(%d+):(%d+%.%d+),')
        if h and m and s then o.duration = h*3600 + m*60 +s end
        local a,b = line:match(', (%d+)x(%d+)')
        if a and b then x,y=a,b end
    end
    IN:close()
    if not o.duration then print(file..": Can't get duration!"); return nil end

    -- determine aspect ratio
    local max_ar
    for i=2,10 do
        local t = x*i/y
        t = math.abs(t-round(t))
        if max_ar==nil or t<max_ar then
            max_ar = t
            o.aspect_ratio = round(x*i/y)..':'..i
        end
    end

    -- size of image
    local W,H = 320,200
    local w,h = W,round(W*y/x)
    if h>H then
        w,h = round(H*x/y),H
    end
    o.w    = math.floor(w/CONFIG.px_size[1])
    o.h    = math.floor(h/CONFIG.px_size[2])
    o.W    = math.floor(W/CONFIG.px_size[1])
    o.H    = math.floor(H/CONFIG.px_size[2])

    setmetatable(o, self)
    self.__index = self
    return o
end
function CONVERTER:_new_video(fps)
    return VIDEO:new(self.file, fps or self.fps, self.w, self.h, self.W, self.H, self.interlace)
end
function CONVERTER:_stat()
    io.stdout:write(self.file..'\n')
    io.stdout:flush()

    -- auto determination des parametres
    local neg_fps = self.fps<0
	self.fps = math.abs(self.fps)
    local stat = self:_new_video((neg_fps and self.fps > FPS_MAX) and 3 or self.fps)
    stat.super_pset = stat.pset
    stat.histo = {}; for i=0,255 do stat.histo[i]=0 end
    function stat:pset(x,y, r,g,b)
        self:super_pset(x,y,r,g,b)
		local h = self.histo
        h[r],h[g],h[b] = h[r]+1,h[g]+1,h[b]+1
    end
    stat.super_next_image = stat.next_image
    stat.mill = {'|', '/', '-', '\\'}
    stat.mill[0] = stat.mill[4]
    stat.duration = self.duration
    function stat:next_image()
        self:super_next_image()
        io.stderr:write(string.format('> analyzing video...%s %d%%\r', self.mill[self.cpt % 4], percent(self.cpt/(self.fps*self.duration))))
        io.stderr:flush()
    end
    stat.trames = 0
    stat.prev_img = {}
    for i=0,7999 do stat.prev_img[i]=-1 end
    stat.type = {0,0,0,0}
    function stat:count_trames()
        local pos,prev,curr,c = 8000,stat.prev_img,stat.image,stat.trames

        -- local chg = 0
        -- for _,i in ipairs(indices) do
            -- if prev[i] ~= curr[i] then chg = chg+1 end
        -- end
		
        for _,i in self.indices(prev,curr) do
            while prev[i] ~= curr[i] do
				local k,t = i-pos
				if k<0 then 
					-- print(4,i,k)
					t,pos = 4,i
				elseif k<=1 then
					if k==0 and curr[i+1]==prev[i+1] then
						-- print(3,i,k)
						t,prev[i],prev[i+2],pos = 
						3,curr[i],curr[i+2],i+3
					else
						-- print(1,i,k)
						t,prev[pos],prev[pos+1],pos = 
						1,curr[pos],curr[pos+1],pos+2
					end
				elseif k<=257 then
					-- print(2,i,k)
					t,prev[i],pos = 
					2,curr[i],i+1
				else
					-- print(4,i,k)
					t,pos = 4,i
				end
				stat.type[t],c=stat.type[t]+1,c+(c % 171 == 169 and 2 or 1)
            end
        end
		stat.trames = c
    end

    while stat.running do
        stat:next_image()
        stat:count_trames()
    end
    io.stderr:write(string.rep(' ',79)..'\r')
    io.stderr:flush()

	-- nb de trames vidéos par image
	local avg_trames = (stat.trames/stat.cpt) * 1.10 -- 10% safety margin
	-- nombre de trames théoriques max par image
	local max_trames = 1000000/(self.fps*CYCLES)
	-- rapport entre les deux
	local ratio = max_trames / avg_trames
	-- print(avg_trames, max_trames, ratio)
	if neg_fps and self.fps>FPS_MAX then
		self.fps = FPS_MAX
	elseif ratio>1 or neg_fps then
		self.fps = math.min(round(self.fps*ratio),FPS_MAX)
	elseif ratio<1 then
		local zoom = ratio^.5
		self.w=round(self.w*zoom)
		self.h=round(self.h*zoom)
	end
	
	-- for i=0,255 do print('histo',i,stat.histo[i]) end
	
	-- find true black
	local total,threshold = 0
	for i=1,184 do total = total + stat.histo[i] end
	total,threshold = 0, total * .04
    stat.min = 0
    for i=1,184 do
        total = total + stat.histo[i]
        if total>threshold then
            stat.min = i-1
            break
        end
    end
	-- find true white
	stat.max = 255
	if stat.histo[253]>=stat.histo[254] then
		for i=252,184,-1 do
			if 0<stat.histo[i] and stat.histo[i]<stat.histo[i+1] then
				stat.max = i+1
				break
			end
		end
	end
	total,threshold = 0
	for i=127,stat.max-1 do total = total + stat.histo[i] end
	total,threshold = 0, total * .04
	for i=stat.max-1,127,-1 do
		total = total + stat.histo[i]
		if total>threshold then
			stat.max = i+1
			break
		end
	end
    -- print(stat.min .. '    ' .. stat.max .. '                  ')
    io.stdout:flush()
    local video_cor = {stat.min, 255/(stat.max - stat.min)}
    if MODE==10 or MODE==11 then video_cor = {0,1} end
    self.video_cor = video_cor

    -- info
    io.stdout:write(string.format('> %dx%d %s/%d (%s) %s at %d fps (%d%% zoom)\n',
        self.w, self.h, self.interlace, MODE, self.aspect_ratio,
        hms(self.duration, "%dh %dm %ds"), self.fps,
        percent(math.max(self.w/self.W,self.h/self.H))))
	local TOT = stat.type[1]+stat.type[2]+stat.type[3]+stat.type[4]
    io.stdout:write(string.format('> %d frames: %d%% %d%% %d%% %d%%\n',
                                    TOT,
                                    percent(stat.type[1]/TOT),
                                    percent(stat.type[2]/TOT),
                                    percent(stat.type[3]/TOT),
                                    percent(stat.type[4]/TOT)))
    io.stdout:flush()
end
function CONVERTER:process()
    -- collect stats
    self:_stat()

    -- flux audio/video
    local audio  = AUDIO:new(self.file)
    local video  = self:_new_video()

    -- adaptation luminosité
	-- print(self.video_cor[1],self.video_cor[2])
    if self.video_cor[1]~=0 or self.video_cor[2]~=1 then
        local cor = self.video_cor
        local super_pset = video.pset
        function video:pset(x,y, r,g,b)
            local function f(x)
                x = round((x-cor[1])*cor[2])
                return x<0 and 0 or x>255 and 255 or x
            end
            super_pset(self, x,y, f(r),f(g),f(b))
        end
    end

    -- vars pour la conversion
    local start          = os.time()
    local tstamp         = 0
    local cycles_per_img = 1000000 / self.fps
    local current_cycle  = 0
    local completed_imgs = 0
    local pos            = 8000

    -- init previous image
    local curr,prev = video.image,{}

	-- user feedback
	local last_etc=1e38
    local function info()
        local d = os.time() - start
		local t = "> %d%% %s (%3.1fx) e=%5.3f"
		t = t:format(
			percent(tstamp/self.duration), hms(tstamp),
			round(100*tstamp/(d==0 and 100000 or d))/100, completed_imgs/video.cpt)
		local etc = d*(self.duration-tstamp)/tstamp
		if d>10 then if etc>last_etc then etc = last_etc else last_etc = etc end end
		local etr = 5 -- etc>=90 and 10 or 5
		etc = round(etc/etr)*etr
		etc = etc>0 and d>10 and "ETC="..hms(etc) or ""
		t = t .. string.rep(' ', math.max(0,79-t:len()-etc:len())) .. etc 
		return t
	end
	
	local info_sec = 1
	
	local function update_info()
		if video.cpt>=info_sec then
			info_sec = info_sec + video.fps
			tstamp = tstamp + 1
			io.stdout:write(info() .. '\r')
			io.stdout:flush()
		end
	end 
	
	-- progressive
	local indices = function()
		local i=-1
		return function()
			i=i+1
			if i==8000 then return nil else return i,i end
		end
	end
	
    -- conversion
    video:skip_image()
    current_cycle = current_cycle + cycles_per_img
    video:next_image()
    while audio.running and video.running do
        update_info()
		local k,b0,b1,b2
        for _,i in indices(prev,curr) do
            while prev[i] ~= curr[i] do
				k = i - pos
				if k<0 then 
					b0,b1,b2,pos = 3,math.floor(i/256),i%256,i
				elseif k<=1 then
					if k==0 and curr[pos+1]==prev[pos+1] then
						b0,b1,b2  = 2,curr[pos],curr[pos+2]
						prev[pos] = curr[pos]; pos = pos+2
						prev[pos] = curr[pos]; pos = pos+1
					else
						b0,b1,b2  = 0,curr[pos],curr[pos+1]
						prev[pos] = curr[pos]; pos = pos+1
						prev[pos] = curr[pos]; pos = pos+1
					end
				elseif k<=257 then -- deplacement 8 bit
					b0,b1,b2,prev[i],pos = 1,k-2,curr[i],curr[i],i+1
				else -- deplacement arbitraire
					b0,b1,b2,pos = 3,math.floor(i/256),i%256,i
				end
				-- print(zz, b0, b1, b2, '-->', pos)
				current_cycle = current_cycle + self.out:frame(b0,b1,b2,audio)
            end
        end
		
		indices = video.indices
        completed_imgs = completed_imgs + 1
        video.filter:flush()

        -- skip image if drift is too big
        -- if current_cycle>cycles_per_img then print(current_cycle/cycles_per_img) end
        while current_cycle>=2*cycles_per_img do
			-- print('X', current_cycle, 2*cycles_per_img)
            video:skip_image()
            update_info()
            current_cycle = current_cycle - cycles_per_img
        end

        -- add padding if image is too simple
        while current_cycle<cycles_per_img do
			-- print('Y', current_cycle, cycles_per_img)
            current_cycle = current_cycle + self.out:frame(3,0,0,audio)
            pos = 0
        end

        -- next image
        video:next_image()
        current_cycle = current_cycle - cycles_per_img
    end

    audio:close()
    video:close()
	
	tstamp = self.duration
    io.stdout:write(info() .. '\n')
    io.stdout:flush()
end

local OUT = {}
function OUT:new(file)
    local o = {
        file = file,
        stream = nil,
        buf = '', -- buffer
    }
    setmetatable(o, self)
    self.__index = self
    return o
end
function OUT:open()
    local function file_content(size, file, extra)
        local buf = ''
        local INP = assert(io.open(file, 'rb'))
        while true do
            local t = INP:read(256)
            if not t then break end
            if extra and t:len()<256 then t = t .. extra end
            if t:len()>256 then
                buf = buf .. t:sub(1,256) .. string.rep(string.char(0),256)
                t = t:sub(257)
            end
            buf = buf .. t .. string.rep(string.char(0),512-t:len())
        end
        INP:close()
        size = size - buf:len()
        if size<0 then
            print('size',size)
            error('File ' .. file .. ' is too big')
        end
        return buf .. string.rep(string.char(0),size)
    end
    local function raw(name, source)
        local raw = BIN .. name .. '.raw'
        if not exists(raw) then
            error(raw .. ' is missing. Please create via\n' ..
			'c6809 -bd -am -oOP ' .. source .. ' ' .. raw)
        end
        return raw
    end

    local asm_mode=CONFIG.asm_mode --(MODE<6 and MODE) or (MODE%2==0 and 4 or 5)

	self.stream = assert(io.open(self.file, 'wb'))
    self.stream:write(file_content(1*512, raw('bootblk', 'asm/bootblk.ass')))
    self.stream:write(file_content(7*512, raw('player4'..asm_mode, '-dMODE='..asm_mode..' asm/player4.ass'),
                                           PALETTE:file_content()))
end
function OUT:frame(buf0,buf1,buf2,audio)
	if not self.stream then self:open() end
    local ret = 1
    self.buf = self.buf .. string.char(buf0+audio:next_sample()*4,buf1,buf2)
    if self.buf:len()==3*170 then
        local s1 = audio:next_sample()
        local s2 = audio:next_sample()
        local s3 = audio:next_sample()
        local t = s1*1024 + math.floor(s2/2)*32 + math.floor(s3/2)
        self.stream:write(self.buf .. string.char(math.floor(t/256), t%256))
        self.buf = ''
        ret = ret + 3
    end
    return ret*CYCLES
end
function OUT:close()
	if self.stream then
		self:frame(3,255,255, {next_sample=compo(0)})
		self.stream:write(self.buf .. string.rep(string.char(255),512-self.buf:len()))
		self.stream:close()
		self.stream = nil
	end
end

-- ===========================================================================
-- replace URLs
function replace_yt(arg)
	local updated = false
	local out = {}
	for i,vid in ipairs(arg) do
		if vid:sub(1,8)=='https://' or vid:sub(1,7)=='http://' then
			updated = updated or 0==os.execute(YT_DL .. ' -U -q')
			local all={}
			if vid:find('/playlist?') then
				local IN,line = assert(io.popen(YT_DL..' -i --geo-bypass --get-id '..vid, 'r'))
				for line in IN:lines() do
					table.insert(all,'https://youtu.be/'.. line)
					-- table.insert(all, '"'..line..'"')
				end
				IN:close()
			else
				table.insert(all,vid)
			end
			local YT_DL=YT_DL..' --no-check-certificate'
			for _,vid in ipairs(all) do
				local IN,line,file = assert(io.popen(YT_DL..' --geo-bypass --restrict-filenames -o "%(title)s--%(id)s" --get-filename ' .. vid, 'r'))
				for line in IN:lines() do file = file or line .. '.mkv' end
				IN:close()
				if file then
					local ok = exists(file) and 0 or 1
					ok = ok==0 and 0 or os.execute(YT_DL .. ' -f 18 --geo-bypass --merge-output-format mkv -o "'.. file .. '" ' .. vid)
					ok = ok==0 and 0 or os.execute(YT_DL .. ' -f "best[height<=200]" --geo-bypass --merge-output-format mkv -o "'.. file .. '" ' .. vid)
					ok = ok==0 and 0 or os.execute(YT_DL .. ' --geo-bypass --merge-output-format mkv -o "'.. file .. '" ' .. vid)
					if ok==0 then table.insert(out, file) end
				end
			end
		else
			table.insert(out,vid)
		end
	end
	return out
end

-- ===========================================================================
-- main process
arg = replace_yt(arg)
if #arg==0 then os.exit(0) end
local file = basename(arg[1])
if #arg>1 then -- infer name
    local function substrings(s)
        local MIN=4
        local subs = {set={}}
        function subs:longest()
            local l=''
            for _,s in pairs(self.set) do
                if s:len()>l:len() then l=s end
            end
            return l
        end
        function subs:intersect(other)
            for s in pairs(self.set) do
                if other.set[s]==nil then self.set[s]=nil end
            end
        end
        for i=1,s:len()-MIN do
            for j=i+MIN,s:len() do
                local t = s:sub(i,j)
                subs.set[t:lower()]=t
            end
        end
        return subs
    end
    local subs,num,first = substrings(file),0
    for i,f in ipairs(arg) do
        local TMP = CONVERTER:new(f,nil,3)
        if TMP then
			first = first or f
            subs:intersect(substrings(basename(f)))
			num = num + 1
        end
    end
    file = subs:longest():gsub("%W+$", "")
    if file:len()<=4 then file = basename(first) end
    file = file.."#"..num
    io.stderr:write("\n===> "..file.." <===\n")
    io.stderr:flush()
end
PALETTE:init(CONFIG.palette(CONVERTER,VIDEO))
local out = OUT:new(MODE..'_'..file..'.sd')
local first = true
for _,f in ipairs(arg) do
    local conv = CONVERTER:new(f,out,FPS)
    if conv then 
		if not first then io.stdout:write('\n') else first=nil end
		conv:process() 
	end
end
out:close()
