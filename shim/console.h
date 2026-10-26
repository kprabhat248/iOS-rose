#pragma once
#include <stdint.h>

#define FB_BASE		0x7c010000UL	/* fleur: mblock-18-framebuffer */
#define FB_W		1080
#define FB_H		2400
/* a8r8g8b8. This header is shared with fleur, whose shim was verified with
 * 4320, so the scan pitch comes from the build: build-rosemary.sh passes
 * -DFB_STRIDE=4352 (LK reports 0x1100 for rosemary's panel). */
#ifndef FB_STRIDE
#define FB_STRIDE	(1080 * 4)
#endif

#define RED	0xffff0000U
#define BLUE	0xff0000a0U
#define WHITE	0xffffffffU
#define YELLOW	0xffffff00U
#define GREEN	0xff00ff00U
#define BLACK	0xff000000U

extern volatile uint32_t *con_fb;

void con_clear(uint32_t bg);
void con_skip(void);
void con_str(const char *label, const char *s);
void con_hex(const char *label, uint64_t v);
/* label, then "a=xxxxxxxx b=xxxxxxxx" style pairs of 32-bit values */
void con_hex2(const char *label, const char *a, uint32_t va, const char *b, uint32_t vb);
