#include <gint/display.h>
#include <gint/keyboard.h>

/* Penumbra — darkroom helper for the Casio fx-9860GIII.
 *
 * First milestone: a "hello world" that verifies the whole build pipeline
 * (compile -> link gint -> generate .g1a). The real menu and calculators
 * come next. */
int main(void)
{
	dclear(C_WHITE);

	/* Title, centred at the top with a rule underneath. */
	dtext_opt(64, 3, C_BLACK, C_NONE, DTEXT_CENTER, DTEXT_TOP,
		"P E N U M B R A", -1);
	drect(0, 13, 127, 13, C_BLACK);

	dtext(4, 20, C_BLACK, "Darkroom helper");
	dtext(4, 32, C_BLACK, "Toolchain: OK");

	dtext_opt(64, 61, C_BLACK, C_NONE, DTEXT_CENTER, DTEXT_BOTTOM,
		"[EXIT] to quit", -1);

	dupdate();

	/* Wait until EXIT is pressed. */
	while(getkey().key != KEY_EXIT)
		;

	return 1;
}
