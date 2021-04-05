-- conversion fichier video en fichier sd-drive
--
-- version alpha 0.01
---
-- Samuel DEVULDER Aout 2018

-- code experimental. essaye de determiner
-- les meilleurs parametres (fps, taille ecran
-- pour respecter le fps ci-dessous. 

-- gray peut etre true ou false suivant qu'on
-- veut une sortie couleur ou pas. Le gris est
-- generalement plus rapide et/ou avec un ecran
-- plus large.

-- Work in progress!
-- le code doit etre nettoye et rendu plus
-- amical pour l'utilisateur

local function round(x)
	return math.floor(x+.5)
end

local tmp = 'tmp'
local img_pattern =  tmp..'/img%05d.bmp'
local cycles = 199 -- cycles par échantillons audio
local hz = round(8000000/cycles)/8
local fps = 10
local gray = false
local interlace = false --gray
local dither = 2
local ffmpeg = 'tools\\ffmpeg'
local mode = 'p'
local skip = true

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

-- if file:match('miga') then
	-- gray = false
	-- interlace = false
-- end

-- nom fichier
io.stdout:write('\n'..file..'\n')
io.stdout:flush()

-- initialise la progression dans les octets de l'image
local next_pos,next_pos0,next_pos1 = {}
if mode=='p' then
	local i=0
	while i<8000 do
		local j = i+1
		if j%160==120 then 
			j = j + 40 
			for k=i+1,i+39 do next_pos[k] = j end
		end
		next_pos[i] = j
		i = j
	end
	next_pos0 = next_pos
	next_pos1 = next_pos
elseif mode=='i' then
	-- r* 0->2
	-- g  1->4
	-- b* 2->5
	-- -  3->5
	-- r  4->6
	-- g* 5->8
	-- b  6->9
	-- -  7->8
	next_pos0 = {}
	next_pos1 = {}
	for q=0,7999,8*40 do
		for p=q,q+39 do
			next_pos0[p + 0*40] = p + 0*40 + 1
			next_pos0[p + 1*40] = q + 2*40
			next_pos0[p + 2*40] = p + 2*40 + 1
			next_pos0[p + 3*40] = q + 5*40
			next_pos0[p + 4*40] = q + 5*40
			next_pos0[p + 5*40] = p + 5*40 + 1
			next_pos0[p + 6*40] = q + 8*40
			next_pos0[p + 7*40] = q + 8*40
			
			next_pos1[p + 0*40] = q + 1*40
			next_pos1[p + 1*40] = p + 1*40 + 1
			next_pos1[p + 2*40] = q + 4*40
			next_pos1[p + 3*40] = q + 4*40
			next_pos1[p + 4*40] = p + 4*40 + 1
			next_pos1[p + 5*40] = q + 6*40
			next_pos1[p + 6*40] = p + 6*40 + 1
			next_pos1[p + 7*40] = q + 9*40
		end
		next_pos0[q+39 + 0*40] = q + 2*40
		next_pos0[q+39 + 2*40] = q + 5*40
		next_pos0[q+39 + 5*40] = q + 8*40

		next_pos1[q+39 + 1*40] = q + 4*40
		next_pos1[q+39 + 4*40] = q + 6*40
		next_pos1[q+39 + 6*40] = q + 9*40
	end
	for p=8000-40,8000+3 do
		next_pos0[p] = 8000
		next_pos1[p] = 8000
	end
	next_pos = next_pos0	
elseif mode=='i' and gray then
	-- r* 0->1
	-- g* 1->4
	-- b  2->5
	-- -  3->5
	-- r* 4->6
	-- g  5->6
	-- b  6->10
	-- -  7->8
	next_pos0 = {}
	next_pos1 = {}
	for q=0,7999,8*40 do
		for p=q,q+39 do
			next_pos0[p + 0*40] = p + 0*40 + 1
			next_pos0[p + 1*40] = p + 1*40 + 1
			next_pos0[p + 2*40] = q + 4*40
			next_pos0[p + 3*40] = q + 4*40
			next_pos0[p + 4*40] = p + 4*40 + 1
			next_pos0[p + 5*40] = q + 8*40
			next_pos0[p + 6*40] = q + 8*40
			next_pos0[p + 7*40] = q + 8*40
			
			next_pos1[p + 0*40] = q + 2*40
			next_pos1[p + 1*40] = q + 2*40
			next_pos1[p + 2*40] = p + 2*40 + 1
			next_pos1[p + 3*40] = q + 5*40
			next_pos1[p + 4*40] = q + 5*40
			next_pos1[p + 5*40] = p + 5*40 + 1
			next_pos1[p + 6*40] = p + 6*40 + 1
			next_pos1[p + 7*40] = q + 10*40
		end
		next_pos0[q+39 + 1*40] = q + 4*40
		next_pos0[q+39 + 4*40] = q + 8*40

		next_pos1[q+39 + 2*40] = q + 5*40
		next_pos1[q+39 + 6*40] = q + 10*40
	end
	for p=8000-40,8000+3 do
		next_pos0[p] = 8000
		next_pos1[p] = 8000
	end
	next_pos = next_pos0
else
	error('Unknown mode: ' .. mode)
end


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

-- flux audio
local AUDIO = {}
function AUDIO:new(file, hz)
	local o = {
		stream = assert(io.popen(ffmpeg..' -i "'..file ..'" -v 0 -f u8 -ac 1 -ar '..round(8*hz)..' -acodec pcm_u8 -', 'rb')),
		cor = {8,255}, -- volume auto
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
		local t = self.stream:read(65536)
		if not t then 
			self.running = false
			t = string.char(0,0,0,0,0,0,0,0)
		end
		buf = buf .. t
	end
	local v = (buf:byte(1) + buf:byte(2) + buf:byte(3) + buf:byte(4) +
				buf:byte(5) + buf:byte(6) + buf:byte(7) + buf:byte(8))*.125
	self.buf = buf:sub(9)
	-- auto volume
	if v<self.cor[2]     then self.cor[2]=v end
	v = v-self.cor[2]
	if v*self.cor[1]>255 then self.cor[1]=255/v end
	v = v*self.cor[1]
	-- dither
	v = math.min(v + math.random(0,3), 255)
	return math.floor(v/4)
end

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
		indices = {},
		dither = nil,
		expected_size = 54 + h*(math.floor((w*3+3)/4)*4),
		running=true,
		streams = {
			inp = assert(io.open(file, 'rb')),
			out = assert(io.popen(ffmpeg..' -i - -v 0 -r '..fps..' -s '..w..'x'..h..' -an '..img_pattern, 'wb')),
		}
	}
	setmetatable(o, self)
	self.__index = self
	for i=0,7999+3 do o.image[i]=0 end	
	for i=0,7999 do
		if (i%160)<120 then
			table.insert(o.indices, i)
		end
	end
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
	local m = {{1}}
	for i=1,dither do m = bayer(m) end
	local x = 0
	for i=1,#m do
		for j=1,#m[1] do
			x = math.max(x, m[i][j])
		end
	end
	x = 1/(x + 1)
	for i = 1,#m do
		for j = 1,#m[1] do
			m[i][j] = m[i][j]*x
		end
	end
	m.w = #m
	m.h = #m[1]
	function m:get(i,j)
		return self[1+(i % self.w)][1+(j % self.h)]
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
				self._pset[0][i][j] = (i%4) + 4*j
				self._pset[1][i][j] = (i-(i%4)) + j
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
	for y = biHeight-1, 0, -1 do
		offset = bfOffBits + oo*y + 1;
		for x = ox, ox+biWidth-1 do
			self:pset(x, oy, 
					  bytecode:byte(offset+2), -- r
					  bytecode:byte(offset+1), -- g
					  bytecode:byte(offset));  -- b
			offset = offset + 3;
		end
		oy = oy+1
	end
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
	local timeout = 5
	while buf:len() ~= self.expected_size and timeout>0 do
		buf = self.streams.inp:read(65536)
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
			timeout = 5
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
		self.running = false
	end
end
function VIDEO:skip_image()
	local bak = self.pset
	self.pset = function() end
	self:next_image()
	self.pset = bak
end

-- auto determination des parametres
local stat = VIDEO:new(file,w,h,round(fps/2),gray)
stat.super_pset = stat.pset
stat.histo = {n=0}; for i=0,255 do stat.histo[i]=0 end
function stat:pset(x,y, r,g,b)
	stat.histo[r] = stat.histo[r]+1
	stat.histo[g] = stat.histo[g]+1
	stat.histo[b] = stat.histo[b]+1
	self:super_pset(x,y,r,g,b)
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
	for _,i in ipairs(self.indices) do
	-- for i=0,7999 do
		if prev[i] ~= curr[i] then 
			stat.trames = stat.trames + 1
			local k = i - pos
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
local max_trames = 1000000/fps/cycles
local avg_trames = (stat.trames/stat.cpt) * 1.02 -- 11% safety margin
local ratio = max_trames / avg_trames
if ratio>1 then
	fps = math.min(math.floor(fps*ratio),interlace and 50 or 25)
elseif ratio<1 then
	local zoom = ratio^.5
	w=math.floor(w*zoom)
	h=math.floor(h*zoom)
end
stat.total = 0
for i=1,255 do
	stat.total = stat.total + stat.histo[i]
end
stat.threshold_min = (gray and .03 or .03)*stat.total
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
local OUT = assert(io.open(file:gsub('.*[/\\]',''):gsub('%.[%a%d]+','')..'.sd', 'wb'))

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
OUT:write(file_content('bin/bootblk.raw', 512))
OUT:write(file_content(gray and 'bin/player1.raw' or 'bin/player0.raw', 7*512))

-- conversion

local audio = AUDIO:new(file, hz)
local video = VIDEO:new(file,w,h,fps,gray)
local tstamp = 0
local start = os.time()
local cycles_per_img = 1000000 / fps
local current_cycle  = 0
local completed, completed_imgs = 0,0
local pos = 0
local prev_img = {}
for i=0,7999+3 do prev_img[i] = -1 end
local blk = ''

video.super_pset = video.pset
function video:pset(x,y, r,g,b)
	local function f(x)
		x = round((x-video_cor[1])*video_cor[2]);
		return x<0 and 0 or x>255 and 255 or x
	end
	self:super_pset(x,y, f(r),f(g),f(b))
end

function trame_fin()
	local s1 = audio:next_sample()
	local s2 = audio:next_sample()
	local s3 = audio:next_sample()
	
	local t = s1*1024 + math.floor(s2/2)*32 + math.floor(s3/2)
	
	return string.char(math.floor(t/256), t%256)
end

video:next_image()

io.stdout:write('> '..w..'x'..h..' ('..aspect_ratio..') '..duration..'s at '..fps..'fps ('..mode..')\n')
io.stdout:flush()

if true then
	local prev,curr=prev_img,video.image
	local blk = ''
	local pos=8000
	while audio.running do
		for _,i in ipairs(video.indices) do
		-- for i=0,7999 do
			if prev[i] ~= curr[i] then 
				local k = i - pos
				if k<0 then k=8000 end
				pos = i
				local buf = {audio:next_sample()*4,0,0}
				if k<=2 then
					-- deplacement trop faible: mise a jour des 4 octets videos suivants d'un coup
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
				
				if blk:len()==170*3 then
					blk = blk .. trame_fin()
					current_cycle = current_cycle + cycles*3
					OUT:write(blk)
					blk = ''
				end
			end
		end
		completed_imgs = completed_imgs + 1
		-- skip image if drift is too big
		while current_cycle>2*cycles_per_img do
			video:skip_image()
			if video.cpt % video.fps == 0 then
				tstamp = tstamp + 1
			end
			current_cycle = current_cycle - cycles_per_img
		end		
		-- add padding if image is too simple
		while current_cycle<cycles_per_img do
			blk = blk .. string.char(audio:next_sample()*4+2,0,0)
			current_cycle = current_cycle + cycles
			if blk:len()==170*3 then
				blk = blk .. trame_fin()
				current_cycle = current_cycle + cycles*3
				OUT:write(blk)
				blk = ''
			end
		end
		
		-- infos
		if video.cpt % video.fps == 0 then
			tstamp = tstamp + 1
			local d = os.time() - start; if d==0 then d=1000000000 end
			local t = "> %d%% %d:%02d:%02d (%3.1fx) e=%5.3f a=(x%+d)*%.1g         \r"
			t = t:format(
				percent(tstamp/duration),
				math.floor(tstamp/3600), math.floor(tstamp/60)%60, tstamp%60, 
				math.floor(100*tstamp/d)/100, completed_imgs/video.cpt,
				-audio.cor[2], audio.cor[1])
			io.stdout:write(t)
			io.stdout:flush()
		end
		-- next image
		video:next_image()
		current_cycle = current_cycle - cycles_per_img
	end
else -- orig
function trame_video() 
	if current_cycle >= cycles_per_img then
		-- image complete ?
		if completed==0 and not skip then
			for i=0,7999 do if prev_img[i]==video.image[i] then completed = completed + 1 end end
			completed = completed / 8000
		end
		completed_imgs = completed_imgs + completed
	
		-- image suivante
		if skip and current_cycle > 2*cycles_per_img then
			local bak=video.image
			video.image={}
			for i=0,8003 do video.image[i] = 0 end
			repeat
				-- io.stderr:write('skip\n')
				video:next_image()
				current_cycle = current_cycle - cycles_per_img
			until current_cycle <= cycles_per_img
			video.image=bak
		end
		if not skip or completed>0 then
			video:next_image()
			current_cycle = current_cycle - cycles_per_img	
			completed = 0
			-- next_pos = next_pos0
			if mode=='i' then
				next_pos = next_pos==next_pos0 and next_pos1 or next_pos0
			end
			
			-- infos
			if video.cpt % video.fps == 0 then
				tstamp = tstamp + 1
				local d = os.time() - start; if d==0 then d=1000000000 end
				local t = "> %d%% %d:%02d:%02d (%3.1fx) e=%5.3f a=(x%+d)*%.1g         \r"
				t = t:format(
					percent(tstamp/duration),
					math.floor(tstamp/3600), math.floor(tstamp/60)%60, tstamp%60, 
					math.floor(100*tstamp/d)/100, completed_imgs/video.cpt,
					-audio.cor[2], audio.cor[1])
				io.stdout:write(t)
				io.stdout:flush()
			end
		end
		
		if false then
			-- force retour au début
			local buf = {audio:next_sample()*4,0,0}
			pos = 0
			buf[1] = buf[1] + 2 + math.floor(pos/4096)
			buf[2] = math.floor(pos/16) % 256
			buf[3] = (pos%16)*16 + video.image[pos]
			prev_img[pos] = video.image[pos]; pos = pos + 1
			return string.char(buf[1], buf[2], buf[3])
		end
	end
	
	
	local buf = {audio:next_sample()*4,0,0}
	local k
	local function find_diff()
		local i=pos
		while i<8000 do
			-- io.stderr:write(i..' '..pos..' a\n')
			if prev_img[i] ~= video.image[i] then 
				k = i - pos
				pos = i
				i = 8000
			else
			-- io.stderr:write(i..'-->'..next_pos[i]..'\n')
				i = next_pos[i]
			end
		end
		if not k then
			local i=0
			while i<pos do
			-- io.stderr:write(i..' '..pos..' b\n')
				if prev_img[i] ~= video.image[i] then 
					k = 8000
					pos = i
				else
					-- io.stderr:write(i..'-->'..next_pos[i]..'\n')
					i = next_pos[i]
				end
			end
		end
	end
	if completed==0 then
		find_diff()
		if (not k) and mode=='i' then
			next_pos = next_pos==next_pos0 and next_pos1 or next_pos0
			find_diff()
		end
	end
	if not k then 
		-- aucun changement
		completed = 1
		pos = 7999
		k = 8000
	end
	
	if k<=2 then
		-- deplacement trop faible: mise a jour des 4 octets videos suivants d'un coup
		pos = pos - k
		buf[1] = buf[1] + 1
		buf[2] = video.image[pos+0]*16 + video.image[pos+1]
		buf[3] = video.image[pos+2]*16 + video.image[pos+3]
		prev_img[pos] = video.image[pos]; pos = pos+1
		prev_img[pos] = video.image[pos]; pos = pos+1
		prev_img[pos] = video.image[pos]; pos = pos+1
		prev_img[pos] = video.image[pos]; pos = pos+1
	elseif k<=256 then
		-- deplacement 8 bit
		buf[2] = k%256
		buf[3] = video.image[pos+0]*16 + video.image[pos+1]
		prev_img[pos] = video.image[pos]; pos = pos+1
		prev_img[pos] = video.image[pos]; pos = pos+1
	else
		-- deplacement arbitraire
		buf[1] = buf[1] + 2 + math.floor(pos/4096)
		buf[2] = math.floor(pos/16) % 256
		buf[3] = (pos%16)*16 + video.image[pos]
		prev_img[pos] = video.image[pos]; pos = pos + 1
	end
	return string.char(buf[1], buf[2], buf[3])
end

while audio.running do
	if blk:len() < 3*170 then
		blk = blk..trame_video()
		current_cycle = current_cycle + cycles
	else
		blk = blk..trame_fin()
		current_cycle = current_cycle + cycles*3
		OUT:write(blk)
		blk = ''
	end
end
end
if blk:len()==3*170 then
	OUT:write(blk .. string.char(0,0))
	blk = ''
end
OUT:write(blk)
OUT:write(string.rep(string.char(255),512-blk:len()))
OUT:write(string.rep(string.char(255),512))
OUT:close()
audio:close()
video:close()
io.stdout:write('\n')
io.stdout:flush() 	