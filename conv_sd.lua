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

local function env(var, default)
	return loadstring('return ' .. (os.getenv(var) or default))();
end
local function round(x)
	return math.floor(x+.5)
end

local CYCLES        = 199 -- cycles par échantillons audio
local BUFFER_SIZE   = 4096
local FPS_MAX       = 30
local TIMEOUT       = 2
local GRAY_THR      = .1 -- .07
local FILTER_DEPTH  = 1
local GRAY          = env('GRAY','nil')
local FPS           = env('FPS',11)

local interlace     = nil -- useless
local dither        = env('DITH', 8) -- -8 for vac
local mode          = 'p'
local FFMPEG        = 'tools\\ffmpeg.exe'
local C6809         = 'tools\\c6809.exe'

local SPECIAL_4 = false -- experiment ==> no interrest
if SPECIAL_4 then
	GRAY = 1
	dither = 3
end

-- sanitise
if GRAY~=nil and GRAY~=0 and GRAY~=1 then 
	error("Env. var. GRAY shall be unset or set to 0 or 1.")
end
if type(FPS)~='number' then
	error('Env. var. ENV shall be a positive integer.')
else
	FPS = round(FPS)
end

-- if os.execute('cygpath -W >/dev/null 2>&1')==0 then
	-- ffmpeg = 'tools/ffmpeg.exe' 
-- end

if nil==os.getenv('CYG_SYS_BASHRC') then
	FFMPEG = 'tools/ffmpeg.exe' 
	C6809  = 'tools/c6809.exe'
end
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
local function percent(x)
	return round(math.min(1,x)*100)
end
local function hms(secs, fmt)
	secs = round(secs)
	return string.format(fmt or "%d:%02d:%02d", 
			math.floor(secs/3600), math.floor(secs/60)%60, math.floor(secs)%60)
end
function basename(file)
    return file:gsub('^/cygdrive/(%w)/','%1:/'):gsub('.*[/\\]',''):gsub('%.[%a%d]+','')
end

-- os.exit(0)
-- flux audio
local AUDIO = {}
function AUDIO:new(file)
	-- value such that group_size*1000000/cycles is the most integer
	local size = 8 
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
	local o = {
		hz = hz,
		stream = assert(io.popen(FFMPEG..' -i "'..file ..'" -v 0 -af loudnorm -f u8 -ac 1 -ar '..hz..' -acodec pcm_u8 pipe:', 'rb')),
		size = size,
		mute = '',
		buf = '', -- buffer
		running = true
	}
	for i=1,size do o.mute = o.mute .. string.char(128) end
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
	local v,g = 0,4
	for i=1,siz do v = v + buf:byte(i) end
	self.buf,v = buf:sub(siz+1),g*(v/(siz*4)-32) + 32
	if v<0 then v=0 elseif v>63 then v=63 end
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
function VIDEO:new(file, w, h, fps)
    local o = {
        file = file,
        cpt = 1, -- compteur image
        width = w,
        height = h,
        screen_width = 80,
        screen_height = 50,
        interlace = interlace,
        fps = fps or 10,
        image = {},
        dither = nil,
        expected_size = 3*h*w, -- --54 + h*(math.floor((w*3+3)/4)*4),
        running=true,
        input = assert(io.popen(FFMPEG..
			' -i "'..file..'" -v 0 -r '..fps..
			' -s '..w..'x'..h..
			' -an -f rawvideo -pix_fmt rgb24 pipe:', 
			'rb'))
    }
    setmetatable(o, self)
    self.__index = self

	for i=0,7999+3 do o.image[i]=0 end
	
	o.filter = FILTER:new()
	
	return o
end
function VIDEO:close()
	if io.type(self.input)=='file' then self.input:close() end
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
		self:init_dither()
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
	r,g,b = self._linear[r],self._linear[g],self._linear[b]
	local d = self.dither:get(x,y)
	
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
				self.image[p],q,p = self._pset[o][self.image[p]][v],false,p+40
			else
				q,p = true,p+40
			end
		end	
	end
	
	if GRAY==1 then
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
function VIDEO:clear()
    for p=0,#self.image do self.image[p] = 0 end
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

