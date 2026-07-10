#include <gint/display.h>
#include <gint/keyboard.h>
#include "ui.h"
#include "screens.h"

/* Chemistry dilution — darkroom "1+X" notation (1 part stock + X parts water).
 * The user edits X and the target total volume; the concentrate and water
 * volumes are recomputed live. concentrate + water always equals the total. */
void screen_dilution(void)
{
	ui_intfield water_parts = { .value = 9,   .max = 999 };   /* the X in 1+X */
	ui_intfield total_ml     = { .value = 500, .max = 9999 };  /* target volume */
	int field = 0;   /* 0 = dilution, 1 = volume */

	while(1) {
		/* Compute in tenths of a millilitre so we can show one decimal
		 * without floating point. concentrate = total / (1 + X). */
		int denom  = 1 + water_parts.value;
		int total_t = total_ml.value * 10;
		int conc_t  = (total_t + denom / 2) / denom;   /* rounded */
		int water_t = total_t - conc_t;                /* exact remainder */

		dclear(C_WHITE);
		ui_title("Chem dilution");           /* title y=1, rule y=10 */

		/* input fields with a cursor on the active one */
		dtext(2, field == 0 ? 13 : 23, C_BLACK, ">");
		dprint(10, 13, C_BLACK, "Dilution 1 + %d", water_parts.value);
		dprint(10, 23, C_BLACK, "Volume   %d ml", total_ml.value);

		drect(0, 32, 127, 32, C_BLACK);
		dprint(4, 34, C_BLACK, "Conc  %d.%d ml", conc_t / 10, conc_t % 10);
		dprint(4, 44, C_BLACK, "Water %d.%d ml", water_t / 10, water_t % 10);

		/* footer sits on rows ~55-63; content above stays clear of it */
		ui_footer("EXIT:menu  ^v:field");
		dupdate();

		key_event_t ev = getkey();
		switch(ev.key) {
			case KEY_EXIT:
				return;
			case KEY_UP:
				field = 0;
				break;
			case KEY_DOWN:
				field = 1;
				break;
			default:
				ui_intfield_key(field == 0 ? &water_parts : &total_ml, ev.key);
				break;
		}
	}
}
