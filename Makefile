MKEXE=chmod a+rx
STRIP=strip
WGET=wget
SED=sed -e
GIT=git
RM=rm
CP=cp
7Z=7z

VERSION:=$(shell git describe --abbrev=0)
MACHINE:=$(shell uname -m)
DATE:=$(shell date +%FT%T%Z || date)
TMP:=$(shell mktemp)
OS:=$(shell uname -o)
EXE=

CC=gcc
CFLAGS=-O3 -Wall

ifeq ($(OS),Windows_NT)
	OS:=win
endif

ifeq ($(OS),Cygwin)
	OS:=win
endif

ifeq ($(OS),win)
	EXE=.exe
	CC=i686-w64-mingw32-gcc -m32
	MACHINE=x86
	FFMPEG_URL=https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.7z 
	YT_DL_URL=https://youtube-dl.org/downloads/latest/youtube-dl.exe
else
	YT_DL_URL=https://yt-dl.org/downloads/latest/youtube-dl
endif

DISTRO=SDDrive-$(VERSION)-$(OS)-$(MACHINE)

BIN=bin/bootblk.raw bin/player0.raw bin/player1.raw \
    bin/player40.raw bin/player41.raw bin/player42.raw \
	bin/player43.raw bin/player44.raw bin/player45.raw

LUA=tools/luajit$(EXE)
C6809=tools/c6809$(EXE)
FFMPEG=tools/ffmpeg$(EXE)
YT_DL=tools/youtube-dl$(EXE)

ALL=$(LUA) $(BIN) $(FFMPEG) $(YT_DL)

all: $(ALL)
	ls -l .

clean:
	-$(RM) -rf 2>/dev/null bin $(DISTRO) $(C6809)* $(LUA)* $(FFMPEG)* $(YT_DL)*
	-cd LuaJIT/ && make clean

distro: $(DISTRO)
	zip -u -r "$(DISTRO).zip" "$<"

$(DISTRO): $(ALL) \
	$(DISTRO)/ $(DISTRO)/bin/ $(DISTRO)/tools/ \
	$(DISTRO)/README.html do_wrappers \
	$(DISTRO)/tools/sdvideo.lua $(DISTRO)/tools/conv_sd.lua
	$(CP) $(BIN) $@/bin/
	$(CP) $(LUA)* $(FFMPEG)* $(YT_DL)* $@/tools/
	$(GIT) log >$@/ChangeLog.txt
	
do_wrappers: $(DISTRO)/sdvideo.bat $(DISTRO)/conv_sd.bat 

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
HTML_TO=-|$(SED) 's%tools/luajit\s+%tools/luajit.exe tools/%g'>
endif
	
$(DISTRO)/%.html: %.md
	grip -h >/dev/null || pip3 install grip
	grip --wide --export "$<" $(HTML_TO) "$@"

$(DISTRO)/tools/%.lua: %.lua
	$(SED) 's%\$$Version\$$%$(VERSION)%g;s%\$$Date\$$%$(DATE)%g' $< >$@

%/:
	mkdir -p "$@"

tst: tst_conv_sd tst_sdvideo

tst_conv_sd: $(ALL)
	nice -19 \
	$(LUA) conv_sd.lua https://www.youtube.com/watch?v=uOyaCOViAPA
	
tst_sdvideo: $(ALL)
	for i in {0..19}; do \
		echo "MODE=$$i"; \
		MODE=$$i \
		nice -19 \
		$(LUA) sdvideo.lua \
			https://www.youtube.com/watch?v=sBKmqkh9bb8 \
			https://www.youtube.com/watch?v=ThFCg0tBDck \
			https://www.youtube.com/watch?v=c5UoU7O3AzQ;\
	done
	
$(LUA): LuaJIT $(wildcard LuaJIT/src/*)
	cd $< && export MAKE="make -f Makefile" && $$MAKE BUILDMODE=static CC="$(CC) -static" CFLAGS="$(CFLAGS)"  
	$(CP) $</src/$(notdir $@) "$@"
	$(CP) $</COPYRIGHT "$@"-COPYRIGHT
	$(STRIP) "$@"
	
$(FFMPEG):
	$(7Z) --help >/dev/null || apt-cyg install p7zip
	$(WGET) $(FFMPEG_URL) -O $(TMP)
	$(7Z) e $(TMP) LICENSE -r -so >$(FFMPEG)-LICENSE
	$(7Z) e $(TMP) ffmpeg$(EXE) -r -so >$(FFMPEG)
	$(MKEXE) $(FFMPEG)
	$(RM) $(TMP)
	
$(YT_DL):
	$(WGET) $(YT_DL_URL) -O $@
	$(MKEXE) $@
	$(WGET) https://raw.githubusercontent.com/ytdl-org/youtube-dl/master/LICENSE -O $@-LICENSE
	
tools/%$(EXE): c6809/%.c 
	$(CC) $(CFLAGS) -o "$@" "$<"
	@sleep 1 && strip "$@"

c6809/%.c:
	$(WGET) http://www.pulsdemos.com/c6809/c6809-0.83.zip
	unzip c6809-0.83.zip

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