--------------------------------------------------
local CONVERTER = {}
function CONVERTER:new(file, out, fps)
    file = file:gsub('^/cygdrive/(%w)/','%1:/')
    if not exists(file) then return nil end

    local o = {
        file      = file,
        out       = out,
        fps       = fps,
        interlace = interlace
    }

    -- recherche la bonne taille d'image
    local x,y = 80,50
    local IN,line = assert(io.popen(FFMPEG..' -i "'..file ..'" 2>&1', 'r'))
    for line in IN:lines() do
        local h,m,s = line:match('Duration: (%d+):(%d+):(%d+%.%d+),')
        if h and m and s then o.duration = h*3600 + m*60 + s end
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
	local w = 80
	local h = round(w*y/x)
	if h>50 then
	   h = 50
	   w = round(h*x/y)
	end

	if mode==nil then
		mode = (h*w>32*48 and 'i') or 'p'
	end
	o.mode = mode
    o.w    = w
    o.h    = h

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
	o.indices = indices

    setmetatable(o, self)
    self.__index = self
    return o
end
function CONVERTER:_new_video()
    return  VIDEO:new(self.file, self.w, self.h, self.fps)
end
function CONVERTER:_stat()
    io.stdout:write('\n'..self.file..'\n')
    io.stdout:flush()

	-- auto determination des parametres
	local stat = VIDEO:new(self.file,self.w,self.h,7)
	stat.super_pset = stat.pset
	stat.histo = {n=0}; for i=0,255 do stat.histo[i]=0 end
	function stat:pset(x,y, r,g,b)
		local h=self.histo
		h[r] = h[r]+1
		h[g] = h[g]+1
		h[b] = h[b]+1
		
		self:super_pset(x,y,r,g,b)
		
		if GRAY==nil then
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
	local indices,duration = self.indices,self.duration
	function stat:next_image()
		self:super_next_image()
		io.stderr:write(string.format('> analyzing...%s %d%%\r', self.mill[self.cpt % 4], percent(self.cpt/self.fps/duration)))
		io.stderr:flush()
	end
	stat.trames = 0
	stat.prev_img = {}
	for i=0,7999 do stat.prev_img[i]=-1 end
	function stat:count_trames()
		local pos,prev,curr,k = 0,stat.prev_img,stat.image
		for _,i in ipairs(indices) do
			if prev[i] ~= curr[i] then 
				stat.trames,k = stat.trames + 1,i-pos
				if k<0 then k=8000 end
				if k<=2 then
					prev[pos],pos = curr[pos],pos+1
					prev[pos],pos = curr[pos],pos+1
					prev[pos],pos = curr[pos],pos+1
					prev[pos],pos = curr[pos],pos+1
				elseif k<=256 then
					pos = i
					prev[pos],pos = curr[pos],pos+1
					prev[pos],pos = curr[pos],pos+1
				else
					pos = i
					prev[pos],pos = curr[pos],pos+1
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
	if GRAY==nil then
		local m = stat.mnt
		m.r1,m.g1,m.b1 = m.r1/m.n,m.g1/m.n,m.b1/m.n
		m.r2,m.g2,m.b2 = m.r2/m.n,m.g2/m.n,m.b2/m.n

		local e = 0
		e = e + math.sqrt(m.r2 - m.r1*m.r1)
		e = e + math.sqrt(m.g2 - m.g1*m.g1)
		e = e + math.sqrt(m.b2 - m.b1*m.b1)
		e = e/3
		
		GRAY = e<GRAY_THR and 1 or 0
	end

	local neg_fps = self.fps<0
	self.fps = math.abs(self.fps)
	local max_trames = 1000000/(self.fps*CYCLES)
	local avg_trames = (stat.trames/stat.cpt) * 1.03 -- 001 -- 0.11% safety margin
	local ratio = max_trames / avg_trames
	if neg_fps and self.fps>FPS_MAX then
		self.fps = FPS_MAX
	elseif ratio>1 or neg_fps then
		self.fps = math.min(math.floor(self.fps*ratio),self.interlace and 2*FPS_MAX or FPS_MAX)
	elseif ratio<1 then
		local zoom = ratio^.5
		self.w=math.floor(self.w*zoom)
		self.h=math.floor(self.h*zoom)
	end
	stat.total = 0
	for i=1,255 do
		stat.total = stat.total + stat.histo[i]
	end
	stat.threshold_min = (GRAY==1 and .03 or .05)*stat.total
	stat.min = 0
	for i=1,255 do
		stat.min = stat.min + stat.histo[i]
		if stat.min>stat.threshold_min then
			stat.min = i-1
			break
		end
	end
	stat.max = 0
	stat.threshold_max = (GRAY==1 and .03 or .03)*stat.total
	for i=254,1,-1 do
		stat.max = stat.max + stat.histo[i]
		if stat.max>stat.threshold_max then
			stat.max = i+1
			break
		end
	end
	-- print(stat.min, stat.max)
	-- io.stdout:flush()
	self.video_cor = {stat.min, 255/(stat.max - stat.min)}

    -- info
    io.stdout:write(string.format('> %dx%d %s (%s) %s at %d fps (%d%% zoom, %s)\n',
		self.w, self.h, mode,self.aspect_ratio,hms(duration, "%dh %dm %ds"), self.fps, 
		percent(math.max(self.w/80,self.h/50)), GRAY==1 and "gray" or "color"))
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
                x = round((x-cor[1])*cor[2]);
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
	for i=0,7999+3 do prev[i] = -1 end

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
	local indices = {}
	for i=0,7999 do indices[i] = i end

    -- conversion
    video:skip_image()
    current_cycle = current_cycle + cycles_per_img
    video:next_image()
    while audio.running and video.running do
		local b0,b1,b2,k
        update_info()
        for _,i in ipairs(indices) do
            if prev[i] ~= curr[i] then
				k = i - pos
				if k<0 then k=8000 end
				if k<=2 then
					-- deplacement trop faible: mise a jour des 4 octets
					-- videos suivants d'un coup
					b0 = 1
					b1 = curr[pos+0]*16 + curr[pos+1]
					b2 = curr[pos+2]*16 + curr[pos+3]
					prev[pos] = curr[pos]; pos = pos+1
					prev[pos] = curr[pos]; pos = pos+1
					prev[pos] = curr[pos]; pos = pos+1
					prev[pos] = curr[pos]; pos = pos+1
				elseif k<=256 then
					-- deplacement 8 bit
					b0,b1,b2 = 0,k%256,curr[i]*16 + curr[i+1]
					prev[i],prev[i+1],pos=curr[i],curr[i+1],i+2
				else
					-- deplacement arbitraire
					b0 = 2 + math.floor(i/4096)
					b1 = math.floor(i/16) % 256
					-- print(i, curr[i])
					b2 = (i%16)*16 + curr[i]
					prev[i],pos = curr[i],i+1
				end
				current_cycle = current_cycle + self.out:frame(b0,b1,b2,audio)
			end
		end
        completed_imgs = completed_imgs + 1
        video.filter:flush()
		indices = self.indices

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
            current_cycle = current_cycle + self.out:frame(2,0,0,audio)
            pos = 1
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
        local raw = 'bin/' .. name .. '.raw'
        if not exists(raw) then
            local cmd = C6809..' -bd -am -oOP ' .. source .. ' ' .. raw
            print(cmd) io.flush()
            os.execute(cmd)
        end
        return raw
    end

    local asm_mode=GRAY

	self.stream = assert(io.open(self.file, 'wb'))
    self.stream:write(file_content(1*512, raw('bootblk', 'asm/bootblk.ass')))
    self.stream:write(file_content(7*512, raw('player'..asm_mode, '-dGRAY='..asm_mode..' asm/player.ass')))
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
		self:frame(3,255,255, {next_sample=function() return 32 end})
		self.stream:write(self.buf .. string.rep(string.char(255),512-self.buf:len()))
		self.stream:close()
		self.stream = nil
	end
end

-- ===========================================================================
-- main process
if #arg==0 then os.exit(0) end
table.sort(arg)
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
local out = OUT:new(file..'.sd')
for _,f in ipairs(arg) do
    local conv = CONVERTER:new(f,out,FPS)
    if conv then conv:process() end
end
out:close();
