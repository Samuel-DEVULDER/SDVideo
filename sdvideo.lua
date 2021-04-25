-- conversion fichier video en fichier sd-drive
--
-- version alpha 0.07
---
-- Samuel DEVULDER Oct 2018

-- code experimental. essaye de determiner
-- les meilleurs parametres (fps, taille ecran
-- pour respecter le fps ci-dessous. 

-- Work in progress!
-- =================
-- le code doit être nettoye et rendu plus
-- amical pour l'utilisateur

local MODE = loadstring('return ' .. (os.getenv('MODE') or '7'))();
local fps = 11 -- 15 -- 10 -- 15 -- 11

package.path = './lib/?.lua;' .. package.path 
function getpicturesize() return 80,50 end
function waitbreak() end
run = function(name) require(name:gsub('%..*','')) end

run("color_reduction.lua")

local function round(x)
	return math.floor(x+.5)
end

if not unpack then unpack = table.unpack end

local BUFFER_SIZE   = 4096*4
local FPS_MAX       = 30
local TIMEOUT       = 2
local FILTER_DEPTH  = 1
local MAX_AUDIO_AMP = 16
local EXPONENTIAL   = true

local tmp = 'tmp'
local img_pattern =  tmp..'/img%05d.bmp'
local cycles = 179 -- cycles par échantillons audio
local hz = round(5000000/cycles)/5
local dither = 1
local ffmpeg = 'tools\\ffmpeg.exe'
local c6809  = 'tools\\c6809.exe'
local mkdir  = 'md'
local del    = 'del >nul /s /q'
local mode = 'iii'

if os.execute('cygpath -W >/dev/null 2>&1')==0 then
	ffmpeg = 'tools/ffmpeg.exe' 
	c6809  = 'tools/c6809.exe'
	mkdir  = 'mkdir -p'
	del    = 'rm -r'
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
local W,H = 320,200
local w = W
local h = round(w*y/x)
if h>H then
   h = H
   w = round(h*x/y)
end
if MODE>=2 and MODE<=11 then
	w = round(w/4)
	W = round(W/4)
	if MODE==8 or MODE==9 then dither=0 end
end
if MODE==6 or MODE==7 then
	h = round(h/2)
	H = round(H/2)
	mode = 'p'
end
if MODE==1 or MODE==8 or MODE==9 then
	h = math.floor(h/3)
	H = math.floor(H/3)
	mode = 'p'
end
if MODE==10 or MODE==11 then
	mode = 'p'
end
-- if mode==nil then
	-- mode = (h*w>320*200 and 'i') or 'p'
-- end

-- initialise la progression dans les octets de l'image
local lines,indices = {},{}
for i=0,199 do
	table.insert(lines, i)
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
elseif mode=='ii' then
	local t = {}
	for i=1,#lines,4 do
		table.insert(t, lines[i])
	end
	for i=3,#lines,4 do
		table.insert(t, lines[i])
	end
	for i=2,#lines,4 do
		table.insert(t, lines[i])
	end
	for i=4,#lines,4 do
		table.insert(t, lines[i])
	end	
	lines = t
elseif mode=='iii' then
	local t = {}
	for i=1,#lines,4 do
		table.insert(t, lines[i])
	end
	for i=3,#lines,4 do
		table.insert(t, lines[i])
	end
	for i=2,#lines,2 do
		table.insert(t, lines[i])
	end
	lines = t
elseif mode=='iiii' then
	local t = {}
	for i=1,#lines,8 do
		table.insert(t, lines[i])
	end
	for i=5,#lines,8 do
		table.insert(t, lines[i])
	end
	for i=3,#lines,8 do
		table.insert(t, lines[i])
	end
	for i=7,#lines,8 do
		table.insert(t, lines[i])
	end
	for i=2,#lines,8 do
		table.insert(t, lines[i])
	end
	for i=6,#lines,8 do
		table.insert(t, lines[i])
	end
	for i=4,#lines,8 do
		table.insert(t, lines[i])
	end
	for i=8,#lines,8 do
		table.insert(t, lines[i])
	end
	lines = t
else 
	error('Unknown mode: ' .. mode)
end
for _,i in ipairs(lines) do
	-- print(i)
	for j=i*40,i*40+39 do
		table.insert(indices, j)
	end
end

local PALETTE = {
        {},{},{},{},{},{},{},{},
		{},{},{},{},{},{},{},{},
		cache = {},
		ef = {0,100,127,142,163,179,191,203,215,223,231,239,243,247,251,255}
}
for i=0,15 do PALETTE.ef[i]=math.floor(.5+255*(i/15)^(1/2.8)) end
function PALETTE:init(pal) 
	self.thomson = pal
	for i,p in ipairs(pal) do
		self[i][1] = self.ef[1+(p%16)]
		self[i][2] = self.ef[1+(math.floor(p/16)%16)]
		self[i][3] = self.ef[1+math.floor(p/256)]
	end
end
if MODE==4 or MODE==5 then
	local
		tab = {0x000,0x00F,0x0F0,0x0FF,
			   0xF00,0xF0F,0xFF0,0xFFF,
			   0x004,0x040,0x400,0x444,
			   0x001,0x010,0x100,0x111}
	if EXPONENTIAL then
		tab = {0x000,0x00F,0x0F0,0x0FF,
			   0xF00,0xF0F,0xFF0,0xFFF,
			   0x003,0x030,0x300,0x333,
			   0x007,0x070,0x700,0x777}
	end
	dither = 0
	PALETTE:init(tab)
elseif MODE==6 or MODE==7 then
	local tab = {}
	
	local r_range = {0,4,8,15}
	local b_range = {0,6,15}
	local g_range = {3,6,9,15}
	-- 1 2 4 7  15
	-- 2 3 5 8  15
	-- 4 6 8 10 15 
	if EXPONENTIAL then
		r_range = {0,1,4,15}
		b_range = {0,1,15}
		g_range = {1,2,6,15}
	end
	
	for _,r in ipairs(r_range) do
		for _,b in ipairs(b_range) do
			table.insert(tab, r+b*256)
		end
	end
	for _,g in ipairs(g_range) do
		table.insert(tab,g*16)
	end
	PALETTE:init(tab)
elseif MODE==8 or MODE==9 then
	local tab = {0}
	local lvls={2,4,7,10,15}
	if EXPONENTIAL then
		lvls = {1,2,4,7,15}
	end
	for _,r in ipairs(lvls) do
		table.insert(tab, r)
	end
	for _,g in ipairs(lvls) do
		table.insert(tab, g*16)
	end
	for _,b in ipairs(lvls) do
		table.insert(tab, b*256)
	end
	PALETTE:init(tab)
else
	-- std palette
	PALETTE:init{0x000,0x00F,0x0F0,0x0FF,
				 0xF00,0xF0F,0xFF0,0xFFF,
				 0x666,0x338,0x383,0x388,
				 0x833,0x838,0x883,0x069}
end
function PALETTE:file_content()
	local buf = ''
	for _,v in ipairs(self.thomson) do
		buf = buf .. string.char(math.floor(v/256), v%256)
	end
	return buf
end
function PALETTE.linear(u)
	return u<10.31475 and u/3294.6 or (((u+14.025)/269.025)^2.4)
	-- return (u/255)^2.2
end
function PALETTE.unlinear(u)
	return u<0 and 0 or u>1 and 255 or u<0.00313 and (u*3294.6) or ((u^(1/2.4))*269.025-14.025)
	-- return u<0 and 0 or u>1 and 255 or (u^(1/2.2))*255
end
-- print(PALETTE.unlinear(.2), PALETTE.unlinear(.4), PALETTE.unlinear(.6), PALETTE.unlinear(.8))
function PALETTE:intens(i)
	local p = self[i]
	return .2126*p[1] + .7152*p[2] + .0722*p[3]
end
function PALETTE.key(r,g,b)
	return string.format("%d,%d,%d",round(r/8),round(g/8),round(b/8))
end
function PALETTE:compute(n, r,g,b)
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
								print("pert", pt[1],pt[2],pt[3],"\n=>",pert[1],pert[2],pert[3])
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
			x,y,z,t = x*n,(x+y)*n,(x+y+z)*n,{}
			while #t<x do push(t,tetra.a.index) end
			while #t<y do push(t,tetra.b.index) end
			while #t<z do push(t,tetra.c.index) end
			while #t<n do push(t,tetra.d.index) end
			table.sort(t, function(a,b) return self:intens(a+1)<self:intens(b+1) end)
			return string.char(unpack(t))
		end
	end
	error("no match for " .. p[1].." "..p[2].." "..p[3])
end
-- function PALETTE:index(r,g,b) 
	-- local k=self.key(self.unlinear(r),self.unlinear(g),self.unlinear(b))
	-- local i=self.cache[k]
	-- if true or not i then
		-- local f=self.linear
		-- if not self.linearized then
			-- self.linearized = true
			-- for _,p in ipairs(self) do
				-- p[1],p[2],p[3] = f(p[1]),f(p[2]),f(p[3])
			-- end
		-- end
		-- local d=1e38
		-- for j,p in ipairs(self) do
			-- local t = (r-p[1])^2 + (g-p[2])^2 + (b-p[3])^2
			-- if t<d then d,i=t,j end
		-- end
		-- self.cache[k] = i
	-- end
	-- return i
-- end
-- function PALETTE:compute(n, r,g,b)
	-- r,g,b = self.linear(r),self.linear(g),self.linear(b)
	-- local k = 0.7
	-- local x,y,z=0,0,0
	-- local t = {}
	-- for i=1,n do
		-- local j = self:index(r+x*k, g+y*k, b+z*k)
		-- local p = self[j]
		-- x,y,z = x+r-p[1],y+g-p[2],z+b-p[3]
		-- t[i] = j-1
	-- end
	-- table.sort(t, function(a,b) return self:intens(a+1)<self:intens(b+1) end)
	-- return t 
	-- return string.char(unpack(t))
-- end

-- os.exit(0)
-- flux audio
local AUDIO = {}
function AUDIO:new(file, hz)
	hz=round(5*hz)
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
	if buf:len()<=5 then
		local t = self.stream:read(BUFFER_SIZE)
		if not t then 
			self.running = false
			t = string.char(0,0,0,0,0)
		end
		buf = buf .. t
	end
	function sample(offset)
		return ((buf:byte(offset)+128)%256)-128
	end
	-- print(buf:byte(1), sample(1))
	local v = (buf:byte(1) + buf:byte(2) + buf:byte(3) + buf:byte(4) +
	           buf:byte(5))*.2 
	self.buf = buf:sub(6)

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
function VIDEO:new(file, w, h, fps)
	if     isdir(tmp) then os.execute(del..' '..tmp) end
	if not isdir(tmp) then os.execute(mkdir..' '..tmp) end
	
	local o = {
		cpt = 1, -- compteur image
		width = w,
		height = h,
		fps = fps or 10,
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
	
	o.zero = (MODE>=3) and ((MODE%2)==1) and 0xC0 or 0x00
	for i=0,7999+3 do o.image[i]=o.zero end
	
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
				t[math.random(m)][math.random(n)] = 1
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
	
	local m=bayer(bayer{{1}})
	-- m = {{1,46,37,32, 3,45,40,18},
        -- {30,22,50,13,27,62,11,55},
        -- {64, 9, 5,41,57,34,25,16},
        -- {44,58,53,15,19,51, 6,38},
        -- {33,28,24,36,43, 2,47,21},
        -- {12, 4,48,63,10,59,31,54},
        -- {42, 8,17,39,29,23,14,61},
        -- {26,60,52,21,56, 7,49,3}}
	if MODE>=2 and MODE<=5 then m = {{1,4},{9,12},{5,8},{13,16},{3,2},{11,10},{7,6},{15,14}} end
	if MODE>=6 and MODE<=7 then m={{1,4},{5,8},{3,2},{7,6}} end
	if MODE>=8 and MODE<=9 then m=bayer{{1}} end
	if MODE==1 then m=((bayer{{1,2,3}})) end
	if MODE>=10 and MODE<=11 then m = {{1,4},{9,12},{5,8},{13,16},{3,2},{11,10},{7,6},{15,14}} end
	for i=1,dither do m = bayer(m) end
	-- if MODE==1 then m=vac(8,3) end
	if dither<0 then m = vac(-dither,-dither*4) end
	
	m.w = #m[1]
	m.h = #m
	local norm=1
	if MODE<=1 or (MODE>=6 and MODE<=9) then norm=1/(1+m.w*m.h) end
	function m:get(i,j)
		return self[1+(j % self.h)][1+(i % self.w)]*norm
	end
	m.wh = m.w*m.h
	
	self.dither = m
end
function VIDEO:transcode(p, o, v)
	local t = self.image[p]
	v = v + (v>=8 and -8 or 8)
	if o==0 then
		v = v*8+t-(math.floor(t/8)%16)*8
	else
		v = (v>=8 and 128 or 0)+(v%8)+(math.floor(t/8)%16)*8
	end
	self.image[p] = v
end
if MODE==0 then
	-- GRAY
	function VIDEO:pset(x,y, r,g,b)
		if not self.dither then VIDEO:init_dither()	end
		if not self._linear then
			self._linear = {}
			for i=0,255 do self._linear[i]=PALETTE.linear(i) end
			self._mask = {}
			for i=0,7 do self._mask[i]=2^(7-i) end
		end
		local f = self._linear
		local v = .2126*f[r] + .7152*f[g] + .0722*f[b]
		if v>self.dither:get(x,y) then 
			local p = math.floor(x/8) + y*40
			self.image[p] = self.image[p] + self._mask[x%8]
		end
	end
elseif MODE==1 then
	-- RGB
	function VIDEO:pset(x,y, r,g,b)
		if not self.dither then VIDEO:init_dither()	end
		if not self._linear then
			self._linear = {}
			for i=0,255 do self._linear[i]=PALETTE.linear(i) end
			self._mask = {}
			for i=0,7 do self._mask[i]=2^(7-i) end
		end
		local f,d = self._linear,self.dither:get(x,y)
		local m,p = self._mask[x%8],math.floor(x/8) + y*120
		if f[r]>d then 
			self.image[p] = self.image[p] + m
		end
		p = p + 40
		if f[g]>d then 
			self.image[p] = self.image[p] + m
		end
		p = p + 40
		if f[b]>d then 
			self.image[p] = self.image[p] + m
		end
	end
elseif MODE==2 or MODE==4 or MODE==10 then
	-- MO (not transcode)
	function VIDEO:pset(x,y, r,g,b)
		if not self.dither then VIDEO:init_dither()	end
		if not self._cache then self._cache = {} end
		
		local k = PALETTE.key(r,g,b)
		local t = self._cache[k]
		if not t then
			t = PALETTE:compute(self.dither.wh,r,g,b)
			self._cache[k] = t
		end
		local o,p,d = (x%2),math.floor(x/2) + y*40,self.dither:get(x,y)
		local v = t:byte(d)
		if o==0 then v=v*16 end
		self.image[p] = self.image[p] + v
	end
elseif MODE==3 or MODE==5 or MODE==11 then
	-- TO (transcode)
	function VIDEO:pset(x,y, r,g,b)
		if not self.dither then VIDEO:init_dither()	end
		if not self._cache then self._cache = {} end
		
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
			o = o==0 and 16 or 1
			local t = b+r*3
			if t>0 then self.image[p] = self.image[p] + t*o end
			if g>0 then 
				p=p+40
				self.image[p] = self.image[p] + (g+11)*o 
			end
		end
	else
		-- TO (transcode)
		function VIDEO:plot(p,o,r,g,b)
			local t = b+r*3
			if t>0 then self:transcode(p,o,t) end
			if g>0 then self:transcode(p+40,o,g+11) end
		end
	end
	function VIDEO:pset(x,y, r,g,b)
		if not self.dither then VIDEO:init_dither()	end
		if not self._linear then
			self._linear = {}
			for i=0,255 do 
				local t = PALETTE.linear(i)
				self._linear[i]={t*3,t*4,t*2}
			end
			if EXPONENTIAL then
				for i=0,255 do 
					local t = 1.0682695162866084908046982244581* math.log(i/255)
					local u = 7.8413059063194981354434536025936 * (i/255)^2.2
					self._linear[i]={
						i<=100 and u or 3+2*t,
						i<=100 and u or 4+3*t,
						i<=100 and u or 2+t
					}
				end
			end
		end
		
		local f,d = self._linear,self.dither:get(x,y)
		r,g,b = f[r][1],f[g][2],f[b][3]
		r = math.floor(r) + (r%1>d and 1 or 0)
		g = math.floor(g) + (g%1>d and 1 or 0)
		b = math.floor(b) + (b%1>d and 1 or 0)
		
		self:plot(math.floor(x/2) + y*80,x%2,r,g,b)
	end
elseif MODE==8 or MODE==9 then
	if MODE%2==0 then
		-- MO (not transcode)
		function VIDEO:plot(p,o,r,g,b)
			o = o==0 and 16 or 1
			if r>0 then self.image[p] = self.image[p] + r*o end 
			p=p+40
			if g>0 then self.image[p] = self.image[p] + (g+5)*o end 
			p=p+40
			if b>0 then self.image[p] = self.image[p] + (b+10)*o end
		end
	else
		-- TO (transcode)
		function VIDEO:plot(p,o,r,g,b)
			if r>0 then self:transcode(p,o,r) end 
			if g>0 then self:transcode(p+40,o,g+5) end 
			if b>0 then self:transcode(p+80,o,b+10) end
		end
	end	
	function VIDEO:pset(x,y, r,g,b)
		if not self.dither then VIDEO:init_dither()	end
		if not self._linear then
			self._linear = {}
			local f = function (i)
				return PALETTE.linear(i)*5
			end
			if EXPONENTIAL then
				f = function(i)
					return 
					i<=100 and ((i/255)^2.2)*7.8413059063194981354434536025936 or 
					5+math.log(i/255)*4.2730780651464339632187928978323
				end
			end
			for i=0,255 do self._linear[i]=f(i) end
		end
		local f,d = self._linear,self.dither:get(x,y)
		r,g,b = f[r],f[g],f[b]
		r = math.floor(r) + (r%1>d and 1 or 0)
		g = math.floor(g) + (g%1>d and 1 or 0)
		b = math.floor(b) + (b%1>d and 1 or 0)
		self:plot(math.floor(x/2) + y*120, x%2, r,g,b)
	end
else
	error('Invalid mode: ' .. MODE)
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
	
	-----------------
	-- Clear image --
	-----------------
	if mode=='a' then
		if not self._prev then self._prev = {} end
		for p=0,#self.image do 
			self._prev[p] = self.image[p]
		end
	end
	for p=0,#self.image do self.image[p] = self.zero end
	
	---------------------
	-- Parse bitmap image
	---------------------
	local ox = math.floor((W - biWidth)/2)
	local oy = math.floor((H - biHeight)/2)
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
	
	if mode=='a' and self._prev then 
		if not diff_tab then
			diff_tab = {}
			local function diff(i,j)
				local c,t = 0,128
				if (i>=t) ~= (j>=t) then c=c+1 end; i,j,t=i%t,j%t,t/2
				if (i>=t) ~= (j>=t) then c=c+1 end; i,j,t=i%t,j%t,t/2
				if (i>=t) ~= (j>=t) then c=c+1 end; i,j,t=i%t,j%t,t/2
				if (i>=t) ~= (j>=t) then c=c+1 end; i,j,t=i%t,j%t,t/2
				if (i>=t) ~= (j>=t) then c=c+1 end; i,j,t=i%t,j%t,t/2
				if (i>=t) ~= (j>=t) then c=c+1 end; i,j,t=i%t,j%t,t/2
				if (i>=t) ~= (j>=t) then c=c+1 end; i,j,t=i%t,j%t,t/2
				if (i>=t) ~= (j>=t) then c=c+1 end; i,j,t=i%t,j%t,t/2
				if (i>=t) ~= (j>=t) then c=c+1 end; i,j,t=i%t,j%t,t/2
				return c
			end
			for i=0,255 do
				for j=0,255 do
					diff_tab[i*256+j] = diff(i,j)
				end
			end
		end
		local diff = {}
		for i=math.floor((200-h)/2),math.floor((200-h)/2)+h-1 do
			local l={i=i, n=0}
			for j=i*40,i*40+39 do 
				l.n =l.n + diff_tab[self.image[j]*256 + self._prev[j]]
			end
			table.insert(diff, l)
		end
		table.sort(diff, function(a,b) return a.n>b.n end)
		local flag = {}
		for i=1,math.floor(#diff/3) do flag[diff[i].i] = true end
		indices = {}
		for i=math.floor((200-h)/2),math.floor((200-h)/2)+h-1 do
			if flag[i] then 
				for j=i*40,i*40+39 do table.insert(indices, j) end
			end
		end
		for i=math.floor((200-h)/2),math.floor((200-h)/2)+h-1 do
			if not flag[i] then 
				for j=i*40,i*40+39 do table.insert(indices, j) end
			end
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

if MODE==10 or MODE==11 then
	
	-- determine la palette	
	local stat = VIDEO:new(file,w,h,round(fps))
	stat.reducer = ColorReducer:new() 
	function stat:pset(x,y, r,g,b)
		local col = Color:new(r,g,b):toLinear()
		-- for i=1,1+1000*math.exp(-(x-40)^2/100) do
			self.reducer:add(col)
		-- end
	end
	stat.super_next_image = stat.next_image
	stat.mill = {'|', '/', '-', '\\'}
	stat.mill[0] = stat.mill[4]
	function stat:next_image()
		self:super_next_image()
		io.stderr:write(string.format('> analyzing colors...%s %d%%\r', self.mill[self.cpt % 4], percent(self.cpt/self.fps/duration)))
		io.stderr:flush()
	end
	while stat.running do
		stat:next_image()
	end
	io.stderr:write(string.rep(' ',79)..'\r')
	io.stderr:flush()
	-- stat.reducer:boostBorderColors()
	local pal = stat.reducer:buildPalette(16, true)
	PALETTE:init(pal)
end

-- auto determination des parametres
local stat = VIDEO:new(file,w,h,round(fps/2))
stat.super_pset = stat.pset
stat.histo = {n=0}; for i=0,255 do stat.histo[i]=0 end
function stat:pset(x,y, r,g,b)
	self.histo[r] = self.histo[r]+1
	self.histo[g] = self.histo[g]+1
	self.histo[b] = self.histo[b]+1
	
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
	local chg = 0
	for _,i in ipairs(indices) do
		if prev[i] ~= curr[i] then chg = chg+1 end
	end
	
	for _,i in ipairs(indices) do
	-- for i=0,7999 do
		while prev[i] ~= curr[i] do
			stat.trames = stat.trames + 1
			local k = i - pos
			if k<0 then k=8000 end
			if k<=1 then
				if curr[pos]==curr[pos+2] and curr[pos+1]==curr[pos+3] then
					prev[pos] = curr[pos]; pos = pos+1
					prev[pos] = curr[pos]; pos = pos+1
					prev[pos] = curr[pos]; pos = pos+1
					prev[pos] = curr[pos]; pos = pos+1
				else
					prev[pos] = curr[pos]; pos = pos+1
					prev[pos] = curr[pos]; pos = pos+1
				end				
			elseif k<=256 then
				pos = i
				prev[pos] = curr[pos]; pos = pos+1
				prev[pos] = curr[pos]; pos = pos+1
			else
				pos = i
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
local avg_trames = (stat.trames/stat.cpt) * 1.03 -- 001 -- 6% safety margin
local ratio = max_trames / avg_trames
-- print(ratio)
if ratio>1 then
	fps = math.min(math.floor(fps*ratio),FPS_MAX)
elseif ratio<1 then
	local zoom = ratio^.5
	w=math.floor(w*zoom)
	h=math.floor(h*zoom)
end
stat.total = 0
for i=1,255 do
	stat.total = stat.total + stat.histo[i]
end
stat.threshold_min = .03*stat.total
stat.min = 0
for i=1,255 do
	stat.min = stat.min + stat.histo[i]
	if stat.min>stat.threshold_min then
		stat.min = i-1
		break
	end
end
stat.max = 0
stat.threshold_max = .03*stat.total
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
if MODE==10 or MODE==11 then video_core = {0,255} end

-- fichier de sortie
function file_content(size, file, extra)
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
		local cmd = c6809..' -bd -am -oOP ' .. source .. ' ' .. raw
		print(cmd) io.flush()
		os.execute(cmd)
	end
	return raw
end

local OUT = assert(io.open(MODE..'_'..file:gsub('.*[/\\]',''):gsub('%.[%a%d]+','')..'.sd', 'wb'))
OUT:write(file_content(1*512, raw('bootblk', 'asm/bootblk.ass')))
local zmode=(MODE<6 and MODE) or (MODE%2==0 and 4 or 5)
OUT:write(file_content(7*512, raw('player3'..zmode, '-dMODE='..zmode..' asm/player3.ass'), PALETTE:file_content()))

-- flux audio/video
local audio  = AUDIO:new(file, hz)
local video  = VIDEO:new(file,w,h,fps)

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
for i=0,7999+3*10 do prev[i] = -1 end

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

-- conversion
io.stdout:write(string.format('> %dx%d %s (%s) %s at %d fps (%d%% zoom)\n',
	w, h, mode, aspect_ratio,
	hms(duration, "%dh %dm %ds"), fps, percent(math.max(w/W,h/H))))
io.stdout:flush()
video:skip_image()
current_cycle = current_cycle + cycles_per_img
video:next_image()
local last_etc=1e38
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
		if d>10 then if etc>last_etc then etc = last_etc else last_etc = etc end end
		local etr = 5 -- etc>=90 and 10 or 5
		etc = round(etc/etr)*etr
		etc = etc>0 and d>10 and "ETC="..hms(etc) or ""
		t = t .. string.rep(' ', math.max(0,79-t:len()-etc:len())) .. etc .. "\r"
		io.stdout:write(t)
		io.stdout:flush()
	end
	
	for _,i in ipairs(indices) do
	-- for i=0,7999 do
		while prev[i] ~= curr[i] do 
			local k = i - pos
			if k<0 then k=8000 end
			local buf = {audio:next_sample()*4,0,0}
			-- if mode=='i' and w==80 then
				-- if k<=2 and ((pos-k)%40)+4>=40
			-- end
			
			if k<=1 then
				-- deplacement trop faible: mise a jour des 2/4 octets
				-- videos suivants d'un coup
				buf[2] = curr[pos]
				buf[3] = curr[pos+1]
				prev[pos] = curr[pos]; pos = pos+1
				prev[pos] = curr[pos]; pos = pos+1					
				if curr[pos]==buf[2] and curr[pos+1]==buf[3] then
					buf[1] = buf[1] + 2
					prev[pos] = curr[pos]; pos = pos+1
					prev[pos] = curr[pos]; pos = pos+1
				end
			elseif k<=256 then
				pos = i			
				-- deplacement 8 bit
				buf[1] = buf[1] + 1
				buf[2] = k%256
				buf[3] = curr[pos]
				prev[pos] = curr[pos]; pos = pos+1
			else
				pos = i
				-- deplacement arbitraire
				buf[1] = buf[1] + 3
				buf[2] = math.floor(pos/256)
				buf[3] = pos%256
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
		blk = blk .. string.char(audio:next_sample()*4+3,0,0)
		pos = 0
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
