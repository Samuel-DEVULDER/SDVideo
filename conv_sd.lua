-- conversion fichier video en fichier sd-drive
--
-- version alpha 0.07
---
-- Samuel DEVULDER Aout-Oct 2018

-- code experimental. essaye de determiner
-- les meilleurs parametres (fps, taille ecran
-- pour respecter le fps ci-dessous. 

-- gray peut être true ou false suivant qu'on
-- veut une sortie couleur ou pas. Le gris est
-- generalement plus rapide et/ou avec un ecran
-- plus large. Si on le laisse à nil, l'outil 
-- détermine automatiquement le mode couleur de
-- la video.

-- Work in progress!
-- =================
-- le code doit être nettoye et rendu plus
-- amical pour l'utilisateur

local function round(x)
	return math.floor(x+.5)
end

local BUFFER_SIZE   = 4096
local FPS_MAX       = 30
local TIMEOUT       = 2
local GRAY_THR      = .1 -- .07
local FILTER_DEPTH  = 1
local MAX_AUDIO_AMP = 16

local tmp = 'tmp'
local img_pattern =  tmp..'/img%05d.bmp'
local cycles = 199 -- cycles par échantillons audio
local hz = round(8000000/cycles)/8
local fps = 12
local gray = nil
local interlace = nil	
local dither = 8 -- -8
local ffmpeg = 'tools\\ffmpeg'
local mode = 'p'

local SPECIAL_4 = false -- true

if SPECIAL_4 then
	gray = true
	dither = 3
end

local file = arg[1]:gsub('^/cygdrive/(%w)/','%1:/')

local function exists(file)
   local ok, err, code = os.rename(file, file)
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

if not exists(file) then os.exit(0) end

local function percent(x)
	return round(math.min(1,x)*100)
end

local function hms(secs, fmt)
	secs = round(secs)
	return string.format(fmt or "%d:%02d:%02d", 
			math.floor(secs/3600), math.floor(secs/60)%60, math.floor(secs)%60)
end

-- if file:match('miga') then
	-- gray = false
	-- interlace = false
-- end

-- nom fichier
io.stdout:write('\n'..file..'\n')
io.stdout:flush()

-- recherche la bonne taille d'image
local x,y = 80,45
local IN,line = assert(io.popen(ffmpeg..' -i "'..file ..'" 2>&1', 'r'))
for line in IN:lines() do 
	local h,m,s = line:match('Duration: (%d+):(%d+):(%d+%.%d+),')
	if h and m and s then duration = h*3600 + m*60 +s end
	local a,b = line:match(', (%d+)x(%d+)')
	if a and b then x,y=a,b end
end
IN:close()
if not duration then error("Can't get duration!") end
local max_ar
for i=2,10 do
	local t = x*i/y
	t = math.abs(t-round(t))
	if max_ar==nil or t<max_ar then
		max_ar = t
		aspect_ratio = round(x*i/y)..':'..i
	end
end
local w = 80
local h = round(w*y/x)
if h>50 then
   h = 50
   w = round(h*x/y)
end

if mode==nil then
	mode = (h*w>32*48 and 'i') or 'p'
end

-- initialise la progression dans les octets de l'image
local lines,indices = {},{}
for i=math.floor((50-h)/2)*4,(math.floor((50-h)/2)+h)*4-1 do
	if i%4<3 then
		table.insert(lines, i)
	end
end
if mode=='p' or mode=='a' then
	-- rien
elseif mode=='i' then
	local t = {}
	for i=1,#lines,2 do
		table.insert(t, lines[i])
	end
	for i=2,#lines,2 do
		table.insert(t, lines[i])
	end
	lines = t
elseif mode=='2' then
	local t = {}
	for i=1,#lines,3 do
		table.insert(t, lines[i])
	end
	for i=2,#lines,3 do
		table.insert(t, lines[i])
	end
	table.sort(t)
	for i=3,#lines,3 do
		table.insert(t, lines[i])
	end
	lines = t
elseif mode=='3' then
	local t = {}
	for i=2,#lines,3 do
		table.insert(t, lines[i])
	end
	for i=1,#lines,3 do
		table.insert(t, lines[i])
	end
	for i=2,#lines,3 do
		table.insert(t, lines[i])
	end
	lines = t
elseif mode=='I' then
	local t = {}
	for i=1,#lines,6 do
		table.insert(t, lines[i])
		table.insert(t, lines[i+1])
		table.insert(t, lines[i+2])
	end
	for i=4,#lines,6 do
		table.insert(t, lines[i])
		table.insert(t, lines[i+1])
		table.insert(t, lines[i+2])
	end
	lines = t
elseif mode=='ipi' then
	local t = {}
	for i=1+math.floor(#lines/3),math.floor(2*#lines/3) do
		table.insert(t, lines[i])
	end
	for i=1,math.floor(#lines/3),2 do
		table.insert(t, lines[i])
	end
	for i=1+math.floor(2*#lines/3),#lines,2 do
		table.insert(t, lines[i])
	end
	for i=2,math.floor(#lines/3),2 do
		table.insert(t, lines[i])
	end
	for i=2+math.floor(2*#lines/3),#lines,2 do
		table.insert(t, lines[i])
	end
	lines = t
elseif mode=='r' then
	local size = #lines
	for i = size, 1, -1 do
		local rand = math.random(size)
		lines[i], lines[rand] = lines[rand], lines[i]
	end
elseif mode=='3i' then
	-- 14 + 14+12
	local w = 2+4+4+4+4+4
	local x = math.floor((39-w)/2)
	for _,j in ipairs(lines) do
		for i=j*40+x,j*40+x+w-1 do
			table.insert(indices,i)
		end
	end
	for j=1,#lines,2 do
		for i=lines[j]*40,lines[j]*40+x-1 do
			table.insert(indices,i)
		end
		for i=lines[j]*40+x+w,lines[j]*40+39 do
			table.insert(indices,i)
		end
	end
	for j=2,#lines,2 do
		for i=lines[j]*40,lines[j]*40+x-1 do
			table.insert(indices,i)
		end
		for i=lines[j]*40+x+w,lines[j]*40+39 do
			table.insert(indices,i)
		end
	end
	lines = {}
elseif mode=='d' then
	lines = {}
	for x=0,39 do
		for y=0,math.min(24,x) do
			local p = y*320+(x-y)
			for j=p,p+319,40 do
				table.insert(indices,j)
			end
		end
	end
	for y=1,24 do
		for x=0,24-y do
			local p = (y+x)*320+39-x
			for j=p,p+319,40 do
				table.insert(indices,j)
			end
		end
	end
else 
	error('Unknown mode: ' .. mode)
end

for _,i in ipairs(lines) do
	-- print(i)
	for j=i*40,i*40+39 do
		table.insert(indices, j)
	end
end
-- os.exit(0)
-- flux audio
local AUDIO = {}
function AUDIO:new(file, hz)
	hz=round(8*hz)
	local o = {
		hz = hz,
		stream = assert(io.popen(ffmpeg..' -i "'..file ..'" -v 0 -f u8 -ac 1 -ar '..hz..' -acodec pcm_u8 pipe:', 'rb')),
		amp = MAX_AUDIO_AMP, -- volume auto
		min = 255,
		buf = '', -- buffer
		running = true
	}
	setmetatable(o, self)
	self.__index = self
	return o
end
function AUDIO:close()
	self.stream:close()
end
function AUDIO:next_sample()
	local buf = self.buf
	if buf:len()<=8 then
		local t = self.stream:read(BUFFER_SIZE)
		if not t then 
			self.running = false
			t = string.char(0,0,0,0,0,0,0,0)
		end
		buf = buf .. t
	end
	function sample(offset)
		return ((buf:byte(offset)+128)%256)-128
	end
	-- print(buf:byte(1), sample(1))
	local v = (buf:byte(1) + buf:byte(2) + buf:byte(3) + buf:byte(4) +
	           buf:byte(5) + buf:byte(6) + buf:byte(7) + buf:byte(8))*.125 
	self.buf = buf:sub(9)

	v = v - self.min
	if v<0 then
		self.min = .3*v + self.min
		v = 0
	else
		self.min = v/self.hz + self.min
	end
	
	-- auto volume
	self.amp = self.amp*(1 + 1/self.hz)
	if self.amp>MAX_AUDIO_AMP then self.amp = MAX_AUDIO_AMP end
	local z=v*self.amp
	if z>255 then z=255; self.amp = 255/v end
	-- print(vv,self.amp)
	-- dither
	v = math.max(math.min(z/4 + math.random() + math.random() - 1, 63),0)
	return math.floor(v)
end

-- filtre video
local FILTER = {}
function FILTER:new()
	local o = {t={}}
	setmetatable(o, self)
	self.__index = self	
	return o
end

function FILTER:push(bytecode)
	table.insert(self.t, bytecode)
	return self
end

function FILTER:flush()
	-- for i=#self.t,1,-1 do self.t[i]=nil end
	-- self.t = {}
	for i=FILTER_DEPTH,#self.t do table.remove(self.t,1) end
end

function FILTER:byte(offset)
	local m = #self.t
	if m==1 then
		return self.t[1]:byte(offset)
	elseif m==2 then
		return math.floor(.5+(self.t[1]:byte(offset)+2*self.t[2]:byte(offset))*.3333333)
	elseif m==3 then
		return math.floor(.5+(self.t[1]:byte(offset)+2*self.t[2]:byte(offset)+3*self.t[3]:byte(offset))*.16666666)
	else
		local v,d = 0,0
		for i=1,m do 
			local t=i
			v = v + self.t[i]:byte(offset)*t
			d = d + t
		end
		return math.floor(.5 + v/d)
	end
end
--	o.filter:new{1,4,10,30,10,4,1} -- {1,2,4,2,1} -- {1,4,10,4,1} -- {1,2,6,2,1} -- {1,1,2,4,2,1,1} -- {1,2,3,6,3,2,1} -- ,2,4,8,16,32}		

-- flux video
local VIDEO = {}
function VIDEO:new(file, w, h, fps, gray)
	if isdir(tmp) then
		os.execute('del >nul /s /q '..tmp)
	else
		os.execute('md '..tmp)
	end

	local o = {
		cpt = 1, -- compteur image
		width = w,
		height = h,
		fps = fps or 10,
		gray = gray or false,
		image = {},
		dither = nil,
		expected_size = 54 + h*(math.floor((w*3+3)/4)*4),
		running=true,
		streams = {
			inp = assert(io.open(file, 'rb')),
			out = assert(io.popen(ffmpeg..' -i pipe: -v 0 -r '..fps..' -s '..w..'x'..h..' -an '..img_pattern, 'wb')),
		}
	}
	setmetatable(o, self)
	self.__index = self
	for i=0,7999+3 do o.image[i]=0 end
	
	o.filter = FILTER:new()
	
	return o
end
function VIDEO:close()
	if io.type(self.streams.inp)=='file' then self.streams.inp:close() end
	if io.type(self.streams.out)=='file' then self.streams.out:close() end
end
function VIDEO:init_dither()
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
				local s=''
				for i=1,#t do
					for j=1,#t[1] do
						if j>1 then s=s..',' end
						s = s..string.format("%9.6f",t[i][j])
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
					-- print(i, l[i][1], l[i][2]	)
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
				local i = ((x-1+w2)%w)-w/2
				local j = ((y-1+h2)%h)-h/2
				m[y][x] = math.exp(-40*(i^2+j^2)/(w*h))
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
					for i,j in rangexy(#GAUSS[1],#GAUSS) do
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
			for i=0,math.floor(m*n/10) do
				t[math.random(n)][math.random(m)] = 1
			end
			for i=1,m*n*10 do
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
		-- print(vnc)
		return vnc
	end
	
	local m = {{1}}
	-- m={{1,3},{3,1}}
	for i=1,dither do m = bayer(m) end
	if dither<0 then m = vac(-dither,-dither) end
	
	m.w = #m
	m.h = #m[1]
	function m:get(i,j)
		return self[1+(i % self.w)][1+(j % self.h)]
	end
	
	local x = 0
	for i=1,m.w do
		for j=1,m.h do
			-- print(m[i][j])
			x = math.max(x, m[i][j])
		end
	end
	x = 1/(x + 1)
	for i = 1,m.w do
		for j = 1,m.h do
			m[i][j] = m[i][j]*x
		end
	end
	self.dither = m
end
function VIDEO:linear(u)
	return u<0.04045 and u/12.92 or (((u+0.055)/1.055)^2.4)
end
function VIDEO:pset(x,y, r,g,b)
	if not self._linear then
		self._linear = {}
		for i=0,255 do self._linear[i] = self:linear(i/255) end
	end
	r,g,b = self._linear[r],self._linear[g],self._linear[b]
	if not self.dither then VIDEO:init_dither()	end
	local d = self.dither:get(x,y)
	
	if not self._pset then
		self._pset = {}
		self._pset[0] = {}
		self._pset[1] = {}
		for i=0,15 do
			self._pset[0][i] = {}
			self._pset[1][i] = {}
			for j=0,3 do
				self._pset[0][i][j] = (i%4)     + 4*j
				self._pset[1][i][j] = (i-(i%4)) +   j
			end
		end
	end
	local o,p = x%2,math.floor(x/2) + y*160
	local function v(v) 
		-- assert(0<=v and v<=3, 'v=' .. v)
		self.image[p] = self._pset[o][self.image[p]][v]
		p = p+40
	end	
	if interlace then
		local q = self.cpt%2 == 0
		function v(v) 
			if q then
				self.image[p] = self._pset[o][self.image[p]][v]
				q = false
			else
				q = true
			end
			p = p+40
		end	
	end
	
	if self.gray then
		if SPECIAL_4 then
			r = (.2126*r + .7152*g + .0722*b)*3 + d
			if     r>=2 then	v(3)
			elseif r>=1 then	v(2)
			else 				v(0)	
			end
			if     r>=3 then	v(3)
			elseif r>=2 then	v(2)
			elseif r>=1 then	v(1)
			else 				v(0)	
			end
			if     r>=3 then	v(3)
			elseif r>=2 then	v(1)
			else 				v(0)	
			end
		else
			r = (.2126*r + .7152*g + .0722*b)*9 + d
			if     r>=4 then	v(3)
			elseif r>=2 then	v(2)
			elseif r>=1 then	v(1)
			else 				v(0)	
			end
			if     r>=7 then	v(3)
			elseif r>=5 then	v(2)
			elseif r>=3 then	v(1)
			else 				v(0)	
			end
			if     r>=9 then	v(3)
			elseif r>=8 then	v(2)
			elseif r>=6 then	v(1)
			else 				v(0)	
			end
		end
	else
		v(math.floor(r*3 + d))
		v(math.floor(g*3 + d))
		v(math.floor(b*3 + d))
	end
end
function VIDEO:read_bmp(bytecode) -- (https://www.gamedev.net/forums/topic/572784-lua-read-bitmap/)
	-- Helper function: Parse a 16-bit WORD from the binary string
	local function ReadWORD(str, offset)
		local loByte = str:byte(offset);
		local hiByte = str:byte(offset+1);
		return hiByte*256 + loByte;
	end

	-- Helper function: Parse a 32-bit DWORD from the binary string
	local function ReadDWORD(str, offset)
		local loWord = ReadWORD(str, offset);
		local hiWord = ReadWORD(str, offset+2);
		return hiWord*65536 + loWord;
	end
	
	-------------------------
	-- Parse BITMAPFILEHEADER
	-------------------------
	local offset = 1;
	local bfType = ReadWORD(bytecode, offset);
	if(bfType ~= 0x4D42) then
		error("Not a bitmap file (Invalid BMP magic value)");
		return;
	end
	local bfOffBits = ReadWORD(bytecode, offset+10);

	-------------------------
	-- Parse BITMAPINFOHEADER
	-------------------------
	offset = 15; -- BITMAPFILEHEADER is 14 bytes long
	local biWidth = ReadDWORD(bytecode, offset+4);
	local biHeight = ReadDWORD(bytecode, offset+8);
	local biBitCount = ReadWORD(bytecode, offset+14);
	local biCompression = ReadDWORD(bytecode, offset+16);
	if(biBitCount ~= 24) then
		error("Only 24-bit bitmaps supported (Is " .. biBitCount .. "bpp)");
		return;
	end
	if(biCompression ~= 0) then
		error("Only uncompressed bitmaps supported (Compression type is " .. biCompression .. ")");
		return;
	end

	---------------------
	-- Parse bitmap image
	---------------------
	local ox = math.floor((80 - biWidth)/4)*2
	local oy = math.floor((50 - biHeight)/2)
	local oo = 4*math.floor((biWidth*biBitCount/8 + 3)/4)
	local pr = self.filter:push(bytecode)
	for y = biHeight-1, 0, -1 do
		offset = bfOffBits + oo*y + 1;
		for x = ox, ox+biWidth-1 do
			self:pset(x, oy,
						pr:byte(offset+2), -- r
						pr:byte(offset+1), -- g
						pr:byte(offset  )  -- b
			);
			offset = offset + 3;
		end
		oy = oy+1
	end
	self.filter:flush()
end
function VIDEO:next_image()
	if not self.running then return end
	
	-- nom nouvelle image
	local name = img_pattern:format(self.cpt); self.cpt = self.cpt + 1
	local buf = ''
	local f = io.open(name,'rb')
	if f then 
		buf = f:read(self.expected_size) or buf
		f:close()
	end
		
	-- si pas la bonne taille, on nourrit ffmpeg
	-- jusqu'a obtenir un fichier BMP complet
	local timeout = TIMEOUT
	while buf:len() ~= self.expected_size and timeout>0 do
		buf = self.streams.inp:read(BUFFER_SIZE)
		if buf then
			self.streams.out:write(buf)
			self.streams.out:flush()
		else 
			if io.type(self.streams.out)=='file' then
				self.streams.out:close()
			end
			-- io.stdout:write('wait ' .. name ..'\n')
			-- io.stdout:flush()
			local t=os.time()+1
			repeat until os.time()>t
			timeout = timeout - 1
		end
		f = io.open(name,'rb')
		if f then 
			buf = f:read(self.expected_size) or ''
			f:close()
			timeout = TIMEOUT
		else
			buf = ''
		end
	end
	
	-- effacement temporaire
	os.remove(name)

	if buf and buf:len()>0 then 
		-- nettoyage de l'image précédente
		-- for i=0,7999+3 do self.image[i]=0 end
		-- lecture image
		self:read_bmp(buf)
	else
		if self.cpt==2 and not self._avi_hack then
			self:close()
			self.streams.inp = assert(io.popen(ffmpeg..' -i "'..file..'" -v 0 -f avi pipe:','rb'))
			self.streams.out = assert(io.popen(ffmpeg..' -i pipe: -v 0 -r '..self.fps..' -s '..self.width..'x'..self.height..' -an '..img_pattern, 'wb'))
			self._avi_hack   = true
			self.cpt = 1
			self:next_image()
		else
			self.running = false
		end
	end
end
function VIDEO:skip_image()
	local bak = self.read_bmp
	function self:read_bmp(bytecode)
		self.filter:push(bytecode)
	end
	self:next_image()
	self.read_bmp = bak
end

-- auto determination des parametres
local stat = VIDEO:new(file,w,h,round(fps/2),gray)
stat.super_pset = stat.pset
stat.histo = {n=0}; for i=0,255 do stat.histo[i]=0 end
function stat:pset(x,y, r,g,b)
	self.histo[r] = self.histo[r]+1
	self.histo[g] = self.histo[g]+1
	self.histo[b] = self.histo[b]+1
	
	self:super_pset(x,y,r,g,b)
	
	if gray==nil then
		if self.mnt==nil then
			self.mnt = {n=0,r1=0,g1=0,b1=0,r2=0,g2=0,b2=0}
		end
		local m = math.max(r,g,b)
		if m>10 then 
			m=1/m
			r,g,b = r*m,g*m,b*m
		
			m = self.mnt
			m.n  = m.n + 1
			
			m.r1 = m.r1 + r
			m.g1 = m.g1 + g
			m.b1 = m.b1 + b
			
			m.r2 = m.r2 + r*r
			m.g2 = m.g2 + g*g
			m.b2 = m.b2 + b*b
		end
	end
end
stat.super_next_image = stat.next_image
stat.mill = {'|', '/', '-', '\\'}
stat.mill[0] = stat.mill[4]
function stat:next_image()
	self:super_next_image()
	io.stderr:write(string.format('> analyzing...%s %d%%\r', self.mill[self.cpt % 4], percent(self.cpt/self.fps/duration)))
	io.stderr:flush()
end
stat.trames = 0
stat.prev_img = {}
for i=0,7999 do stat.prev_img[i]=-1 end
function stat:count_trames()
	local pos,prev,curr = 0,stat.prev_img,stat.image
	local chg = 0
	for _,i in ipairs(indices) do
		if prev[i] ~= curr[i] then chg = chg+1 end
	end
	
	for _,i in ipairs(indices) do
	-- for i=0,7999 do
		if prev[i] ~= curr[i] then 
			stat.trames = stat.trames + 1
			local k = i - pos
			if k<0 then k=8000 end
			if k<=2 then
				prev[pos] = curr[pos]; pos = pos+1
				prev[pos] = curr[pos]; pos = pos+1
				prev[pos] = curr[pos]; pos = pos+1
				prev[pos] = curr[pos]; pos = pos+1
			elseif k<=256 then
				pos = i
				prev[pos] = curr[pos]; pos = pos+1
				prev[pos] = curr[pos]; pos = pos+1
			else
				pos = i
				prev[pos] = curr[pos]; pos = pos+1
			end
		end
	end
end
while stat.running do
	stat:next_image()
	stat:count_trames()
end
io.stderr:write(string.rep(' ',79)..'\r')
io.stderr:flush()

-- determine if monochrome
if gray==nil then
	local m = stat.mnt
	m.r1,m.g1,m.b1 = m.r1/m.n,m.g1/m.n,m.b1/m.n
	m.r2,m.g2,m.b2 = m.r2/m.n,m.g2/m.n,m.b2/m.n

	local e = 0
	e = e + math.sqrt(m.r2 - m.r1*m.r1)
	e = e + math.sqrt(m.g2 - m.g1*m.g1)
	e = e + math.sqrt(m.b2 - m.b1*m.b1)
	e = e/3
	
	gray = e<GRAY_THR
	-- print(gray,e)
	-- print(m.r1, m.g1, m.b1)
	-- if not gray then os.exit() end
end

local max_trames = 1000000/fps/cycles
local avg_trames = (stat.trames/stat.cpt) * 1.03 -- 001 -- 0.11% safety margin
local ratio = max_trames / avg_trames
-- print(ratio)
if ratio>1 then
	fps = math.min(math.floor(fps*ratio),interlace and 2*FPS_MAX or FPS_MAX)
elseif ratio<1 then
	local zoom = ratio^.5
	w=math.floor(w*zoom)
	h=math.floor(h*zoom)
end
stat.total = 0
for i=1,255 do
	stat.total = stat.total + stat.histo[i]
end
stat.threshold_min = (gray and .03 or .05)*stat.total
stat.min = 0
for i=1,255 do
	stat.min = stat.min + stat.histo[i]
	if stat.min>stat.threshold_min then
		stat.min = i-1
		break
	end
end
stat.max = 0
stat.threshold_max = (gray and .03 or .05)*stat.total
for i=254,1,-1 do
	stat.max = stat.max + stat.histo[i]
	if stat.max>stat.threshold_max then
		stat.max = i+1
		break
	end
end
-- print(stat.min, stat.max)
-- io.stdout:flush()
local video_cor = {stat.min, 255/(stat.max - stat.min)}

-- fichier de sortie
function file_content(file, size)
	local INP = assert(io.open(file, 'rb'))
	local buf = ''
	while true do
		local t = INP:read(256)
		if not t then break end
		buf = buf .. t .. string.rep(string.char(0),512-t:len())
	end
	size = size - buf:len()
	if size<0 then
		print('size',size)
		error('File ' .. file .. ' is too big')
	end
	return buf .. string.rep(string.char(0),size)
end

local OUT = assert(io.open(file:gsub('.*[/\\]',''):gsub('%.[%a%d]+','')..'.sd', 'wb'))
OUT:write(file_content('bin/bootblk.raw', 512))
OUT:write(file_content(gray and 'bin/player1.raw' or 'bin/player0.raw', 7*512))

-- flux audio/video
local audio  = AUDIO:new(file, hz)
local video  = VIDEO:new(file,w,h,fps,gray)

-- adaptation luminosité
video.super_pset = video.pset
function video:pset(x,y, r,g,b)
	local function f(x)
		x = round((x-video_cor[1])*video_cor[2]);
		return x<0 and 0 or x>255 and 255 or x
	end
	self:super_pset(x,y, f(r),f(g),f(b))
end

-- vars pour la cvonvesion
local start          = os.time()
local tstamp         = 0
local cycles_per_img = 1000000 / fps
local current_cycle  = 0
local completed_imgs = 0
local pos            = 8000
local blk            = ''

-- init previous image
local curr = video.image
local prev = {}
for i=0,7999+3 do prev[i] = -1 end

function test_fin_bloc()
	if blk:len()==3*170 then
		local s1 = audio:next_sample()
		local s2 = audio:next_sample()
		local s3 = audio:next_sample()
		local t = s1*1024 + math.floor(s2/2)*32 + math.floor(s3/2)
	
		blk = blk .. string.char(math.floor(t/256), t%256)
		OUT:write(blk)
		blk = ''

		current_cycle = current_cycle + cycles*3
	end
end

local _recalc_indices_d = {}
for i=0,255 do 
	local a = {i % 4, math.floor(i/4)%4}
	local b = {math.floor(i/16)%4, math.floor(i/64)%4}
	_recalc_indices_d[i] = math.abs(a[1]-b[1]) + math.abs(a[2]-b[2])
end
function recalc_indices_d()
	local d = {} 
	for i=0,7999,160 do
		local e,f=0,0
		for j=i,i+119 do
			if curr[j]~=prev[j] then
				f = f + 1
				e = e + (_recalc_indices_d[prev[j]*16+curr[j]] or 6)
			end
		end
		table.insert(d, {e=e/(f>0 and f or 1), i=i})
	end
	
	local MAX_DELAY = 1000000/fps -- 100*1000 -- µs
	local e,h = 0,math.floor(MAX_DELAY *8 / (w*3*cycles))
	local PRE = math.floor(h/3)
	-- print(h,PRE)
	for i=PRE,math.min(PRE+h,50) do e=e+d[i].e end
	local m,p = e,1
	for i=PRE+1,50-h do
		e = e - d[i-1].e + d[i+h].e
		if e>m then m,p = e,i-PRE end
	end
	-- print(p,m)
	indices = {}
	for i=p,50 do
		for j=d[i].i,d[i].i+119 do table.insert(indices, j) end
	end
	for i=1,p-1 do
		for j=d[i].i,d[i].i+119 do table.insert(indices, j) end
	end
end

-- conversion
io.stdout:write(string.format('> %dx%d %s (%s) %s at %d fps (%d%% zoom, %s)\n',
	w, h, mode, aspect_ratio,
	hms(duration, "%dh %dm %ds"), fps, percent(math.max(w/80,h/50)), gray and "gray" or "color"))
io.stdout:flush()
video:skip_image()
current_cycle = current_cycle + cycles_per_img
video:next_image()
while audio.running do
	-- infos
	if video.cpt % video.fps == 0 then
		tstamp = tstamp + 1
		local d = os.time() - start
		local t = "> %d%% %s (%3.1fx) e=%5.3f a=(x%+d)*%-3.1f"
		t = t:format(
			percent(tstamp/duration), hms(tstamp),
			round(100*tstamp/(d==0 and 100000 or d))/100, completed_imgs/video.cpt,
			-audio.min, audio.amp
			)
		local etc = d*(duration-tstamp)/tstamp
		local etr = etc>=90 and 10 or 5
		etc = round(etc/etr)*etr
		etc = etc>0 and d>10 and "ETC="..hms(etc) or ""
		t = t .. string.rep(' ', math.max(0,79-t:len()-etc:len())) .. etc .. "\r"
		io.stdout:write(t)
		io.stdout:flush()
	end
	
	if mode=='a' then recalc_indices_d() end
	
	for _,i in ipairs(indices) do
	-- for i=0,7999 do
		if prev[i] ~= curr[i] then 
			local k = i - pos
			if k<0 then k=8000 end
			pos = i
			local buf = {audio:next_sample()*4,0,0}
			-- if mode=='i' and w==80 then
				-- if k<=2 and ((pos-k)%40)+4>=40
			-- end
			
			if k<=2 then
				-- deplacement trop faible: mise a jour des 4 octets
				-- videos suivants d'un coup
				pos = pos - k
				buf[1] = buf[1] + 1
				buf[2] = curr[pos+0]*16 + curr[pos+1]
				buf[3] = curr[pos+2]*16 + curr[pos+3]
				prev[pos] = curr[pos]; pos = pos+1
				prev[pos] = curr[pos]; pos = pos+1
				prev[pos] = curr[pos]; pos = pos+1
				prev[pos] = curr[pos]; pos = pos+1
			elseif k<=256 then
				-- deplacement 8 bit
				buf[1] = buf[1] + 0
				buf[2] = k%256
				buf[3] = curr[pos+0]*16 + curr[pos+1]
				prev[pos] = curr[pos]; pos = pos+1
				prev[pos] = curr[pos]; pos = pos+1
			else
				-- deplacement arbitraire
				buf[1] = buf[1] + 2 + math.floor(pos/4096)
				buf[2] = math.floor(pos/16) % 256
				buf[3] = (pos%16)*16 + curr[pos]
				prev[pos] = curr[pos]; pos = pos + 1
			end
			blk = blk .. string.char(buf[1], buf[2], buf[3])
			current_cycle = current_cycle + cycles
			
			test_fin_bloc()
		end
	end
	completed_imgs = completed_imgs + 1

	video.filter:flush()
	
	-- skip image if drift is too big
	-- if current_cycle>cycles_per_img then print(current_cycle/cycles_per_img) end
	while current_cycle>2*cycles_per_img do
		video:skip_image()
		if video.cpt % video.fps == 0 then
			tstamp = tstamp + 1
		end
		current_cycle = current_cycle - cycles_per_img
	end		
	
	-- add padding if image is too simple
	while current_cycle<cycles_per_img do
		blk = blk .. string.char(audio:next_sample()*4+2,0,curr[0])
		pos = 1
		current_cycle = current_cycle + cycles
		test_fin_bloc()
	end
	
	-- next image
	video:next_image()
	current_cycle = current_cycle - cycles_per_img
end
test_fin_bloc()
blk = blk .. string.char(3,255,255)
OUT:write(blk .. string.rep(string.char(255),512-blk:len()))
OUT:close()
audio:close()
video:close()
io.stdout:write('\n')
io.stdout:flush()
