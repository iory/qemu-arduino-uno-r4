CC ?= arm-none-eabi-gcc
CFLAGS = -mcpu=cortex-m4 -mthumb -Os -ffreestanding -nostdlib -Wall -Wextra

hello.elf: hello.c link.ld
	$(CC) $(CFLAGS) -T link.ld -o $@ hello.c

clean:
	rm -f hello.elf
