#ifndef PENUMBRA_UI_H
#define PENUMBRA_UI_H

/* Shared UI helpers for Penumbra screens (128x64 mono display). */

/* Draw a centred title at the top with a horizontal rule under it. */
void ui_title(const char *title);

/* Draw a centred hint at the very bottom of the screen. */
void ui_footer(const char *hint);

/* Map a gint key code to a digit 0-9, or -1 if it isn't a number key. */
int ui_key_digit(int key);

/* An editable non-negative integer field. */
typedef struct {
	int value;   /* current value */
	int max;     /* inclusive upper bound; digits that would exceed it are ignored */
} ui_intfield;

/* Apply a key to a field: number keys append a digit (capped at max), DEL
 * removes the last digit. Returns 1 if the key was consumed. */
int ui_intfield_key(ui_intfield *f, int key);

#endif /* PENUMBRA_UI_H */
