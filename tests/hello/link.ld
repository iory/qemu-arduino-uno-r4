/* Same layout as an Arduino UNO R4 sketch: code after the 16 KiB bootloader. */
MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00004000, LENGTH = 240K
    RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 32K
}

_estack = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS
{
    .text : { KEEP(*(.vectors)) *(.text*) *(.rodata*) } > FLASH
    /DISCARD/ : { *(.ARM.*) *(.comment) *(.note*) }
}
