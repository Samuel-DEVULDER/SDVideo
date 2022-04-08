##############################################################################
# Makefile for SDDrive by Samuel Devulder
##############################################################################

STRIP=strip
WGET=wget
SED=sed -e
GIT=git
RM=rm
CP=cp
7Z=7z

VERSION:=$(shell git describe --tags --abbrev=0)
MACHINE:=$(shell uname -m)
DATE:=$(shell date +%FT%T%Z || date)
TMP:=$(shell mktemp)
OS:=$(shell uname -o | tr "/" "_")
EXE=

SHELL=bash
BAT=.sh
BAT_1ST=\#!/usr/bin/env $(SHELL)
BAT_DIR=`dirname $$0`
SETENV=export
MKEXE=chmod a+rx

CC=gcc
CFLAGS=-O3 -Wall

ifeq ($(OS),Windows_NT)
	OS:=win
endif

ifeq ($(OS),Cygwin)
	OS:=win
endif

ifeq ($(OS),win)
	CC=i686-w64-mingw32-gcc -m32
	MACHINE=x86
	EXE=.exe

	BAT=.bat
	BAT_1ST=@echo off
	BAT_DIR=%~dsp0
	SETENV=set
	FFMPEG_URL=https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.7z 
	YT_DL_URL=https://github.com/yt-dlp/yt-dlp/releases/download/2022.03.08.1/yt-dlp_x86.exe
else
	FFMPEG_URL=https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz
	YT_DL_URL=https://github.com/yt-dlp/yt-dlp/releases/download/2022.03.08.1/yt-dlp
endif

DISTRO=SDDrive-$(VERSION)-$(OS)-$(MACHINE)

BIN=bin/bootblk.raw bin/player0.raw bin/player1.raw \
    bin/player40.raw bin/player41.raw bin/player42.raw \
	bin/player43.raw bin/player44.raw bin/player45.raw

TOOLS=tools/
LUA=$(TOOLS)luajit$(EXE)
C6809=$(TOOLS)c6809$(EXE)
FFMPEG=$(TOOLS)ffmpeg$(EXE)
YT_DL=$(TOOLS)yt-dlp$(EXE)

ALL=$(TOOLS) $(LUA) $(BIN) $(FFMPEG) $(YT_DL)

##############################################################################

all: $(ALL)
	ls -l .

clean:
	-$(RM) -rf 2>/dev/null bin $(DISTRO) $(C6809)* $(LUA)* $(FFMPEG)* $(YT_DL)*
	-cd LuaJIT/ && make clean


##############################################################################
# Distribution stuff

distro: $(DISTRO) 
	zip --help >/dev/null || apt-cyg install zip || sudo apt-get install zip
	zip -u -r "$(DISTRO).zip" "$<"

