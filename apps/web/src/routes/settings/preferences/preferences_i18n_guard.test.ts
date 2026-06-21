// Source-level guard: the Settings → Preferences page is the highest-
// traffic settings save surface, and every save-failure / telemetry
// toast on it must route through the i18n `m()` layer like its sibling
// settings pages (settingsAccount.saveFailed, settingsGear.saveFailed).
// A regression to a hardcoded English literal ships a broken toast to
// every non-English user.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { en } from '../../../lib/i18n/locales/en';

const __dirname = dirname(fileURLToPath(import.meta.url));
const page = readFileSync(resolve(__dirname, '+page.svelte'), 'utf-8');

test('preferences save-failure toasts use the i18n key, not a literal', () => {
	assert.doesNotMatch(
		page,
		/showToast\(`(Couldn't save|Save failed):/,
		"Save-failure toast must use m('prefs.saveFailed', { error }) — a hardcoded literal ships untranslated to every non-English user.",
	);
	assert.match(
		page,
		/m\('prefs\.saveFailed', \{ error:/,
		"Preferences page must route its save-failure toast through m('prefs.saveFailed').",
	);
});

test('preferences telemetry toggle toasts use i18n keys, not literals', () => {
	assert.doesNotMatch(
		page,
		/'Error reporting (enabled|disabled)/,
		"Telemetry toggle toast must use m('prefs.telemetryEnabledToast') / m('prefs.telemetryDisabledToast').",
	);
	assert.match(page, /m\('prefs\.telemetryEnabledToast'\)/);
	assert.match(page, /m\('prefs\.telemetryDisabledToast'\)/);
});

test('the toast keys exist in the en catalogue with the right placeholder', () => {
	assert.equal(en['prefs.saveFailed'], "Couldn't save: {error}");
	assert.ok(en['prefs.telemetryEnabledToast']);
	assert.ok(en['prefs.telemetryDisabledToast']);
});
