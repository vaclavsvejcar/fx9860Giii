#include <gint/display.h>
#include <gint/keyboard.h>
#include "ui.h"

void ui_title(const char *title)
{
	dtext_opt(64, 1, C_BLACK, C_NONE, DTEXT_CENTER, DTEXT_TOP, title, -1);
	drect(0, 10, 127, 10, C_BLACK);
}

void ui_footer(const char *hint)
{
	dtext_opt(64, 63, C_BLACK, C_NONE, DTEXT_CENTER, DTEXT_BOTTOM, hint, -1);
}

int ui_key_digit(int key)
{
	switch(key) {
		case KEY_0: return 0;
		case KEY_1: return 1;
		case KEY_2: return 2;
		case KEY_3: return 3;
		case KEY_4: return 4;
		case KEY_5: return 5;
		case KEY_6: return 6;
		case KEY_7: return 7;
		case KEY_8: return 8;
		case KEY_9: return 9;
		default:    return -1;
	}
}

int ui_intfield_key(ui_intfield *f, int key)
{
	int d = ui_key_digit(key);
	if(d >= 0) {
		int nv = f->value * 10 + d;
		if(nv <= f->max)
			f->value = nv;
		return 1;
	}
	if(key == KEY_DEL) {
		f->value /= 10;
		return 1;
	}
	return 0;
}
