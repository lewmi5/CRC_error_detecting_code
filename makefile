ASM = nasm
ASM_FLAGS = -f elf64 -w+all -w+error -g
LD = ld
LD_FLAGS = --fatal-warnings -g

all: crc

crc.o: crc.asm
$(ASM) $(ASM_FLAGS) -o crc.o crc.asm

crc: crc.o
$(LD) $(LD_FLAGS) -o crc crc.o

clean:
rm -f crc.o crc

.PHONY: all clean
