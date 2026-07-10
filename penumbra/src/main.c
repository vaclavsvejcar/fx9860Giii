#include <gint/display.h>
#include <gint/keyboard.h>
#include "ui.h"
#include "screens.h"

/* Placeholder for functions that aren't built yet. */
static void screen_soon(void)
{
	while(1) {
		dclear(C_WHITE);
		ui_title("Coming soon");
		dtext_opt(64, 30, C_BLACK, C_NONE, DTEXT_CENTER, DTEXT_MIDDLE,
			"Not built yet.", -1);
		ui_footer("[EXIT] back");
		dupdate();
		if(getkey().key == KEY_EXIT)
			return;
	}
}

typedef struct {
	const char *name;
	void (*run)(void);
} menu_item;

static const menu_item items[] = {
	{ "Chemistry dilution", screen_dilution },
	{ "Temp compensation",  screen_soon },
	{ "Development timer",   screen_soon },
};
#define NITEMS ((int)(sizeof(items) / sizeof(items[0])))

int main(void)
{
	int sel = 0;

	while(1) {
		dclear(C_WHITE);
		ui_title("PENUMBRA");

		for(int i = 0; i < NITEMS; i++) {
			int y = 15 + i * 11;
			if(i == sel) {
				drect(0, y - 1, 127, y + 9, C_BLACK);
				dtext(5, y + 1, C_WHITE, items[i].name);
			} else {
				dtext(5, y + 1, C_BLACK, items[i].name);
			}
		}

		ui_footer("EXE:open  EXIT:quit");
		dupdate();

		key_event_t ev = getkey();
		switch(ev.key) {
			case KEY_UP:
				sel = (sel + NITEMS - 1) % NITEMS;
				break;
			case KEY_DOWN:
				sel = (sel + 1) % NITEMS;
				break;
			case KEY_EXE:
				items[sel].run();
				break;
			case KEY_EXIT:
				return 1;
		}
	}
}
