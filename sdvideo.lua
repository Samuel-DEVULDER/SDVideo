-- sdvideo.lua : Conversion fichier video en fichier sd-drive
--
-- Version $Version$ $Date$ par Samuel DEVULDER 
--
-- Ici la résolution est plus fine que dans conv_sd.lua (de 320x200
-- N/B à 80x66 avec 216 couleurs.) Les fichiers vidéo sont en partie
-- différents entre les gammes d'ordinateurs thomson. Reférez vous au
-- README.html pour avoir tous les détails.
--
-- Le son joue à ~5.9 kHz.
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
-- MODE=0..8 (défaut: 1)
--    Mode de sortie. Regardez le README.html pour les détails.
--
-- Work in progress!
-- =================
-- De nouveaux modes peuvent apparaitre et d'anciens disparaitre.
-- Le code doit être nettoye et rendu plus amical pour l'utilisateur.
--
-- Travail débuté en Oct 2018.


-- ===========================================================================

local MODE_TXT = {}
for i,v in pairs{
				-- B/W
				 "EDGE", 
				 "OTSU", 
				 "BAYR", "VACD", "HLFT", "DITH", 
				 -- GRAY
				 "BM59", 
				 -- COLOR
			     "RGB2", "C345", "RGB6",
				 "RGB4", "RGB5", "CR16",
				 nil} do
	local n = i-1
	_G['MODE_' .. v], MODE_TXT[n] = n, v
end

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
      local f = io.open(file,'r')
	  if f then f:close() return true end
   end
   return ok, err
end
local function isdir(file)
	return exists(file..'/')
end
local function env(var, default)
	local val  = os.getenv(var)
	local code = 'return ' .. (val or 'false') .. 
       ' or ' .. ' MODE_' .. (val or '')  .. 
       ' or ' .. (val or default)
	return loadstring(code)();
end
local function locate(file,...)
	-- look locally
	local pwd = arg[0]:match("(.*[/\\])") or ''
	for _,ext in ipairs{'','.exe'} do
		for _,sep in ipairs{'\\','/'} do
			for _,root in ipairs{pwd, pwd .. '..' .. sep} do
				for _,dir in ipairs{'', ...} do
					dir = dir=='' and dir or dir..sep
					local tmp = (root .. dir .. file .. ext):gsub('[\\/]',sep)
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
local MODE          = env('MODE',MODE_DITH)
local FPS           = env('FPS',16)
local COLOR         = env('COLOR',-1)
local SCROLL        = env('SCROLL', 'true')
local FFMPEG        = locate('ffmpeg', 'tools')
local YT_DL         = locate('yt-dlp', 'tools')
local BIN           = locate('bin/')

local POPEN_READBIN = FFMPEG:match(".*%.exe") and "rb" or "r"

-- constants
local CYCLES        = 168 -- CYCLES per audio sample
local FPS_MAX       = 30
local ZIGZAG        = false
local BUFFER_SIZE   = 4096
local CONFIG        = nil
-- local GRAY_R		= 0.30
-- local GRAY_G		= 0.59
-- local GRAY_B		= 0.11
local GRAY_R		= 0.2126
local GRAY_G		= 0.7152
local GRAY_B		= 0.0722
local MODE_BM59_PROG_COL 

if type(MODE)=='string' then
	for k,v in pairs(MODE_TXT) do
		if v==MODE then MODE=k end
	end
end

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
local function _ms(secs, fmt)
    -- return a formated version of secs seconds (fmt is optional)
    secs = round(secs)
    return string.format(fmt or "%d:%02d",
            math.floor(secs/60), math.floor(secs)%60)
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
local function double(t)
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
            local z = 2*t[i][j]
            d[m*0+i][n*0+j] = z-1
            d[m*1+i][n*1+j] = z-1
            d[m*1+i][n*0+j] = z
            d[m*0+i][n*1+j] = z
        end
    end
    return d
end
local function halve(t)
    local m=#t
    local n=#t[1]
	local d={}
    for i=1,m do
		d[i] = {}
        for j=1,n do
			d[i][j] = math.ceil(t[i][j]/2)
        end
    end
    return d
end
local function vac(n,m)
    math.randomseed(os.time())
    local function mat(w,h)
        local t={}
        for i=1,h do
            t[i] = {}
            for j=1,w do t[i][j] = 0 end
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
        local t
		repeat
			t = mat(n,m)
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
			for i=1,m do
				local c=0
				for j=1,n do if t[i][j]>0 then c=c+1 end end
				if c>1 then t = nil; break; end
			end
			if t then for j=1,n do
				local c=0
				for i=1,m do if t[i][j]>0 then c=c+1 end end
				if c>1 then t = nil; break; end
			end end
		until t
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
local function transp(t)
    local m,n=#t,#t[1]
    for i=1,m do
        for j=1,i-1 do
            t[i][j],t[j][i] = t[j][i],t[i][j]
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
	asm_mode     = 0,
	ffmpeg_extra = '',
    px_size      = {1,1},
    dither       = {{1}},
    palette      = compo{0x000,0x00F,0x0F0,0x0FF,
                         0xF00,0xF0F,0xFF0,0xFFF,
                         0x666,0x338,0x383,0x388,
                         0x833,0x838,0x883,0x069}
}

