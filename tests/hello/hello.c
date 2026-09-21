/*
 * Minimal bare-metal test firmware for the arduino-uno-r4 machine.
 *
 * Linked at 0x4000 like an Arduino sketch, so it only runs if the board
 * sets the reset VTOR past the bootloader. It prints a line on SCI9
 * (serial0) by polling TDRE, then drives D13 (P102) high through PCNTR3
 * and reads it back through PCNTR1, which exercises the width-decoded
 * port registers.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#include <stdint.h>

#define SCI9_BASE   0x40070120u
#define SCI_SCR     (*(volatile uint8_t *)(SCI9_BASE + 0x02))
#define SCI_TDR     (*(volatile uint8_t *)(SCI9_BASE + 0x03))
#define SCI_SSR     (*(volatile uint8_t *)(SCI9_BASE + 0x04))
#define SCR_TE      0x20u
#define SSR_TDRE    0x80u

#define PORT1_PCNTR1 (*(volatile uint32_t *)0x40040020u)  /* PODR:PDR */
#define PORT1_PCNTR3 (*(volatile uint32_t *)0x40040028u)  /* PORR:POSR */
#define D13          (1u << 2)                            /* P102 */

extern uint32_t _estack;
void reset_handler(void);

__attribute__((section(".vectors"), used))
static const void *const vectors[2] = { &_estack, (const void *)reset_handler };

static void sci9_puts(const char *s)
{
    while (*s) {
        while (!(SCI_SSR & SSR_TDRE)) {
        }
        SCI_TDR = (uint8_t)*s++;
    }
}

void reset_handler(void)
{
    SCI_SCR = SCR_TE;
    sci9_puts("arduino-uno-r4: hello from 0x4000\r\n");

    PORT1_PCNTR1 |= D13;            /* PDR: output */
    PORT1_PCNTR3 = D13;             /* POSR: drive high */
    sci9_puts((PORT1_PCNTR1 >> 16) & D13 ? "D13: high\r\n" : "D13: low\r\n");

    for (;;) {
    }
}
