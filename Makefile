CC=gcc
CFLAGS=-O3 -Wall
GIT=git
WGET=wget
MKEXE=chmod 777
RM=rm
CP=cp
7Z=7z

VERSION=$(shell git describe --abbrev=0)
MACHINE=$(shell uname -m)
OS=$(shell uname -o)
TMP:=$(shell mktemp)
EXE=

ifeq ($(OS),Windows_NT)
	OS=Win
endif

ifeq ($(OS),Cygwin)
	OS=Win
endif

ifeq ($(OS),Win)
	EXE=.exe
	CC=i686-w64-mingw32-gcc -m32
	MACHINE=x86
	FFMPEG_URL=https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.7z 
endif

DISTRO=SDDrive-$(VERSION)-$(OS)-$(MACHINE)

BIN=bin/bootblk.raw bin/player0.raw bin/player1.raw \
    bin/player40.raw bin/player41.raw bin/player42.raw \
	bin/player43.raw bin/player44.raw bin/player45.raw

LUA=tools/luajit$(EXE)
C6809=tools/c6809$(EXE)
FFMPEG=tools/ffmpeg$(EXE)

ALL=$(LUA) $(BIN) $(FFMPEG)

all: $(ALL)
	ls -l .

distro: $(DISTRO)
	zip -u -r "$@.zip" "$<"

$(DISTRO): $(ALL) \
	$(DISTRO)/ $(DISTRO)/bin/ $(DISTRO)/tools/ \
	$(DISTRO)/README.html wrappers
	$(CP) $(BIN) $@/bin/
	$(CP) $(LUA) $@/tools/luajit$(EXE)
	$(CP) $(FFMPEG) $@/tools/ffmpeg$(EXE)
	$(CP) sdvideo.lua conv_sd.lua $@/tools/

wrappers: $(DISTRO)/sdvideo.bat $(DISTRO)/conv_sd.bat 

ifeq ($(OS),Win)
$(DISTRO)/%.bat: %.lua
	echo  >$@ '@echo off'
	echo >>$@ '%~dsp0\tools\luajit$(EXE) %~dsp0\tools\$*.lua %*'
	echo >>$@ 'pause'
else
$(DISTRO)/%.bat:
	echo  >$(DISTRO)/$* '#!/usr/bin/env sh'
	echo >>$(DISTRO)/$* 'dir=`dirname "$$0"`'
	echo >>$(DISTRO)/$* 'exec $$dir/luajit$(EXE) $$dir/tools\$*.lua "$$@"'
	$(MKEXE) $(DISTRO)/$*
endif

ifeq ($(OS),Win)
HTML_TO=
else
HTML_TO=-|sed -e 's%tools/luajit\s+%tools/luajit.exe tools/%g'>
endif
	
$(DISTRO)/%.html: %.md
	grip -h >/dev/null || pip3 install grip
	grip --wide --export "$<" $(HTML_TO) "$@"

%/:
	mkdir -p "$@"

tst: tst_conv_sd tst_sdvideo

tst_conv_sd: $(ALL)
	nice -19 \
	$(LUA) conv_sd.lua  "test/MMD Bad Apple!! Now in 3D with more Color-.mp4"
	
tst_sdvideo: $(ALL)
	for i in {0..15}; do \
		echo "MODE=$$i"; \
		MODE=$$i \
		nice -19 \
		$(LUA) sdvideo.lua \
			"test/Medley.mp4" \
			"test/remember to breathe - Travel Alberta, Canada.flv" \
			"test/spinning_a_mountain.mp4";\
	done

clean:
	-$(RM) -rf 2>/dev/null bin $(C6809) $(LUA) $(DISTRO)
	-cd LuaJIT/ && make clean
	
$(LUA): LuaJIT $(wildcard LuaJIT/src/*)
	cd $< && export MAKE="make -f Makefile" && $$MAKE BUILDMODE=static CC="$(CC) -static" CFLAGS="$(CFLAGS)"  
	cp $</src/$(notdir $@) "$@"
	strip "$@"
	
$(FFMPEG):
	$(7Z) --help >/dev/null || apt-cyg install p7zip
	$(WGET) $(FFMPEG_URL) -O $(TMP)
	$(7Z) e $(TMP) ffmpeg$(EXE) -r -so >$(FFMPEG)
	$(MKEXE) $(FFMPEG)
	$(RM) $(TMP)
	
tools/%$(EXE): c6809/%.c
	$(CC) $(CFLAGS) -o "$@" "$<"
	@sleep 1 && strip "$@"
	
bin/%.bin: asm/%.ass $(C6809) bin/
	-$(C6809) -bh -am -oOP "$<" "$@"

bin/player0.raw: asm/player.ass $(C6809) bin/
	-$(C6809) -bd -am -oOP -dGRAY=0 "$<" "$@"

bin/player1.raw: asm/player.ass $(C6809) bin/
	-$(C6809) -bd -am -oOP -dGRAY=1 "$<" "$@"

bin/player4%.raw: asm/player4.ass $(C6809) bin/
	-$(C6809) -bd -am -oOP -dMODE=$* "$<" "$@"

bin/%.raw: asm/%.ass $(C6809) bin/
	-$(C6809) -bd -am -oOP "$<" "$@"
	
LuaJIT:
	$(GIT) clone https://github.com/LuaJIT/LuaJIT.git

tgz: fullclean
	@tar czf `basename "$(PWD)"`.tgz . --exclude=*.zip --exclude=tools/teo --exclude=*.tgz --exclude=dc* --exclude=*/attic/*
	@tar tvf `basename "$(PWD)"`.tgz
	@du `basename "$(PWD)"`.tgz

w:	$(DISK) $(K7)
	../teo/teow.exe -window -m MASS6809.M7 -disk0 `cygpath -w -s "$(PWD)/$(DISK)"` -disk1 `cygpath -w -s "$(PWD)/disk1.sap"` 
	cd sapdir && ../tools/sapfs.exe --extract-all ../$(DISK)
