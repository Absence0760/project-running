import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = dirname(fileURLToPath(import.meta.url));

/// Every share lookup that filters a uuid column by a URL segment must reject
/// a non-uuid BEFORE querying.
///
/// Postgres raises 22P02 when a uuid column is compared to a non-uuid, which
/// PostgREST returns as a 400 and supabase-js surfaces in `error` — so
/// `/share/run/hello` took the `upstream_unreachable` branch and emitted the
/// tagged line a CloudWatch metric filter alarms on. The alarm fires at 5
/// occurrences per 5-minute window, so roughly ten junk share URLs in ten
/// minutes paged the on-call engineer from anonymous traffic, and there is no
/// WAF rate rule on /share/* or /og/*. The alarm's own comment claims that
/// line fires "only on a real infra failure … NOT on a clean not-found".
test('every uuid-keyed share lookup guards its id before querying', () => {
	const files = readdirSync(dir).filter(
		(f) => f.startsWith('share_') && f.endsWith('_lookup.ts'),
	);
	assert.ok(files.length >= 5, 'expected the share lookups to be here');

	for (const f of files) {
		const src = readFileSync(resolve(dir, f), 'utf8');
		// Only lookups that actually filter a uuid `id` column are in scope;
		// slug-keyed ones (clubs) legitimately take any string.
		if (!src.includes(".eq('id'")) continue;

		assert.ok(
			src.includes('isEntityId('),
			`${f} filters a uuid id but does not guard it with isEntityId — a ` +
				`malformed segment will raise 22P02 and trip the upstream alarm`,
		);
		// The guard has to run before the query, not after.
		assert.ok(
			src.indexOf('isEntityId(') < src.indexOf(".eq('id'"),
			`${f} must reject a non-uuid before it queries`,
		);
	}
});