local PALETTE = {ef={}}
-- thomson levels in PC world
for i=0,15 do PALETTE.ef[i+1]=round(255*(i/15)^(1/2.8)) end
function PALETTE.linear(u)
	-- do return (u/255)^2.2 end
	if not PALETTE.__linear then 
		PALETTE.__linear = {}
		for u=0,255 do
			PALETTE.__linear[u] = 
				-- (u/255)^2.2
				u<10.31475 and u/3294.6 or (((u+14.025)/269.025)^2.4)
				-- (u/255)^1.8
				-- (u/255)^1.5
				-- (u/255)^(2.4/2.2)
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
	local size = 21 -- 6
	if false then
		local min = 10
		for i=1,32 do
			local x = i*1000000/CYCLES
			x = math.abs(x-round(x))
			if x<min then size,min = i,x end
			print(i,x,size)
		end
		print('size='..size)
	end
	
	local hz = round(size*1000000/CYCLES)
	local norm = '-filter:a dynaudnorm=r=0.6:s=8:m=30 '
	
	local o = {
		hz = hz,
		stream = assert(io.popen(FFMPEG..' -i "'..file ..'" -v 0 ' ..
		norm ..
		'-ac 1 -ar '..hz..' -f s8 -c:a pcm_s8 pipe:', POPEN_READBIN)),
		size = size,
		mute = '',
		buf = '', -- buffer
		vol = 1.4, -- 1.6,
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
function AUDIO:compressor(v)
	local t,m,s = 28,32,v>=0 and 1 or -1
	self.comp_ratio = self.comp_ratio or (m-t)/(m*self.vol-t)
	v = math.abs(v * self.vol)
	if v>t then v = t + (v-t)*self.comp_ratio end
	return v*s
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
	self.buf,v = buf:sub(siz+1),self:compressor(v/(siz*4)) + 31.5 + math.random()
	if v<0 then v=0 elseif v>63 then v=63 end
	if false then 
		v = (self.last==0 and v>40 and 63 or 0) or (self.last==63 and v<23 and 0 or 63)
		self.last = self.last or 0
		self.last = v
	end
	return math.floor(v)
end

-- ===========================================================================
-- VIDEO filter aimed at mixing dropped frammes
local FILTER = {}
function FILTER:new(video)
    local o = {t={},i=0,a=0,cur={},video=video}
    setmetatable(o, self)
    self.__index = self
	for i=0,320*200*3-1 do o.cur[i] = 0 end
	o.t[0] = o.cur
    return o
end
function FILTER:push(bytecode)
	self.i = self.i + 1
	local t = self.t[self.i]
	if t==nil then t = {}; self.t[self.i] = t end
	if self.a>=.001 then
		local u = self.t[self.i-1]
		for i=#u+1,bytecode:len() do u[i] = 0 end
		local a,b,f = self.a,1-self.a,math.floor
		for i=1,bytecode:len() do t[i] = f(.5 + u[i]*a + b*bytecode:byte(i)) end
	else
		for i=1,bytecode:len() do t[i] = bytecode:byte(i) end
	end
    return self
end
function FILTER:flush()
	self.rnd = nil -- math.random()
	self.t[0] = self.t[self.i]
	self.i = 0
end
function FILTER:byte(offset)
    local m,t = self.i, self.t
	if true then return t[m][offset] end -- aucun traitement
	if m==1 then
	    return t[1][offset]
	elseif m==2 then
	    return round((t[1][offset]+t[2][offset])/2)
	elseif m==3 then
		local a,b,c = t[1][offset],t[2][offset],t[3][offset]
		-- abc acb bac bca cab cba
		local bc = math.min(b,c)
		return a<=bc and bc
		    or b==bc and (a<=c and a or c)
			or           (a<=b and a or b)
	elseif true then -- return median
		local q = self._q if q==nil then q={} self._q = q end
		for i=1,m do q[i] = t[i][offset] end
		table.sort(q)
		local t = math.ceil(m/2)
		if 2*t==m then
			-- if not q[t-1] or not q[t] then print(m..'  '..t..'   ') end
			return math.floor(.5*(1 + q[t] + q[t+1]))
		else
			return q[t]
		end
	elseif true then
		if m==2 then return round(math.sqrt(t[1][offset]*t[2][offset])) end
		local v=1
		for i=1,m do v=v*t[i][offset] end
		return round(v^(1/m))
		-- return t[round(0.25*(1+3*m))][offset]
	elseif false then	
		local v,w,n = 0,0,2
        for i=1,m do v,w = v + t[i][offset]^n,w+1 end
        return round((v/w)^(1/n))
	elseif false then
		local y = math.floor((offset-1)*CONFIG.px_size[1]/320)
		local o = 1+math.abs((y % (2*m-1)) - (m-1))
		return t[o][offset]
	elseif false then
		local v,w,d=0,0,0
		for i=1,m do w=math.exp(-0.125*(i-m/2)^2); v,d=v+w*t[i][offset],d+w end
		return round(v/d)
	elseif false then
		if not self.offset_cache then self.offset_cache = {} end
		if not self.offset_cache[m] then
			self.offset_cache[m] = {}
			local f = math.floor
			for i=1,#t[1] do
				self.offset_cache[m][i] = m-f(m*320*f((i-1)/320)/#t[1])
			end
		end
		return t[self.offset_cache[m][offset]][offset]
	elseif false then
		return round(0.5*(t[1][offset]+t[m][offset]))
	elseif false then	
		local a=.5; local b,v=1-a,t[1][offset]
        for i=2,m do v=a*v+b*t[i][offset] end
		return round(v)
	elseif false then	
		local v,m1,m2 = 0,0,0
        for i=1,m do m2=1.6^i; m1,m2=m1+t[i][offset]*m2,m1+m2 end
		m1,m2 = m1/m2,0
		for i=1,m do m2 = m2 + (t[i][offset]-m1)^2 end
		v = t[m][offset]
		local e1,e2 = (v-m1)^2,m2/m
		return e1<e2 and round(m1) or v
	elseif false then	
		local v,m1,m2 = 0,0,0
        for i=1,m-1 do v=t[i][offset]; m1,m2=m1+v,m2+v*v end
		m1,m2,v = m1/(m-1),m2/(m-1),t[m][offset]
		local e1,e2 = (v-m1)^2,m2-m1^2
		if e1<2*e2 then
			-- if e1>0 then print(e2/e1, m1,m2,v, e1,e2) end
			m1=0.666; v,m2=t[1][offset],1-m1
			for i=2,m do v=m1*v+m2*t[i][offset] end
			return round(v)
		else	
			return v
		end
	elseif false then	
		local a,d,v,w=0,0,0,0
        for i=1,m-1 do a = a + t[i][offset] end; a = a/(m-1)
		for i=1,m do local t=t[i][offset]; w=0.01 + (t-a)^2; v,d=v+t*w,d+w end
		return round(v/d)
	elseif false then
		if self.k==nil then self.k = math.floor(CONFIG.px_size[2]*320/CONFIG.px_size[1]) end
		local k = math.floor(offset/self.k) % (m-1)
		return t[1+k][offset]
	elseif false then	
		local v,m1,m2 = 0,0,0
        for i=1,m do v=t[i][offset]; m1,m2=m1+v,m2+v*v end
		m1,m2,v = m1/m,m2/m,t[m][offset]
		local e1,e2 = (v-m1)^2,m2-m1^2
		-- if e1>=e2 then print("*",(e1/e2),m) else print "-" end
        return e1<e2 and round(m1) or v
	elseif true then	
		local v,m1,m2 = 0,0,0
        for i=1,m-1 do v=t[i][offset]; m1,m2=m1+v,m2+v*v end
		m1,m2,v = m1/(m-1),m2/(m-1),t[m][offset]
		local e1,e2 = (v-m1)^2,m2-m1^2
		-- if e1>e2 then print "*" else print "-" end
        return e1<e2 and round(m1) or v
	elseif false then	
		local v = 0
        for i=1,m do v = math.max(v,t[i][offset]) end
        return v
	elseif true then	
		local v,d,f1,f2 = 0,0,0,1
        for i=1,m do v,d,f1,f2 = v + t[i][offset]*f2,d+f2,f2,f1+f2 end
        return round(v/d)		
	elseif true then	
		local v,d,w = 0,0
        for i=1,m do w=2^i; v,d = v + t[i][offset]*w,d+w end
        return round(v/d)
	elseif false then	
		local v,d,w = 0,0
        for i=1,m do w=i^1.5; v,d = v + t[i][offset]*w,d+w end
        return round(v/d)
	elseif false then	
		local v,d,w = 0,0
        for i=1,m do w=i*i; v,d = v + t[i][offset]*w,d+w end
        return round(v/d)
	elseif true then	
		local v,d,w = 0,0
        for i=1,m do w=i; v,d = v + t[i][offset]*w,d+w end
        return round(v/d)
    elseif true then
        -- do return round((self.t[1][offset]+2*self.t[2][offset])*.3333333) end

        -- new strategy to improve compression: if change is small, keep previous value
        local a,b = t[1][offset],t[m][offset]
        local la,lb =
            -- (a/255)^2.2,(b/255)^2.2
            PALETTE.linear(a),PALETTE.linear(b)
		-- if math.abs(la-lb)>0 and la+lb>0 then print (math.abs(la-lb)/math.max(la,lb)) end
        if la~=lb 
		and	math.abs(la-lb)<FILTER_THRES -- *math.max(la,lb)
		and (self.rnd or math.random())>.25
		then
            b,t[m][offset]=a,a
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
function VIDEO:new(file, fps, w, h, screen_width, screen_height, pset, duration)
    local o = {
        file = file,
        cpt = 1, -- compteur image
		duration = duration,
        width = w,
        height = h,
        screen_width = screen_width or w,
        screen_height = screen_height or h,
        fps = fps or 10,
        image = {},
        dither = nil,
        expected_size = 3*h*w, -- --54 + h*(math.floor((w*3+3)/4)*4),
        running=true,
        img_pattern=img_pattern,
        input = assert(io.popen(FFMPEG..
			' -i "'..file..'" -v 0 -r '..fps..
			' -s '..w..'x'..h..
			-- ' -vf "hqdn3d=luma_spatial=12: chroma_spatial=1: luma_tmp=1: chroma_tmp=1"' ..
			' -vf "tmedian"'..
			-- ' -vf "eq=contrast=2"'..
			-- ' -vf "hqdn3d"' ..
			-- ' -vf "atadenoise"' ..
			-- ' -vf "bm3d"'..
			-- ' -vf "chromanr"'..
			-- ' -vf "dctdnoiz"'..
			-- ' -vf "nlmeans"'..
			-- ' -vf "owdenoise"'..
			-- ' -vf "removegrain"'..
			' -vf "tmix"'..
			-- ' -vf "vaguedenoiser"'..
			CONFIG.ffmpeg_extra ..
			' -an -f rawvideo -pix_fmt rgb24 pipe:', 
			POPEN_READBIN)),
		pset = pset
    }
    setmetatable(o, self)
    self.__index = self

	local cpt,full,i2l = 0,0,{}
	for i=0,199 do
		for j=0,39 do i2l[i*40+j] = math.floor(i/math.min(#CONFIG.dither,CONFIG.px_size[2])) end
	end
	o.progressiv = function(prev,curr)
		if not o._progressive then
			o._progressive = {}
			for i=0,7999 do table.insert(o._progressive,i) end
		end
		return ipairs(o._progressive)
	end
	o.interlaced = function(prev,curr)
		cpt = cpt+1
		local m, t = 2, {}
		local n = cpt % m
		for i=0,7999 do 
			local line = i2l[i]
			if  line<=6  -- do not interlace title zone
			or (line%m)==n then table.insert(t,i) else curr[i] = prev[i] end 
		end
		return ipairs(t)
	end

    for i=0,7999+83 do o.image[i]=0 end

    o.filter = FILTER:new(o)
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

function VIDEO:overwrite(overwrite)
	self._overwrite = overwrite
end

function VIDEO:pset(x,y, r,g,b)
	if not self.dither then	self:init_dither(); self._cache = {} end

	self.pset_ovr = function(self, x,y, r,g,b)
		local k = PALETTE.key(r,g,b)
		local t = self._cache[k]
		if not t then
			t = PALETTE:compute(self.dither.wh,r,g,b)
			self._cache[k] = t
		end
		local p,v = math.floor(x/2) + y*40,t:byte(self.dither:get(x,y))
		t = self.image[p]
		self.image[p] = ((x%2)==0 and t%16+v*16 or t-(t%16)+v)
	end
	
	self.pset_fst = function(self, x,y, r,g,b)
		local k = PALETTE.key(r,g,b)
		local t = self._cache[k]
		if not t then
			t = PALETTE:compute(self.dither.wh,r,g,b)
			self._cache[k] = t
		end
		local p,v = math.floor(x/2) + y*40,t:byte(self.dither:get(x,y))
		self.image[p] = self.image[p]+((x%2)==0 and v*16 or v) 
	end
	
	self.overwrite = function(self, ovr)
		self._overwrite, self.pset = ovr, ovr and self.pset_ovr or self.pset_fast
	end
	
	self.pset = self.pset_fst
	self:pset(x,y, r,g,b)
end
VIDEO.font = {
    [' ']={
        "....",
        "....",
        "....",
        "....",
        "....",
        "...."
    },['!']={
        ".X..",
        ".X..",
        ".X..",
        "....",
        ".X..",
        "...."
    },['"']={
        "X.X.",
        "X.X.",
        "....",
        "....",
        "....",
        "...."
    },['#']={
        "X.X.",
        "XXX.",
        "X.X.",
        "XXX.",
        "X.X.",
        "...."
    },['$']={
        ".XX.",
        "XXX.",
        ".X..",
        ".XX.",
        "XX..",
        "...."
    },['%']={
        "X...",
        "..X.",
        ".X..",
        "X...",
        "..X.",
        "...."
    },['&']={
        ".X..",
        "XX..",
        ".XX.",
        "X.X.",
        ".XX.",
        "...."
    },["'"]={
        ".X..",
        ".X..",
        "....",
        "....",
        "....",
        "...."
    },["("]={
        "..X.",
        ".X..",
        ".X..",
        ".X..",
        "..X.",
        "...."
    },[")"]={
        ".X..",
        "..X.",
        "..X.",
        "..X.",
        ".X..",
        "...."
    },['*']={
        "X.X.",
        ".X..",
        "XXX.",
        ".X..",
        "X.X.",
        "...."
    },['+']={
        "....",
        ".X..",
        "XXX.",
        ".X..",
        "....",
        "...."
    },[',']={
        "....",
        "....",
        "....",
        ".X..",
        "X...",
        "...."
    },['-']={
        "....",
        "....",
        "XXX.",
        "....",
        "....",
        "...."
    },['.']={
        "....",
        "....",
        "....",
        "....",
        ".X..",
        "...."
    },['/']={
        "..X.",
        "..X.",
        ".X..",
        "X...",
        "X...",
        "...."
    },['0']={
        "XXX.",
        "X.X.",
        "X.X.",
        "X.X.",
        "XXX.",
        "...."
    },['1']={
        ".X..",
        "XX..",
        ".X..",
        ".X..",
        ".X..",
        "...."
    },['2']={
        "XXX.",
        "..X.",
        "XXX.",
        "X...",
        "XXX.",
        "...."
    },['3']={
        "XXX.",
        "..X.",
        "XXX.",
        "..X.",
        "XXX.",
        "...."
    },['4']={
        "X.X.",
        "X.X.",
        "XXX.",
        "..X.",
        "..X.",
        "...."
    },['5']={
        "XXX.",
        "X...",
        "XXX.",
        "..X.",
        "XXX.",
        "...."
    },['6']={
        "XXX.",
        "X...",
        "XXX.",
        "X.X.",
        "XXX.",
        "...."
    },['7']={
        "XXX.",
        "..X.",
        "..X.",
        "..X.",
        "..X.",
        "...."
    },['8']={
        "XXX.",
        "X.X.",
        "XXX.",
        "X.X.",
        "XXX.",
        "...."
    },['9']={
        "XXX.",
        "X.X.",
        "XXX.",
        "..X.",
        "XXX.",
        "...."
    },[':']={
        "....",
        ".X..",
        "....",
        ".X..",
        "....",
        "...."
    },[';']={
        "....",
        ".X..",
        "....",
        ".X..",
        ".X..",
        "X..."
    },['<']={
        "..X.",
        ".X..",
        "X...",
        ".X..",
        "..X.",
        "...."
    },['=']={
        "....",
        "XXX.",
        "....",
        "XXX.",
        "....",
        "...."
    },['>']={
        "X...",
        ".X..",
        "..X.",
        ".X..",
        "X...",
        "...."
    },['?']={
        "XX..",
        "..X.",
        ".X..",
        "....",
        ".X..",
        "...."
    },['@']={
        ".XX.",
        "X..X",
        "X.XX",
        "X...",
        ".XX.",
        "...."
    },['A']={
        ".X..",
        "X.X.",
        "XXX.",
        "X.X.",
        "X.X.",
        "...."
    },['B']={
        "XX..",
        "X.X.",
        "XX..",
        "X.X.",
        "XX..",
        "...."
    },['C']={
        ".XX.",
        "X...",
        "X...",
        "X...",
        ".XX.",
        "...."
    },['D']={
        "XX..",
        "X.X.",
        "X.X.",
        "X.X.",
        "XX..",
        "...."
    },['E']={
        "XXX.",
        "X...",
        "XX..",
        "X...",
        "XXX.",
        "...."
    },['F']={
        "XXX.",
        "X...",
        "XX..",
        "X...",
        "X...",
        "...."
    },['G']={
        ".XX.",
        "X...",
        "X.X.",
        "X.X.",
        ".XX.",
        "...."
    },['H']={
        "X.X.",
        "X.X.",
        "XXX.",
        "X.X.",
        "X.X.",
        "...."
    },['I']={
        "XXX.",
        ".X..",
        ".X..",
        ".X..",
        "XXX.",
        "...."
    },['J']={
        "..X.",
        "..X.",
        "..X.",
        "X.X.",
        ".X..",
        "...."
    },['K']={
        "X.X.",
        "X.X.",
        "XX..",
        "X.X.",
        "X.X.",
        "...."
    },['L']={
        "X...",
        "X...",
        "X...",
        "X...",
        "XXX.",
        "...."
    },['M']={
        "X.X.",
        "XXX.",
        "XXX.",
        "X.X.",
        "X.X.",
        "...."
    },['N']={
        "XX..",
        "X.X.",
        "X.X.",
        "X.X.",
        "X.X.",
        "...."
    },['O']={
        ".X..",
        "X.X.",
        "X.X.",
        "X.X.",
        ".X..",
        "...."
    },['P']={
        "XX..",
        "X.X.",
        "XX..",
        "X...",
        "X...",
        "...."
    },['Q']={
        ".X..",
        "X.X.",
        "X.X.",
        "XXX.",
        ".XX.",
        "...."
    },['R']={
        "XX..",
        "X.X.",
        "XX..",
        "X.X.",
        "X.X.",
        "...."
    },['S']={
        ".XX.",
        "X...",
        ".X..",
        "..X.",
        "XX..",
        "...."
    },['T']={
        "XXX.",
        ".X..",
        ".X..",
        ".X..",
        ".X..",
        "...."
    },['U']={
        "X.X.",
        "X.X.",
        "X.X.",
        "X.X",
        "XXX.",
        "...."
    },['V']={
        "X.X.",
        "X.X.",
        "X.X.",
        ".X..",
        ".X..",
        "...."
    },['W']={
        "X.X.",
        "X.X.",
        "XXX.",
        "XXX.",
        "X.X.",
        "...."
    },['X']={
        "X.X.",
        "X.X.",
        ".X..",
        "X.X.",
        "X.X.",
        "...."
    },['Y']={
        "X.X.",
        "X.X.",
        "XXX.",
        ".X..",
        ".X..",
        "...."
    },['Z']={
        "XXX.",
        "..X.",
        ".X..",
        "X...",
        "XXX.",
        "...."
    },['[']={
        "XXX.",
        "X...",
        "X...",
        "X...",
        "XXX.",
        "...."
    },['\\']={
        "X...",
        "X...",
        ".X..",
        "..X.",
        "..X.",
        "...."
    },[']']={
        "XXX.",
        "..X.",
        "..X.",
        "..X.",
        "XXX.",
        "...."
    },['^']={
        ".X..",
        "X.X.",
        "....",
        "....",
        "....",
        "...."
    },['_']={
        "....",
        "....",
        "....",
        "....",
        "....",
        "XXX."
    },['`']={
        ".X..",
        "..X.",
        "....",
        "....",
        "....",
        "...."
    },['a']={
        "....",
        ".XX.",
        "X.X.",
        "X.X.",
        ".XX.",
        "...."
    },['b']={
        "X...",
        "XX..",
        "X.X.",
        "X.X.",
        "XX..",
        "...."
    },['c']={
        "....",
        ".XX.",
        "X...",
        "X...",
        ".XX.",
        "...."
    },['d']={
        "..X.",
        ".XX.",
        "X.X.",
        "X.X.",
        ".XX.",
        "...."
    },['e']={
        "....",
        ".X..",
        "X.X.",
        "XX..",
        ".XX.",
        "...."
    },['f']={
        ".XX.",
        "X...",
        "XX..",
        "X...",
        "X...",
        "...."
    },['g']={
        "....",
        ".XX.",
        "X.X.",
        ".XX.",
        "..X.",
        "XX.."
    },['h']={
        "X...",
        "XX..",
        "X.X.",
        "X.X.",
        "X.X.",
        "...."
    },['i']={
        ".X..",
        "....",
        ".X..",
        ".X..",
        "..X.",
        "...."
    },['j']={
        ".X..",
        "....",
        ".X..",
        ".X..",
        ".X..",
        "X..."
    },['k']={
        "X...",
        "X.X.",
        "XX..",
        "X.X.",
        "X.X.",
        "...."
    },['l']={
        ".X..",
        ".X..",
        ".X..",
        ".X..",
        "..X.",
        "...."
    },['m']={
        "....",
        "XX..",
        "XXX.",
        "XXX.",
        "X.X.",
        "...."
    },['n']={
        "....",
        "XX..",
        "X.X.",
        "X.X.",
        "X.X.",
        "...."
    },['o']={
        "....",
        ".X..",
        "X.X.",
        "X.X.",
        ".X..",
        "...."
    },['p']={
        "....",
        "XX..",
        "X.X.",
        "X.X.",
        "XX..",
        "X..."
    },['q']={
        "....",
        ".XX.",
        "X.X.",
        "X.X.",
        ".XX.",
        "..X."
    },['r']={
        "....",
        "XX..",
        "X.X.",
        "X...",
        "X...",
        "...."
    },['s']={
        "....",
        ".XX.",
        "X...",
        "..X.",
        "XX..",
        "...."
    },['t']={
        ".X..",
        "XXX.",
        ".X..",
        ".X..",
        "..X.",
        "...."
    },['u']={
        "....",
        "X.X.",
        "X.X.",
        "X.X",
        ".XX.",
        "...."
    },['v']={
        "....",
        "X.X.",
        "X.X.",
        "XXX.",
        ".X..",
        "...."
    },['w']={
        "....",
        "X.X.",
        "X.X.",
        "XXX.",
        ".XX.",
        "...."
    },['x']={
        "....",
        "X.X.",
        ".X..",
        ".X..",
        "X.X.",
        "...."
    },['y']={
        "....",
        "X.X.",
        "X.X.",
        ".XX.",
        "..X.",
        "XX.."
    },['z']={
        "....",
        "XXX.",
        "..X.",
        "X...",
        "XXX.",
        "...."
    },['{']={
        ".XX.",
        ".X..",
        "XX..",
        ".X..",
        ".XX.",
        "...."
    },['|']={
        ".X..",
        ".X..",
        ".X..",
        ".X..",
        ".X..",
        "...."
    },['}']={
        "XX..",
        ".X..",
        ".XX.",
        ".X..",
        "XX..",
        "...."
    },['~']={
        "....",
        ".X.X",
        "X.X.",
        "....",
        "....",
        "...."
    }
}
function VIDEO:putc(x,y,chr)
    local f = VIDEO.font[chr]
    if f==nil then f = VIDEO.font['?'] end
    if f==nil then f = VIDEO.font[' '] end
    if f==nil then return x,y end
	x,y = math.floor(x),math.floor(y)
	local w = f[1]:len()
	if x<=-w or x>=self.screen_width 
	or y<=-6 or y>=self.screen_height then return x+w,y end

	local ZZ=ZIGZAG; ZIGZAG=false	
    for j,l in ipairs(f) do
        for i=1,l:len() do
            local c = l:sub(i,i)=='.' and 0 or 255
			local a,b = x+i-1,y+j-1
			if a>=0 and a<self.screen_width and
               b>=0 and b<self.screen_height then
				self:pset(x+i-1,y+j-1,c,c,c)
			end
        end
    end
    ZIGZAG=ZZ
    return x+w,y
end
function VIDEO:puts(x,y,str)
    for i=1,str:len() do
        x,y = self:putc(x,y,str:sub(i,i))
    end
    return x,y
end
function VIDEO:putf(x,y,...)
    return self:puts(x,y,string.format(...))
end

function VIDEO:otsu(gray)
	-- https://en.wikipedia.org/wiki/Otsu's_method
	local histo = self._histo
	if histo==nil then histo = {}; self._histo = histo end
	for i=0,255   do histo[i] = 0 end
	for i=0,63999 do local g = gray[i]; histo[g] = histo[g]+1 end
	local wB,sumB,sum1,maximum,level = 0,0,0,-1,256
	for i=0,255 do sum1 = sum1 + i*histo[i] end
	local function sqr(x) return x*x end
	for i=0,255 do
		local wF = 64000-wB
		if wB*wF>0 then
			local mF = (sum1-sumB)/wF
			local v = wB * wF * sqr((sumB / wB) - mF)
			if v > maximum then	maximum,level = v,i end
		end
		wF = histo[i]
		wB,sumB = wB + wF,sumB + i*wF
	end	
	local m,j,img = {128,64,32,16,8,4,2,1},0,self.image
	for i=0,7999 do for _,m in ipairs(m) do
		if gray[j]>level then img[i] = img[i] + m end
		gray[j],j = 0,j+1
	end end
	-- for i=0,63999 do 
		-- if gray[i]>level then
			-- local a,b = unpack(self._mask[i])
			-- self.image[a] = self.image[a] + b
		-- end
		-- gray[i] = 0
	-- end			
end

function VIDEO:setup_gray()
	self._mask = {}
	for i=0,320*200-1 do self._mask[i]={math.floor(i/8),2^(7-(i%8))} end

	self._r,self._g,self._b = {},{},{}
	for i=0,255 do
		local lin = PALETTE.linear(i)
		self._r[i] = lin*GRAY_R*255
		self._g[i] = lin*GRAY_G*255
		self._b[i] = lin*GRAY_B*255
	end
	
	self._gray = {} for i=0,63999 do self._gray[i] = 0 end
	
	self.pset_ovr = function(self, x,y, r,g,b)
		local i,f,_mask = self.image,unpack(self._mask[x+320*y])
		if (i[f]/_mask) % 2 >= 1 then
			i[f] = i[f] - _mask
		end
		if self._r[r]+self._g[g]+self._b[b]>50 then
			i[f] = i[f] + _mask
		end
	end
	self.pset_fst = function(self, x,y, r,g,b)
		self._gray[x+y*320] = round(self._r[r]+self._g[g]+self._b[b])
	end
	self.pset = self.pset_fst
	self.overwrite = function(self, ovr)
		self._overwrite, self.pset = ovr, ovr and self.pset_ovr or self.pset_fst
	end
end

if MODE==MODE_OTSU then -- Otsu
    CONFIG.asm_mode  = 0
    function VIDEO:pset(x,y, r,g,b)
		self:setup_gray()
		self._flush = self.filter.flush
		self.filter.flush = function(filter) 
			self._flush(filter)
			self:otsu(self._gray)
		end
		self:pset(x,y,r,g,b)
    end
elseif MODE==MODE_DITH 
    or MODE==MODE_BAYR 
	or MODE==MODE_HLFT 
	or MODE==MODE_VACD 
	then -- N&B
	CONFIG.asm_mode  = 0
	if MODE==MODE_HLFT then
		CONFIG.dither = compo(norm,double,transp){ -- 32 levels
			{ 7,13,11, 4},
			{12,16,14, 8},
			{10,15, 6, 2},
			{ 5, 9, 3, 1} 
		}
	elseif MODE==MODE_VACD then
		-- CONFIG.dither = compo(norm,double,vac)(8,8)	-- 128 levels
		CONFIG.dither = compo(norm,halve,vac)(8,8)	-- 32 levels
	elseif MODE==MODE_BAYR then 
		CONFIG.dither = compo(norm, bayer, 4){{1}} -- 64 levels
	else -- default to bayer
		CONFIG.dither = compo(norm, double, bayer, 2){{1}} -- 32 levels
	end

    -- CONFIG.dither    = 
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
	-- compo(norm,vac)(13,13)
	-- compo(norm,vac)(7,7)
	-- compo(norm,vac)(16,8)
	-- compo(norm,vac)(8,7)
	-- compo(norm,bayer,3){{1}}
	-- CONFIG.dither = compo(norm,bayer,3){{1}}
	-- CONFIG.dither = compo(norm,bayer){
		-- { 7,13,11, 4},
		-- {12,16,14, 8},
		-- {10,15, 6, 2},
		-- { 5, 9, 3, 1} 
		
		-- { 5,10,12, 7},
		-- { 9,15,16,13},
		-- { 3, 6,14,11},
		-- { 1, 2, 8, 4}
	-- }
	-- CONFIG.dither = compo(norm,bayer,2){{1,2},{3,4}}
	-- CONFIG.dither = compo(norm){{1}}
	-- CONFIG.dither = compo(norm){
		-- { 7,21,33,43,36,19, 9, 4},
		-- {16,27,51,55,49,29,14,11},
		-- {31,47,57,61,59,45,35,23},
		-- {41,53,60,64,62,52,40,38},
		-- {37,44,58,63,56,46,30,22},
		-- {15,28,48,54,50,26,17,10},
		-- { 8,18,34,42,32,20, 6, 2},
		-- { 5,13,25,39,24,12, 3, 1}
	-- }
	-- CONFIG.dither = compo(norm,transp){
		-- {16,49,25,43,29,50,38,11},
		-- {31, 6,52,10,58, 2,24,55},
		-- {41,21,59,15,33,48, 9,63},
		-- { 4,45,36,27,42,19,35,28},
		-- {51,18, 8,64, 3,53,60,14},
		-- {39,54,30,47,23,12,44,26},
		-- { 1,22,13,56,40,32, 7,57},
		-- {34,61,37, 5,17,62,20,46}
	-- }
	-- CONFIG.dither = compo(norm,bayer,vac)(8,8)	-- 256 levels
	-- CONFIG.dither = compo(norm,vac)(8,8)      	-- 64 levels
	-- CONFIG.dither = compo(norm, double, bayer){{1}} -- 8 levels
	-- CONFIG.dither = compo(norm, bayer, bayer){{1}} -- 16 levels
	function VIDEO:pset(x,y, r,g,b)
        if not self.dither then 
			self:init_dither()
			local _mask,_dith,_r,_g,_b,floor = {},{},{},{},{},math.floor
			for x=0,319 do for y=0,199 do
				_dith[x + 320*y] = self.dither:get(x,y)
				_mask[x + 320*y] = 2^(7-(x%8))
			end end
			for i=0,255 do
				local l = PALETTE.linear(i)
				_r[i],_g[i],_b[i] = l*GRAY_R,l*GRAY_G,l*GRAY_B
			end
			self.pset_ovr = function(self, x,y, r,g,b)
				x,y,r,g = floor(x/8+40*y),_mask[x],self.image,_r[r] + _g[g] + _b[b] >= _dith[x+320*y]
				r[x] = r[x] + (g and y or 0) - (r[x]/y % 2 >= 1 and y or 0)
			end
			self.pset_fst = function(self, x,y, r,g,b)
				if _r[r] + _g[g] + _b[b] >= _dith[x+320*y] then 
					y,r = floor(x/8+40*y),self.image
					r[y] = r[y] + _mask[x] 
				end
			end
			self.pset = self.pset_fst
			self.overwrite = function(self, overwrite)
				self._overwrite, self.pset = overwrite, overwrite and self.pset_ovr or self.pset_fst
			end
		end
		self:pset(x,y,r,g,b)
    end
elseif MODE==MODE_RGB2 then -- RGB
	CONFIG.asm_mode  = 1
    CONFIG.px_size   = {1,3}
	CONFIG.dither    = compo(norm,double,bayer){{3,1,2}} -- 24
	CONFIG.dither    = compo(norm,double,bayer){{3,1,4,2}} -- 24
	-- CONFIG.dither    = compo(norm,vac)(12,4) -- 48
	-- CONFIG.dither    = compo(norm,halve,halve,vac)(16,5) -- 20
	
	-- CONFIG.dither    = compo(norm,double){{9,1,5,10,2,6},{12,4,8,11,3,7}}

	-- 12 = 3*4
	-- CONFIG.dither    = compo(norm,vac)(16,5) -- très belle qualité gfx
	
    function VIDEO:pset(x,y, r,g,b)
        if not self.dither then 
			self:init_dither()
            self._linear = {}
            for i=0,255 do self._linear[i]=PALETTE.linear(i) end
            self._mask = {}
            for i=0,319 do self._mask[i]=2^(7-(i%8)) end
        end
		self.pset_ovr = function(self, x,y, r,g,b)
			local f,d = self._linear,self.dither:get(x,y)
			local m,p,q = self._mask[x],math.floor((x+y*960)/8),self.image
			local m2,t = m+m
					t =   q[p   ] if t % m2 >= m then t = t-m end if f[r]>=d then t = t + m end
			q[p   ],t = t,q[p+40] if t % m2 >= m then t = t-m end if f[g]>=d then t = t + m end
			q[p+40],t = t,q[p+80] if t % m2 >= m then t = t-m end if f[b]>=d then t = t + m end
			q[p+80]   = t
		end
		self.pset_fst = function(self, x,y, r,g,b)
			local f,d = self._linear,self.dither:get(x,y)
			local fr,fg,fb = f[r]>=d,f[g]>=d,f[b]>=d
			if fr or fg or fb then
				local m,p,q = self._mask[x],math.floor((x+y*960)/8),self.image
				-- q[p]    = q[p]    + f[r]>=d and m or 0
				-- q[p+40] = q[p+40] + f[g]>=d and m or 0
				-- q[p+80] = q[p+80] + f[b]>=d and m or 0
				if fr then q[p]    = q[p]    + m end
				if fg then q[p+40] = q[p+40] + m end
				if fb then q[p+80] = q[p+80] + m end
			end
		end
		self.overwrite = function(self, ovr)
			self._overwrite, self.pset = ovr, ovr and self.pset_ovr or self.pset_fst
		end
		self.pset = self.pset_fst
		self:pset(x,y, r,g,b)
    end

	for _,f in pairs(VIDEO.font) do
		for i,s in ipairs(f) do
			f[i] = s:gsub('(.)', '%1%1')
		end
	end
elseif MODE==MODE_BM59 then -- BM59
	CONFIG.asm_mode	 = 2
    CONFIG.px_size   = {2,1}
	CONFIG.dither    = 
		-- compo(norm,double,bayer){{1},{2}} 	
		-- compo(norm,bayer){{1,5},
         -- {2,6},
         -- {7,3},
         -- {8,4},
		-- }
		-- compo(norm,halve,bayer,2){{1},{2}}
		-- norm(vac(8,16))
		-- norm(vac(5,11))
		compo(norm,vac)(4,8)
		-- compo(norm,vac)(8,16) -- ok
		
	-- compo(norm,double){
		-- {7,4},
		-- {8,6},
		-- {5,2},
		-- {3,1}
	-- }

	CONFIG.palette   = function(CONVERTER,VIDEO)
		local H = {w={},r=0,g=0,b=0} for i=0,255 do H.w[i]=0 end		
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
					local DIV=8
					f = round(f*DIV)/DIV
					e = e + h[i]*math.abs(v0 + f*(v1-v0) - v)^2
				end
			end
			return t,math.abs(e)
		end

        for i,f in ipairs(arg) do
            local TMP = CONVERTER:new(f,nil,3)
            if TMP then
                local stat = VIDEO:new(TMP.file,TMP.fps,80,100,80,100,
					function(self, x,y, r,g,b)
					local t = math.floor(r*GRAY_R + g*GRAY_G + b*GRAY_B)
					H.w[t],H.r,H.g,H.b = H.w[t]+1,H.r+r,H.g+g,H.b+b
				end, TMP.duration)
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
		
		do local best = 1e300
			for t=0,255 do local x = math.abs(PALETTE.linear(t)*4*(GRAY_R+GRAY_G+GRAY_B)-1)
				if x<best then best = x
					MODE_BM59_PROG_COL = {t,t,t}
				end
			end
		end
		
		local function tint(col)
			local function m(x)
				return round(x*col/math.max(H.r,H.g,H.b,1))
			end
			return m(H.r)+16*m(H.g)+256*m(H.b)
		end
		-- rescale the base to have approx

		return {
			0x000,tint(w.base[2]),tint(w.base[3]),tint(w.base[4]),
			3840,3855,4080,4095,
			1911,826,931,938,
			2611,2618,3815,123
		}
    end
	local otab = {}
	for i=0,159 do otab[i] = 4^(3-(i%4)) end
	function VIDEO:pset(x,y, r,g,b)
		local _l_R,_l_G,l_B
        if not self.dither then 
			self:init_dither()
            self._l_R,self._l_G,self._l_B = {},{},{}
            local f = PALETTE.linear
            for i=0,255 do
				self._l_R[i]=f(i)*3*GRAY_R
				self._l_G[i]=f(i)*3*GRAY_G
				self._l_B[i]=f(i)*3*GRAY_B
			end
			_l_R,_l_G,_l_B = self._l_R,self._l_G,self.l_B
        end
		self.plot_ovr = function(self,p,o,c)
			self.image[p] = self.image[p] + c*o - ((q[p]/o)%4)*o
		end 
		self.plot_fst = function(self,p,o,c)
			self.image[p] = self.image[p] + c*o
		end 
		self.plot = self.plot_fst
		self.overwrite = function(self, ovr)
			self._overwrite, self.plot = ovr, ovr and self.plot_ovr or self.plot_fst
		end
		self.pset = function (self, x,y, r,g,b)
			local l,f = _l_R[r]+_l_G[r]+_l_B[b],math.floor
			self:plot(f(x/4) + y*40, otab[x], 
				(((l%1)>=self.dither:get(x,y)) and f(l) + 1 or f(l)))
		end
    	self:pset(x,y,r,g,b)
    end
elseif MODE==MODE_C345 then
	CONFIG.asm_mode	 = 3
    CONFIG.px_size   = {4,2}
    CONFIG.dither    = compo(norm,double){{1,4},{5,8},{3,2},{7,6}}
	CONFIG.palette   = function(CONVERTER,VIDEO)
		local H = {r={},g={},b={}}
		for i=0,255 do H.r[i]=0; H.g[i]=0; H.b[i]=0 end	
		local function map(vals, histo)
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
					local DIV=4 -- 2
					f = round(f*DIV)/DIV
					e = e + h[i]*math.abs(v0 + f*(v1-v0) - v)^2
				end
			end
			return t,math.abs(e)
		end

        for i,f in ipairs(arg) do
            local TMP = CONVERTER:new(f,nil,1)
            if TMP then
                local stat = VIDEO:new(TMP.file,TMP.fps,80,50,80,50,
					function(self, x,y, r,g,b)
					H.r[r], H.g[g], H.b[b] = H.r[r]+1, H.g[g]+1, H.b[b]+1
				end, TMP.duration)
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
		-- g=5, r=4, b=3
		local r,g,b,t,e
		for i=1,14 do for j=i+1,15 do 
			t,e = map({ef[i],ef[j]}, H.b)
			if b==nil or e<=b.err then b = {err=e, base={0,i,j}} end
		end end
		for i=1,13 do for j=i+1,14 do for k=j+1,15 do
			t,e = map({ef[i],ef[j],ef[k]}, H.r)
			if r==nil or e<=r.err then r = {err=e, base={0,i,j,k}} end
		end end end
		for i=1,12 do for j=i+1,13 do for k=j+1,14 do for l=k+1,15 do
			t,e = map({ef[i],ef[j],ef[k]}, H.g)
			if g==nil or e<=g.err then g = {err=e, base={0,i,j,k,l}} end
		end end end end

		io.stderr:write(string.rep(' ',79)..'\r')
        io.stderr:flush()

		print('b', unpack(b.base))
		print('r', unpack(r.base))
		print('g', unpack(g.base))

		return {
			0x001*r.base[1]+0x100*b.base[1],0x001*r.base[1]+0x100*b.base[2],0x001*r.base[1]+0x100*b.base[3],
			0x001*r.base[2]+0x100*b.base[1],0x001*r.base[2]+0x100*b.base[2],0x001*r.base[2]+0x100*b.base[3],
			0x001*r.base[3]+0x100*b.base[1],0x001*r.base[3]+0x100*b.base[2],0x001*r.base[3]+0x100*b.base[3],
			0x001*r.base[4]+0x100*b.base[1],0x001*r.base[4]+0x100*b.base[2],0x001*r.base[4]+0x100*b.base[3],
			
			0x010*g.base[2],0x010*g.base[3],0x010*g.base[4],0x010*g.base[5]
		}
    end
    function VIDEO:pset(x,y, r,g,b)
        if not self.dither then 
			self:init_dither()
            self._linear = {}
            for i=0,255 do
                local t = PALETTE.linear(i)
                self._linear[i]={t*3,t*4,t*2}
            end
        end
		self.plot_ovr = function(self,p,o,r,g,b)
			local p1,p2,img,t = p,p+40,self.image
			if ZIGZAG and o==1 then p1,p2=p2,p1 end
			t = img[p1]; img[p1] = o==0 and t%16 or t-(t%16)
			t = img[p2]; img[p2] = o==0 and t%16 or t-(t%16)
			o,t = o==0 and 16 or 1,b+r*3
			if t>0 then img[p1] = img[p1] +      t*o end
			if g>0 then img[p2] = img[p2] + (g+11)*o end
		end 
		self.plot_fst = function(self,p,o,r,g,b)
			local p1,p2,img = p,p+40,self.image
			if ZIGZAG and o==1 then p1,p2=p2,p1 end
			o = o==0 and 16 or 1
			local t = b+r*3
			if t>0 then img[p1] = img[p1] +      t*o end
			if g>0 then img[p2] = img[p2] + (g+11)*o end
		end 
		self.plot = self.plot_fst
		self.overwrite = function(self, ovr)
			self._overwrite, self.plot = ovr, ovr and self.plot_ovr or self.plot_fst
		end	
		self.pset = function(self, x,y, r,g,b)
			local f,d = self._linear,self.dither:get(x,y)
			r,g,b = f[r][1],f[g][2],f[b][3]
			if true then
			r = math.floor(r) +
			-- (r%1>self.dither:get(x,3*y+0) and 1 or 0)
			-- (r%1>=(r>=1 and d or self.dither:get(x,3*y+0)) and 1 or 0)
			(r%1>d and 1 or 0)
			g = math.floor(g) +
			-- (g%1>self.dither:get(x,3*y+1) and 1 or 0)
			-- (g%1>=(g>=1 and d or self.dither:get(x,3*y+1)) and 1 or 0)
			(g%1>d and 1 or 0)
			b = math.floor(b) +
			-- (b%1>self.dither:get(x,3*y+2) and 1 or 0)
			-- (b%1>=(b>=1 and d or self.dither:get(x,3*y+2)) and 1 or 0)
			(b%1>d and 1 or 0)
			else
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
			end

			self:plot(math.floor(x/2) + y*80,x%2,r,g,b)
		end
		self:pset(x,y, r,g,b)
    end
elseif MODE==MODE_RGB6 then -- RGB6
    CONFIG.asm_mode	 = 3
    CONFIG.px_size   = {4,3}
	CONFIG.dither    = compo(norm,bayer){{1}}
	CONFIG.palette   = function(CONVERTER,VIDEO)
		local H = {r={},g={},b={}}
		for i=0,255 do H.r[i]=0; H.g[i]=0; H.b[i]=0 end	
		local function map(vals, histo)
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
					local DIV=4--2
					f = round(f*DIV)/DIV
					e = e + h[i]*math.abs(v0 + f*(v1-v0) - v)^2
				end
			end
			return t,math.abs(e)
		end

        for i,f in ipairs(arg) do
            local TMP = CONVERTER:new(f,nil,1)
            if TMP then
                local stat = VIDEO:new(TMP.file,TMP.fps,80,50,80,50,
					function(self, x,y, r,g,b)
					H.r[r], H.g[g], H.b[b] = H.r[r]+1, H.g[g]+1, H.b[b]+1
				end, TMP.duration)
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
		local r,g,b,t,e
		for i=1,11 do for j=i+1,12 do for k=j+1,13 do for l=k+1,14 do for m=l+1,15 do
			t,e = map({ef[i],ef[j],ef[k],ef[l],ef[m]}, H.r)
			if r==nil or e<=r.err then r = {err=e, base={0,i,j,k,l,m}} end
			t,e = map({ef[i],ef[j],ef[k],ef[l],ef[m]}, H.g)
			if g==nil or e<=g.err then g = {err=e, base={0,i,j,k,l,m}} end
			t,e = map({ef[i],ef[j],ef[k],ef[l],ef[m]}, H.b)
			if b==nil or e<=b.err then b = {err=e, base={0,i,j,k,l,m}} end
		end end end end end
		io.stderr:write(string.rep(' ',79)..'\r')
        io.stderr:flush()

		print('b', unpack(b.base))
		print('r', unpack(r.base))
		print('g', unpack(g.base))

		return {
			0x000,			
			0x001*r.base[2],0x001*r.base[3],0x001*r.base[4],0x001*r.base[5],0x001*r.base[6],
			0x010*g.base[2],0x010*g.base[3],0x010*g.base[4],0x010*g.base[5],0x010*g.base[6],
			0x100*b.base[2],0x100*b.base[3],0x100*b.base[4],0x100*b.base[5],0x100*b.base[6]
		}
    end
	function VIDEO:plot(p,o,r,g,b)
		local img = self.image
		if self._overwrite then
			local t
			t = img[p   ]; img[p   ] = o==0 and t%16 or t-(t%16)
			t = img[p+40]; img[p+40] = o==0 and t%16 or t-(t%16)
			t = img[p+80]; img[p+80] = o==0 and t%16 or t-(t%16)
		end
		o = o==0 and 16 or 1
		if r>0 then img[p] = img[p] + r*o end p=p+40
		if g>0 then img[p] = img[p] + g*o end p=p+40
		if b>0 then img[p] = img[p] + b*o end
	end
	local function pset(self, x,y, r,g,b)
		local f,d,int = self._linear,self.dither:get(x,y),math.floor
        r,g,b = f[r],f[g],f[b]
        r = int(r) + 
			(r%1>d and 1 or 0)
			-- (r%1>(r>=1 and d or self.dither:get(x,3*y+0)) and 1 or 0)
			-- (r%1>self.dither:get(x,3*y+0) and 1 or 0)
        g = int(g) + 
			(g%1>d and 1 or 0)
			-- (g%1>(g>=1 and d or self.dither:get(x,3*y+1)) and 1 or 0)
			-- (g%1>self.dither:get(x,3*y+1) and 1 or 0)
        b = int(b) + 
			(b%1>d and 1 or 0)
			-- (b%1>(b>=1 and d or self.dither:get(x,3*y+2)) and 1 or 0)
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
			for i=0,255 do self._linear[i] = PALETTE.linear(i)*5 end
        end
		self.plot_ovr = function(self,p,o,r,g,b)
			local img,t = self.image
			t = img[p   ]; img[p   ] = o==0 and t%16 or t-(t%16)
			t = img[p+40]; img[p+40] = o==0 and t%16 or t-(t%16)
			t = img[p+80]; img[p+80] = o==0 and t%16 or t-(t%16)
			o = o==0 and 16 or 1
			if r>0 then img[p] = img[p] + r*o end p=p+40
			if g>0 then img[p] = img[p] + g*o end p=p+40
			if b>0 then img[p] = img[p] + b*o end
		end 
		self.plot_fst = function(self,p,o,r,g,b)
			local img = self.image
			o = o==0 and 16 or 1
			if r>0 then img[p] = img[p] + r*o end p=p+40
			if g>0 then img[p] = img[p] + g*o end p=p+40
			if b>0 then img[p] = img[p] + b*o end
		end 
		self.plot = self.plot_fst
		self.overwrite = function(self, ovr)
			self._overwrite, self.plot = ovr, ovr and self.plot_ovr or self.plot_fst
		end	
        pset(self,x,y,r,g,b)
		self.pset = pset
    end
elseif MODE==MODE_CR16 then -- color reduction
    CONFIG.asm_mode	 = 3
    CONFIG.px_size   = {4,1}
    CONFIG.dither    = --compo(bayer){{1,4},{9,12},{5,8},{13,16},{3,2},{11,10},{7,6},{15,14}}
		-- compo(bayer,2){{1},{3},{2},{4}}
		-- compo(bayer){{1},{3},{2},{4}}
		-- vac(5,19) --(7,29)
		-- vac(5,17)
		-- vac(3,12) -- ok
		-- compo(bayer,2){{1},{1},{1},{1}}
			double{{1,5},{3,6},{2,7},{4,8},{5,1},{6,3},{7,2},{8,4}}
			compo(bayer){{1},{2},{3},{4}}
	CONFIG.palette   = function(CONVERTER,VIDEO)
        local reducer = ColorReducer:new()
        for i,f in ipairs(arg) do
            local TMP = CONVERTER:new(f,nil,3)
            if TMP then
                local stat = VIDEO:new(TMP.file,TMP.fps,80,50,80,50,
					function(self, x,y, r,g,b)
                    local col = Color:new(r,g,b):toLinear()
                    -- for i=1,1+1000*math.exp(-(x-40)^2/100) do
                        reducer:add(col)
                    -- end
                end, TMP.duration)
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
		-- reducer:boostBorderColors()			
		-- reducer:boostBorderColors()			
		-- for i=1,16 do reducer:boostBorderColors() end
        io.stderr:write(string.rep(' ',79)..'\r')
        io.stderr:flush()
        local pal = reducer:buildPalette(16, true)
        return pal
    end
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
elseif MODE==MODE_RGB4 then -- 
	CONFIG.asm_mode	 = 3
    CONFIG.px_size   = {4,1}
    CONFIG.dither    = vac(3,8)
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
					local DIV=4
					f = round(f*DIV)/DIV
					e = e + h[i]*math.abs(v0 + f*(v1-v0) - v)^2
				end
			end
			return t,math.abs(e)
		end

        for i,f in ipairs(arg) do
            local TMP = CONVERTER:new(f,nil,3)
            if TMP then
                local stat = VIDEO:new(TMP.file,TMP.fps,80,50,80,50,
					function(self, x,y, r,g,b)
					H.r[r], H.g[g], H.b[b] = H.r[r]+1, H.g[g]+1, H.b[b]+1
					local t = math.floor(r*.30 + g*.59 + b*.11)
					H.w[t] = H.w[t]+1
				end, TMP.duration)
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
elseif MODE==MODE_RGB5 then
	CONFIG.asm_mode	 = 3
    CONFIG.px_size   = {4,1}
	CONFIG.dither    = compo(bayer,1){{1},{3},{2},{4}}			
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
					local DIV=8
					f = round(f*DIV)/DIV
					e = e + h[i]*math.abs(v0 + f*(v1-v0) - v)^2
				end
			end
			return t,math.abs(e)
		end

        for i,f in ipairs(arg) do
            local TMP = CONVERTER:new(f,nil,3)
            if TMP then
                local stat = VIDEO:new(TMP.file,TMP.fps,80,50,80,50,
					function(self, x,y, r,g,b)
					H.r[r], H.g[g], H.b[b] = H.r[r]+1, H.g[g]+1, H.b[b]+1
					local t = math.floor(r*.30 + g*.59 + b*.11)
					H.w[t] = H.w[t]+1
				end,TMP.duration)
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
		for i=1,12 do for j=i+1,13 do for k=j+1,14 do for l=k+1,15 do
			t,e = map({ef[i],ef[j],ef[k],ef[l]}, H.r)
			if r==nil or e<=r.err then r = {err=e, base={0,i,j,k,l}} end
			t,e = map({ef[i],ef[j],ef[k],ef[l]}, H.g)
			if g==nil or e<=g.err then g = {err=e, base={0,i,j,k,l}} end
			t,e = map({ef[i],ef[j],ef[k],ef[l]}, H.b)
			if b==nil or e<=b.err then b = {err=e, base={0,i,j,k,l}} end
			t,e = map({ef[i],ef[j],ef[k],ef[l]}, H.w)
			if w==nil or e<=w.err then w = {err=e, base={0,i,j,k,l}} end
		end end end end
		io.stderr:write(string.rep(' ',79)..'\r')
        io.stderr:flush()

		print('b', unpack(b.base))
		print('r', unpack(r.base))
		print('g', unpack(g.base))
		print('w', unpack(w.base))

		return {
			0x000,
			
			0x100*b.base[2],0x010*g.base[2],0x001*r.base[2],
			0x100*b.base[3],0x010*g.base[3],0x001*r.base[3],
			0x100*b.base[4],0x010*g.base[4],0x001*r.base[4],
			
							0x010*g.base[4]+0x001*r.base[5],
			0x100*b.base[5]                +0x001*r.base[4],
			0x100*b.base[5]+0x010*g.base[4]                ,
			
			0x100*b.base[3]+0x010*g.base[3]+0x001*r.base[3],
			0x100*b.base[4]+0x010*g.base[4]+0x001*r.base[4],
			0x100*b.base[5]+0x010*g.base[5]+0x001*r.base[5]
		}
    end
elseif MODE==MODE_EDGE then
    CONFIG.asm_mode     = 0
	CONFIG.ffmpeg_extra = ' -vf "gblur=sigma=1.4"'
    function VIDEO:pset(x,y, r,g,b)
		self:setup_gray()
		for i=1,644 do self._gray[-i], self._gray[63999+i] = 0,0 end
		self._gray2 = {}
		for i=1,644 do self._gray2[-i], self._gray2[63999+i] = 0,0 end
		self._flush = self.filter.flush
		self.filter.flush = function(filter) 
			self._flush(filter)
			
			local gray,img,sqrt = self._gray2,self._gray,math.sqrt
			
			-- sobel operator
			local mx,max = 10,math.max
			-- for p=0,63999 do mx=max(mx,img[p]) end
			-- local K = 255/sqrt(2*(4*255)^2)
			for p=0,63999 do
				local a,b,c, d,e,f,	g,h,i = 
					img[p-321], img[p-320], img[p-319],
					img[p-1],img[p],img[p+1],
					img[p+319],img[p+320],img[p+321]
				local x = (a-c+g-i)+2*(d-f)
				local y = (a+c-g-i)+2*(b-h)		
				-- gray[p] = round(sqrt(x*x+y*y)*K)
				local t = sqrt(x*x+y*y)
				gray[p],mx = t,max(mx,t)
			end
			for p=0,63999 do gray[p] = round(gray[p]*255/mx) end
			-- for x=0,319 do gray[x], gray[63999-x]=0,0 end
			-- for x=0,63999,320 do gray[x], gray[x+319]=0,0 end
			self:otsu(gray)
		end
		self:pset(x,y,r,g,b)
    end
else
	local msg = "Invalid MODE="..(MODE and MODE or "<empty>")
	msg = msg .. "\npossible values are:"
	for _,v in pairs(MODE_TXT) do msg = msg .. " "..v end
    error(msg)
end

function VIDEO:clear()
    for p=0,#self.image do self.image[p] = 0 end
end

function VIDEO:read_rgb24(raw)
	self:clear()
	self:overwrite(false)
	local i,w,b,p = math.floor,self.width,FILTER.byte,self.pset
	local ox = i((self.screen_width - w)/2)
	local oy = i((self.screen_height - 6 - 7 - self.height)/2)+6
	if oy<0 then oy=0 end
	
	local pr = self.filter:push(raw)
	for o=0,w*self.height-1 do
		local x,y,o = ox+(o % w), i(o/w)+oy,o*3
		-- print(y, oy, w, o)
		p(self, x, y,
			b(pr,o+1), -- r
			b(pr,o+2), -- g
			b(pr,o+3)  -- b
		)
	end
	self.filter:flush()
	self:overwrite(true)
end
function VIDEO:progressbar(y, frac, r,g,b)
	local t=round(self.screen_width*math.max(math.min(1,frac),0))
	for x=0,t-1 do self:pset(x,y,r,g,b) end
	for x=t,self.screen_width-1 do self:pset(x,y, 0,0,0) end
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
    return VIDEO:new(self.file, fps or self.fps, self.w, self.h, self.W, self.H, nil, self.duration)
end
function CONVERTER:vidname()
	return basename(self.file):gsub('%-%-(...........)$','') -- cut YT link '  (https://youtu.be//%1)')
							  :gsub('%s*1440p60',''):gsub('%s*1080p',''):gsub('%s*2160p60','')
							  :gsub('%s*%d+%s*[fF][pP][sS]','')
							  :gsub('%s*%[HD%]','')
							  :gsub('%[%]','')
							  :gsub('%s+$','')
end
function CONVERTER:_compress(pos, prev, curr, indices_fcn, out_fcn)
	local k,b0,b1,b2,ci,cj,ck
	for _,i in indices_fcn(prev,curr) do
		while prev[i] ~= curr[i] do
			ck,ci,cj = curr[i-1],curr[i],curr[i+1]
			k = i - pos
			if k<0 then 
				b0,b1,b2,pos = 3,128+math.floor(i/256),i%256,i
			elseif k==0 then
  			     -- local s = string.char(curr[pos-2] or 123, curr[pos-1] or 214,
					-- curr[pos], curr[pos+1], curr[pos+2],
					-- curr[pos+3], curr[pos+4], curr[pos+5])
				-- local s3 = s:sub(3)
				-- if s:sub(1,6)==s3 then 
				if ck==cj and ci==curr[i-2] and ci==curr[i+2] and cj==curr[i+3] 
				then -- rpt4,-2
					b0,b1,b2,pos,prev[i],prev[i+1],prev[i+2],prev[i+3] = 
						3,0xf8,0,pos+4,ci,cj,ci,cj,ci,cj
					if  ci==curr[i+4] and cj==curr[i+5]
					then -- rpt6,-2
						b1,pos,prev[pos],prev[pos+1] = 0xf0,pos+2,ci,cj
					end
				elseif ci==ck        and ci==cj
				   and ci==curr[i+2] and ci==curr[i+3]
				   and ci==curr[i+4] and ci==curr[i+5]
				then -- rpt6,-1
					b0,b1,b2,pos,prev[i],prev[i+1],prev[i+2],prev[i+3],prev[i+4],prev[i+5]
						= 3,0xe0,0,pos+6,ci,ci,ci,ci,ci,ci
				elseif ci==cj and ci==curr[i+2]
			    then -- rpt3
					b0,b1,b2,pos,prev[i],prev[i+1],prev[i+2] = 
						3,0xC0,ci,pos+3,ci,ci,ci
					if ci==curr[i+3] then -- rpt4
						b1,pos,prev[pos] = 0x00,pos+1,ci
					end
				elseif cj==prev[i+1] then
					b0,b1,b2,pos,prev[i],prev[i+2] = 2,ci,curr[i+2],pos+3,ci,curr[i+2]
				else
					b0,b1,b2,pos,prev[i],prev[i+1] = 0,ci,cj,pos+2,ci,cj
				end
			elseif k==1 then
					b0,b1,b2,pos,prev[pos],prev[pos+1] = 
						0,curr[pos],curr[pos+1],pos+2,curr[pos],curr[pos+1]
			elseif k<=257 then -- deplacement 8 bit
				b0,b1,b2,prev[i],pos = 1,k-2,ci,ci,i+1
			else -- deplacement arbitraire
				b0,b1,b2,pos = 3,128+math.floor(i/256),i%256,i
			end
			-- print(zz, b0, b1, b2, '-->', pos)
			-- if b2==nil then print() print(i, b0, b1, b2, curr[i+1]) end
			out_fcn(b0,b1,b2)
		end
	end
	return pos
end
-- Fait un encodage "à vide" et regarde le nombre de trames moyen par image
-- et compare à la limite théorique.
-- Réduit le zoom si on dépasse ou augmente le fps si on a de la marge.
-- Trouve les niveaux min/max et mets en place une correction video si besoin
function CONVERTER:_stat()
    io.stdout:write(self:vidname()..'\n')
    io.stdout:flush()

    -- auto determination des parametres
    local neg_fps = self.fps<0
	self.fps = math.abs(self.fps)
    local stat = self:_new_video((neg_fps and self.fps > FPS_MAX) and 3 or self.fps)
	stat:pset(0,0,0,0,0)
    stat.super_pset = stat.pset
    stat.histo = {}; for i=0,255 do stat.histo[i]=0 end
	function stat:pset(x,y, r,g,b)
		self:super_pset(x,y,r,g,b)
		local h = self.histo
		h[r],h[g],h[b] = h[r]+1,h[g]+1,h[b]+1
	end	
	local chg_color = COLOR<0 and CONFIG.asm_mode==0
	if chg_color then
		stat.n,stat.r,stat.g,stat.b,stat._pset_ = 0,0,0,0,stat.pset
		local function pset(self, x,y, r,g,b)
			self:_pset_(x,y,r,g,b)
			local l = PALETTE.linear
			stat.n,stat.r,stat.g,stat.b = stat.n+1,stat.r+l(r),stat.g+l(g),stat.b+l(b)
		end
		stat.pset = pset
		stat.overwrite = function(self, bool)
			self._overwrite, self.pset = bool, pset
		end
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
	stat._compress = self._compress
    stat.trames = 0
    stat.type = {}; for i=0,3 do stat.type[i]=0 end
    stat.prev_img = {}; for i=0,7999 do stat.prev_img[i]=-1 end
    function stat:count_trames()
		self:_compress(8000, stat.prev_img, stat.image, stat.progressiv, function(b0,b1,b2)
			stat.type[b0],stat.trames = stat.type[b0]+1,stat.trames + (stat.trames % 171 == 169 and 4 or 1)
		end)
    end

    while stat.running do
        stat:next_image()
        stat:count_trames()
    end
    io.stderr:write(string.rep(' ',79)..'\r')
    io.stderr:flush()
	
	-- nb de trames vidéos par image
	local avg_trames = (stat.trames/stat.cpt) -- * 1.15 -- 15% safety margin
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
    -- print('min/max', stat.min, stat.max)
    io.stdout:flush()
    local video_cor = {stat.min, 255/(stat.max - stat.min)}
    self.video_cor = video_cor

    -- info
	local stat_str = string.format('%s %dx%d (%d%%) %dfps %s',
        self.duration>=3600 and hms(self.duration, "%dh%2d'%d\"") or _ms(self.duration, "%d'%d\""), 
        self.w, self.h, 
		percent(math.max(self.w/self.W,self.h/self.H)),
		self.fps, 
		MODE_TXT[MODE],
	nil)
    io.stdout:write('> '..stat_str..'\n')
	local TOT = 0 for i=0,3 do TOT = TOT+stat.type[i] end
    io.stdout:write(string.format('> %d frames: %d%% %d%% %d%% %d%%\n',
                                    TOT,
                                    percent(stat.type[0]/TOT),
                                    percent(stat.type[1]/TOT),
                                    percent(stat.type[2]/TOT),
                                    percent(stat.type[3]/TOT)))
    io.stdout:flush()
	
	if chg_color then -- uses average
		stat.r,stat.g,stat.b = stat.r/stat.n,stat.g/stat.n,stat.b/stat.n
		local m,r_,g_,b_ = 1/math.max(stat.r, stat.g, stat.b)
		local pal = {0x000,0x00F,0x0F0,0x0FF,0xF00,0xF0F,0xFF0,0xFFF,
                   0x666*0,0x338,0x383,0x388,0x833,0x838,0x883,0x069}
		local rgb = function(p) 
			local l = function(x) return PALETTE.linear(PALETTE.ef[1+(math.floor(x)%16)]) end
			return l(p),l(p/16),l(p/256)
		end
		r_,g_,b_,m = stat.r*m,stat.g*m,stat.b*m,1e300
		for i,p in ipairs(pal) do
			local r,g,b,t = rgb(p) t = math.max(r,g,b) r,g,b = r/t,g/t,b/t
			t = 2*(r-r_)^2 + 4*(g-g_)^2 + (b-b_)^2
			-- print(i-1, t, r,g,b, r_,g_,b_)
			if t<m then m,COLOR = t,i-1 end
		end
		if COLOR~=7 then print(r_,g_,b_,'->',COLOR,'=',rgb(pal[COLOR+1])) end
		COLOR = 0x10*COLOR
		-- os.exit(0)
	end
	
	-- self.avg_chg = (2*(stat.type[0]+stat.type[2])+1*stat.type[1])/(stat.type[0]+stat.type[1]+stat.type[2])
	-- print('average bytes changed per frames = ', self.avg_chg)
	return stat_str
end
function CONVERTER:process()
    -- collect stats
    local stat_str = self:_stat()

    -- flux audio/video
    local audio  = AUDIO:new(self.file)
    local video  = self:_new_video()

    -- adaptation luminosité
	-- print(self.video_cor[1],self.video_cor[2])
    if self.video_cor[1]~=0 or self.video_cor[2]~=1 then
        local cor = self.video_cor
	-- print('min/max corr', cor[1],cor[2])
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
    local pos            = 8040

	-- user feedback
	local last_etc=1e38
    local function info()
        local d = os.time() - start
		local t = "> %d%% %s (%3.1fx) e=%5.3f f=%.3f"
		t = t:format(
			percent(tstamp/self.duration), hms(tstamp),
			round(100*tstamp/(d==0 and 100000 or d))/100, completed_imgs/video.cpt,
			video.filter.a)
		local etc = d*(self.duration-tstamp)/tstamp
		if d>10 then if etc>last_etc then etc = last_etc else last_etc = etc end end
		local etr = 5 -- etc>=90 and 10 or 5
		etc = round(etc/etr)*etr
		etc = etc>0 and d>10 and "ETC="..hms(etc) or ""
		t = t .. string.rep(' ', math.max(0,79-t:len()-etc:len())) .. etc 
		return t
	end
	
	-- info utilisateur
	local wchars = VIDEO.font['X'][1]:len()
	local hchars = math.ceil(video.screen_width/wchars)
	local title_x, title_str = 0, self:vidname(self.file):gsub('_',' ')
	local info_sec, time_str = 1,''

	if 8+stat_str:len()>=hchars then 
		for i=1,hchars-1 do title_str = title_str..' ' end
		title_str, stat_str = title_str..' '.. stat_str..' ', ''
		for i=1,hchars do title_str = title_str..' ' end
	elseif title_str:len()>hchars then 
		for i=1,hchars do title_str = title_str..' ' end
	end
	if title_str:len()>hchars and SCROLL then title_x = 1 end

	-- video.framefill_ratio = 0
	local function update_info()
		if video.cpt>=info_sec then
			info_sec = info_sec + video.fps
			tstamp = tstamp + 1
			io.stdout:write(info() .. '\r')
			io.stdout:flush()
			time_str = (self.duration<3600 and _ms(tstamp) or hms(tstamp))
			-- if tstamp>2 then video.running=false end
		end

		-- affichage info écran
		local y_line = math.ceil(200/CONFIG.px_size[2])-7
		if stat_str~='' then 
			video:puts(video.screen_width-wchars*stat_str:len(),y_line, stat_str) 
		end
		video:puts(0,y_line, time_str
					-- ..' b='..percent(video.filter.a)..'%'
					-- ..' f='..math.floor(100*video.framefill_ratio)..'%'
					,nil)
		video:puts(title_x, 0, title_str)
		if title_str:len()>hchars and SCROLL then
			title_x = title_x - 30/(CONFIG.px_size[1]*self.fps)
			if title_x <= -wchars then
				title_x = title_x + wchars
				title_str = title_str:sub(2) .. title_str:sub(1,1)
			end
		end
		local col = MODE<=MODE_DITH and {255,255,255}
               	 or MODE==MODE_BM59 and MODE_BM59_PROG_COL
				 or                     {255,0,0}
		video:progressbar(y_line+6, tstamp/self.duration,unpack(col))
		-- 0..1.1   => green 
		-- 1.1..2.1 => yellow
		-- 2.1..3+	   => red
		-- local x = video.framefill_ratio
		-- video:progressbar(6, x/3, x>1.1 and 255 or 0,x<=2.1 and 255 or 0,0)
	end 
	
	-- la 1ere image doit se faire de 1 en 1
    local curr,prev,first = video.image,self._prev,true
	if prev==nil then
		prev = {} 
		for i=0,7999 do prev[i] = 0 end
	end
	
	local filter_s,filter_a = 1.5,.95 -- .87 -- .925 -- .95
	local filter_b = filter_a -- damp to return to zero
	filter_b = .5 
    -- conversion
	video.filter.a = .95 -- progressive start
    video:next_image() 	
    while audio.running and video.running do
		update_info()
		-- virtual compression
		local cycles = 0
		if MODE>MODE_OTSU then
			local prev2, frame_cnt = {},0
			for i=0,7999 do prev2[i] = prev[i] end cycles = 0
			self:_compress(pos, prev2, video.image, video.progressiv, function(b0,b1,b2) 
				if frame_cnt == 169 then 
					frame_cnt, cycles = 0, cycles + CYCLES*4
				else
					frame_cnt, cycles = frame_cnt+1, cycles + CYCLES
				end
			end)
			
			-- adapt filtering
			if cycles >= filter_s*cycles_per_img then
				local t = cycles
				repeat
					video.filter.a = video.filter.a*filter_a + (1-filter_a)*.85
					t = t - cycles_per_img
				until t<cycles_per_img
			else
				video.filter.a = video.filter.a*filter_b
			end
		else
			video.filter.a = video.filter.a*filter_b
		end
		
		-- real_compression
		-- print((cycles + current_cycle >= 2*cycles_per_img) and 'interlaced' or 'progressive')
		local indices = not first 
			  and (CONFIG.px_size[2]<=1 or video.filter.a>=.85)
			  and (cycles + current_cycle >= 2*cycles_per_img) 
		      and video.interlaced 
			  or  video.progressiv
		cycles, first = 0, false
		pos = self:_compress(pos, prev, video.image, indices, function(b0,b1,b2)
			cycles = cycles + self.out:frame(b0,b1,b2,audio)
		end)
        video.filter:flush()

        completed_imgs, current_cycle = completed_imgs + 1, current_cycle + cycles
		-- video.framefill_ratio = vi	deo.framefill_ratio*filter_b + (1-filter_b)*cycles/cycles_per_img
		
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
            current_cycle = current_cycle + self.out:frame(3,128,0,audio)
            pos = 0
        end

		-- on ne garde que l'offset par rapport au nb de cycles par image souhaité
		current_cycle = current_cycle - cycles_per_img

        -- next image
		if audio.running then video:next_image() end
    end
	tstamp = self.duration -- update_info()
    io.stdout:write(info() .. '\n')
    io.stdout:flush()

	-- update_info()
	for i=0,7999 do prev[i] = curr[i] end
	self._prev = prev
	
    audio:close()
    video:close()
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
	local function to770(mo5col)
		mo5col = 0<mo5col and mo5col<255 and mo5col or 0x70
		local a,b = math.floor(mo5col/16),mo5col%16
		return (b>=8 and 0 or 128)+(b%8) + ((a+8)%16)*8
	end

    local asm_mode=CONFIG.asm_mode --(MODE<6 and MODE) or (MODE%2==0 and 4 or 5)

	self.stream = assert(io.open(self.file, 'wb'))
    self.stream:write(file_content(1*512, raw('bootblk', 'asm/bootblk.ass')))
    self.stream:write(file_content(7*512, raw('player4'..asm_mode, 
											  '-dMODE='..asm_mode..' asm/player4.ass'),
					                          PALETTE:file_content()..
											  string.char(to770(COLOR))))
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
		self:frame(3,255,255, {next_sample=compo(32)})
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
local tag = '['..MODE_TXT[MODE]..'] '
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
    local subs,num,first = substrings(file),0,nil
	local _arg = arg; arg = {}
    for i,f in ipairs(_arg) do
        local TMP = CONVERTER:new(f,nil,3)
        if TMP then
			first = first or f
            subs:intersect(substrings(basename(f)))
			num = num + 1
			arg[num] = f
        end
    end
    file = subs:longest():gsub("%W+$", "")
    if file:len()<=4 then file = basename(first or 'Medley') end
	if num>1 then file = file.."#"..num; COLOR=COLOR>0 and COLOR or 0x70 end
    io.stderr:write("\n===> "..tag..file.." <===\n")
    io.stderr:flush()
end
PALETTE:init(CONFIG.palette(CONVERTER,VIDEO))
local out = OUT:new(tag..file..'.sd')
local first, last_img = true
for i,f in ipairs(arg) do
    local conv = CONVERTER:new(f,out,FPS)
    if conv then
		if not first then io.stdout:write('\n') else first=nil end
		if #arg>1 then 
			conv.super_vidname = conv.vidname
			conv.vidname = function(self) 
				return i..'/'..#arg..' '..self:super_vidname()
			end 
		end
		conv._prev = last_img
		conv:process() 
		last_img = conv._prev
	end
	i=i+1
end
out:close()