$(DISTRO): $(ALL) \
	$(DISTRO)/ $(DISTRO)/bin/ $(DISTRO)/tools/ $(DISTRO)/tools/lib/ \
	$(DISTRO)/README.html do_wrappers do_examples \
	$(DISTRO)/tools/sdvideo.lua $(DISTRO)/tools/conv_sd.lua
	$(CP) lib/* $(DISTRO)/tools/lib/
	$(CP) $(BIN) $@/bin/
	$(CP) $(LUA)* $(FFMPEG)* $(YT_DL)* $@/tools/
	$(GIT) log >$@/ChangeLog.txt
	
do_wrappers: $(DISTRO)/sdvideo$(BAT) $(DISTRO)/conv_sd$(BAT)
	
$(DISTRO)/%$(BAT): %.lua
	@echo  >$@ '$(BAT_1ST)'
ifeq ($(OS),win)
	@echo >>$@ '$(BAT_DIR)\tools\luajit$(EXE) $(BAT_DIR)\tools\$< %*'
else
	@echo >>$@ 'dir=$(BAT_DIR)'
	@echo >>$@ 'exec $$dir/tools/luajit$(EXE) $$dir/tools/$< "$$@"'
endif
	@$(MKEXE) $@

ifeq ($(OS),win)
HTML_TO=
else
HTML_TO=-|$(SED) 's%tools/luajit\s+%tools/luajit.exe tools/%g'>
endif
	
$(DISTRO)/%.html: %.md 
	grip -h >/dev/null || make install_grip
	grip --wide --export "$<" $(HTML_TO) "$@"

install_grip:
	pip3 -v 2>&1 >/dev/null || sudo apt install python3-pip
	pip3 install grip

$(DISTRO)/tools/%.lua: %.lua
	$(SED) 's%\$$Version\$$%$(VERSION)%g;s%\$$Date\$$%$(DATE)%g' $< >$@

##############################################################################
# Testing
tst: tst_conv_sd tst_sdvideo

tst_conv_sd: $(ALL)
	nice -19 \
	$(LUA) conv_sd.lua https://www.youtube.com/watch?v=uOyaCOViAPA
	
tst_sdvideo: $(ALL)
	for i in 0 1 2 3 4 5 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19; do \
		echo; \
		echo "MODE=$$i"; \
		MODE=$$i \
		nice -19 \
		$(LUA) sdvideo.lua \
			https://www.youtube.com/watch?v=sBKmqkh9bb8 \
			https://www.youtube.com/watch?v=ThFCg0tBDck \
			https://www.youtube.com/watch?v=c5UoU7O3AzQ;\
	done
	
##############################################################################
# Build/download external tools

$(LUA): LuaJIT/ $(wildcard LuaJIT/src/*)
	cd $< && export MAKE="make -f Makefile" && $$MAKE BUILDMODE=static CC="$(CC) -static" CFLAGS="$(CFLAGS)"  
	$(CP) $</src/$(notdir $@) "$@"
	$(CP) $</COPYRIGHT "$@"-COPYRIGHT
	$(STRIP) "$@"

LuaJIT/:
	$(GIT) clone https://github.com/LuaJIT/LuaJIT.git

ifeq ($(OS),win)
$(FFMPEG):
	$(7Z) --help >/dev/null || apt-cyg install p7zip || sudo apt-get install p7zip
	$(WGET) $(FFMPEG_URL) -O $(TMP)
	$(7Z) e $(TMP) LICENSE -r -so >$(FFMPEG)-LICENSE 
	$(7Z) e $(TMP) ffmpeg$(EXE) -r -so >$(FFMPEG)
	$(MKEXE) $(FFMPEG)
	$(RM) $(TMP)
else
$(FFMPEG):
	$(WGET) $(FFMPEG_URL) -O $(TMP)
	cd $(TOOLS) && tar xvf $(TMP) 
	$(CP) $(TOOLS)ffmpeg*static/ffmpeg $(FFMPEG)
	$(CP) $(TOOLS)ffmpeg*static/readme.txt $(FFMPEG)-README
	$(CP) $(TOOLS)ffmpeg*static/GPL* $(FFMPEG)-LICENSE
	$(RM) $(TMP)
	$(RM) -rf $(TOOLS)ffmpeg*static
endif

$(YT_DL):
	$(WGET) $(YT_DL_URL) -O $@
	$(MKEXE) $@
	$(WGET) https://raw.githubusercontent.com/yt-dlp/yt-dlp/master/LICENSE -O $@-LICENSE

##############################################################################
# Compile our stuff

# Our assembler
tools/%$(EXE): c6809/%.c 
	$(CC) $(CFLAGS) -o "$@" "$<"
	@sleep 1 && strip "$@"

c6809/%.c:
	$(WGET) http://www.pulsdemos.com/c6809/c6809-0.83.zip
	unzip c6809-0.83.zip

# Standard thomson binaries
bin/%.bin: asm/%.ass $(C6809) bin/
	-$(C6809) -bh -am -oOP "$<" "$@"

# Thomson binaries without format
bin/player0.raw: asm/player.ass $(C6809) bin/
	-$(C6809) -bd -am -oOP -dGRAY=0 "$<" "$@"

bin/player1.raw: asm/player.ass $(C6809) bin/
	-$(C6809) -bd -am -oOP -dGRAY=1 "$<" "$@"

bin/player4%.raw: asm/player4.ass $(C6809) bin/
	-$(C6809) -bd -am -oOP -dMODE=$* "$<" "$@"

bin/%.raw: asm/%.ass $(C6809) bin/
	-$(C6809) -bd -am -oOP "$<" "$@"

# Create folder	
%/:
	mkdir -p "$@"

# Old
tgz: fullclean
	@tar czf `basename "$(PWD)"`.tgz . --exclude=*.zip --exclude=tools/teo --exclude=*.tgz --exclude=dc* --exclude=*/attic/*
	@tar tvf `basename "$(PWD)"`.tgz
	@du `basename "$(PWD)"`.tgz

w:	$(DISK) $(K7)
	../teo/teow.exe -window -m MASS6809.M7 -disk0 `cygpath -w -s "$(PWD)/$(DISK)"` -disk1 `cygpath -w -s "$(PWD)/disk1.sap"` 
	cd sapdir && ../tools/sapfs.exe --extract-all ../$(DISK)

##############################################################################
# Setup example folder

EXAMPLES=Touhou Cat Russians Spinning Skies Bat Turtles A500 2nd_R Desert Micro Pink Discovery Shaka Indi

EXAMPLES_RUME=$(EXAMPLES:%=$(DISTRO)/examples/%/runme$(BAT))

do_examples: $(DISTRO)/examples/fill_all$(BAT) $(EXAMPLES_RUME)

.PHONY: phony
 
$(DISTRO)/examples/fill_all$(BAT):$(DISTRO)/examples/ Makefile
	@echo -n "Generating $@..."
	@echo  >$@ '$(BAT_1ST)'
	@echo >>$@ 'pushd $(BAT_DIR)'
ifeq ($(OS),win)
	@for d in $(EXAMPLES); do echo >>$@ "call $$d\runme$(BAT)"; done
else
	@for d in $(EXAMPLES); do echo >>$@ "$$SHELL $$d/runme$(BAT)"; done
endif
	@echo >>$@ 'popd'
	@$(MKEXE) $@
	@echo "done"

ifeq ($(OS),win)
INVOKE=call ..\..\ 
else
INVOKE=$$SHELL ../../
endif
INVOKE:=$(strip $(INVOKE))

$(DISTRO)/examples/%/runme$(BAT): $(DISTRO)/examples/%/ Makefile
	@echo -n "Generating $@..."
	@echo  >$@ '$(BAT_1ST)'
	@echo >>$@ 'pushd $(BAT_DIR)'
	@echo >>$@ 'echo Building "$*" -- $(URL_$*)'
	@for m in $(VAR_$*); do echo >>$@ "$(SETENV) $$m"; done
	@if test -n "$(VID_$*)"; then \
		for m in $(VID_$*); do \
			echo >>$@ "$(SETENV) MODE=$$m"; \
			echo >>$@ '$(INVOKE)sdvideo$(BAT) $(URL_$*)'; \
		done; \
	else \
		echo >>$@ '$(INVOKE)conv_sd$(BAT) $(URL_$*)'; \
	fi
	@echo >>$@ 'popd'
	@echo >>$@ 'echo Done "$*"'
	@$(MKEXE) $@
	@echo "done"

$(DISTRO)/examples/%/:
	mkdir -p $@

##############################################################################
# Example data

# Bad Apple - conv_sd
URL_Touhou=https://www.youtube.com/watch?v=uOyaCOViAPA

# Double Trouble - Simon's Cat
URL_Cat=https://www.youtube.com/watch?v=sHWEc-yxfb4
# URL_Cat=https://www.youtube.com/watch?v=3VLcLH97eRw
VID_Cat=0
VAR_Cat=FPS=11

# Sting - Russians
URL_Russians=https://www.youtube.com/watch?v=wHylQRVN2Qs
VID_Russians=0

# Aliens in 60 seconds
# URL_Aliens=https://www.youtube.com/watch?v=LOzU9n_o7dU
# VID_Aliens=0

# Brel à l'Olympia
# URL_Olympia=https://www.dailymotion.com/video/x17ty2g
# VID_Olympia=0 17 16

# Pink Floyd - Delicate soud of thunder
URL_Pink=https://www.youtube.com/playlist?list=PLk3LgDZ_RH0MyrYJOnTNe0qN6XFhAbG9T
VID_Pink=1 18 19
#4 5 7 9 11 15 17 19

# Indiana Jones - Boulder scene
# URL_Indi=https://www.youtube.com/watch?v=x2WAkHuEVHQ
# URL_Indi=https://www.youtube.com/watch?v=aADExWV1bsM
# URL_Indi=https://www.youtube.com/watch?v=c6XHLe94SJA
URL_Indi=https://www.youtube.com/watch?v=IaiOm7ZIuzA
VID_Indi=10 11 18 19
VAR_Indi=FPS=-20

# Microcosmos
# URL_Micro=https://www.dailymotion.com/video/x84o53
URL_Micro=https://vimeo.com/84981267
VID_Micro=2 3 18 19

# DaftPunk - Discovery
URL_Discovery=https://www.youtube.com/playlist?list=PLSdoVPM5WnndLX6Ngmb8wktMF61dJirKl
VID_Discovery=4 5 1

# Shaka Punk
URL_Shaka=https://www.youtube.com/watch?v=210jld2vrxQ  https://www.youtube.com/watch?v=EF2PGnZmXCI  https://www.youtube.com/watch?v=-LVWXQ2F3KI https://www.youtube.com/watch?v=kp4ENt3aK-I https://www.youtube.com/watch?v=iMtcqx4vXXA https://www.youtube.com/watch?v=9RRhKrrbFwE https://www.youtube.com/watch?v=MEecsZXQjCs 
VID_Shaka=10 11 1

# Brain Control - Turtles all the way down
URL_Turtles=https://www.youtube.com/watch?v=sBKmqkh9bb8
VID_Turtles=1 18 19

# Batman forver
# URL_Bat=https://www.youtube.com/watch?v=FKa7X-5L8es
URL_Bat=https://www.youtube.com/watch?v=YJosZfm560Q
VID_Bat=2 3

# Spinning a mountain
URL_Spinning=https://www.youtube.com/watch?v=c5UoU7O3AzQ
VID_Spinning=1 6 7 

# Skies
URL_Skies=https://www.youtube.com/watch?v=r6sgojf-LzM
VID_Skies=1 10 11

# Commodore Amiga 500 Best Demo Effects
URL_A500=https://www.youtube.com/watch?v=G3HUp7LH5ig
VID_A500=6 7
VAR_A500=FPS=11

# Second Reality by Future Crew (PC Demo)
URL_2nd_R=https://www.youtube.com/watch?v=L33eQfT72yo
# https://www.youtube.com/watch?v=TpD4j42elks
VID_2nd_R=4 5
VAR_2nd_R=FPS=11

# Kefrensh megademo
URL_Desert=https://www.youtube.com/watch?v=4HuJK5nITyo https://www.youtube.com/watch?v=fYpLZhkkyRs
VID_Desert=4 5

