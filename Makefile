CC=gcc
CFLAGS=-O3 -Wall
RM=rm

ifeq ($(OS),Windows_NT)
	EXE=.exe
else
	EXE=
endif

MANIFEST=$(wildcard *.manifest)
DSK=$(MANIFEST:%.manifest=%.fd)
SAP=disk.sap

ASM=$(wildcard asm/*.ass) $(wildcard trackdisk/asm/*.ASS)

BIN:=$(ASM:asm/%.ass=bin/%.bin)

LUA=tools/luajit$(EXE)
C6809=tools/c6809$(EXE)

ALL=$(LUA) $(C6809) bin/player0.raw bin/player1.raw bin/bootblk.raw

all: $(ALL)
	ls -l .

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
	-$(RM) 2>/dev/null bin/* $(C6809) $(LUA)
	-cd LuaJIT/ && make clean

tgz: fullclean
	@tar czf `basename "$(PWD)"`.tgz . --exclude=*.zip --exclude=tools/teo --exclude=*.tgz --exclude=dc* --exclude=*/attic/*
	@tar tvf `basename "$(PWD)"`.tgz
	@du `basename "$(PWD)"`.tgz
	
$(LUA): LuaJIT $(wildcard LuaJIT/src/*)
	cd $< && export MAKE="make -f Makefile" && $$MAKE BUILDMODE=static CC="$(CC) -static" CFLAGS="$(CFLAGS)"  
	cp $</src/$(notdir $@) "$@"
	strip "$@"
	
tools/%$(EXE): c6809/%.c
	$(CC) $(CFLAGS) -o "$@" "$<"
	@sleep 1 && strip "$@"
	
bin/%.bin: asm/%.ass $(C6809)
	-$(C6809) -bh -am -oOP "$<" "$@"

bin/player0.raw: asm/player.ass $(C6809)
	-$(C6809) -bd -am -oOP -dGRAY=0 "$<" "$@"

bin/player1.raw: asm/player.ass $(C6809)
	-$(C6809) -bd -am -oOP -dGRAY=1 "$<" "$@"

bin/player3%.raw: asm/player3.ass $(C6809)
	-$(C6809) -bd -am -oOP -dGRAY=$* "$<" "$@"

bin/%.raw: asm/%.ass $(C6809)
	-$(C6809) -bd -am -oOP "$<" "$@"

w:	$(DISK) $(K7)
	../teo/teow.exe -window -m MASS6809.M7 -disk0 `cygpath -w -s "$(PWD)/$(DISK)"` -disk1 `cygpath -w -s "$(PWD)/disk1.sap"` 
	cd sapdir && ../tools/sapfs.exe --extract-all ../$(DISK)
