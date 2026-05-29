import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildFinisherCertificateSvg,
	CERT_WIDTH,
	CERT_HEIGHT,
	type FinisherCertificateInput,
} from './finisher_certificate';

function input(over: Partial<FinisherCertificateInput> = {}): FinisherCertificateInput {
	return {
		eventTitle: 'Riverside 10K',
		finisherName: 'Alex Runner',
		durationS: 3 * 3600 + 25 * 60 + 8, // 3:25:08
		distanceM: 10000,
		rank: 3,
		dateIso: '2026-06-12T08:00:00Z',
		unit: 'km',
		...over,
	};
}

test('renders a well-formed certificate svg with the headline facts', () => {
	const svg = buildFinisherCertificateSvg(input());
	assert.ok(svg.startsWith('<svg'));
	assert.ok(svg.trimEnd().endsWith('</svg>'));
	assert.ok(svg.includes(`viewBox="0 0 ${CERT_WIDTH} ${CERT_HEIGHT}"`));
	assert.ok(svg.includes('Certificate of Completion'));
	assert.ok(svg.includes('Alex Runner'));
	assert.ok(svg.includes('Riverside 10K'));
	assert.ok(svg.includes('3:25:08'));
	assert.ok(svg.includes('10.00 km'));
	assert.ok(svg.includes('3rd place'));
	assert.ok(svg.includes('12 June 2026'));
});

test('formats sub-hour times as m:ss', () => {
	const svg = buildFinisherCertificateSvg(input({ durationS: 22 * 60 + 9 }));
	assert.ok(svg.includes('22:09'));
	assert.ok(!svg.includes('0:22:09'));
});

test('honours the mi unit', () => {
	const svg = buildFinisherCertificateSvg(input({ distanceM: 10000, unit: 'mi' }));
	assert.ok(svg.includes('6.21 mi'));
	assert.ok(!svg.includes(' km'));
});

test('omits the place line when rank is null or zero', () => {
	assert.ok(!buildFinisherCertificateSvg(input({ rank: null })).includes('place'));
	assert.ok(!buildFinisherCertificateSvg(input({ rank: 0 })).includes('place'));
});

test('ordinal handles 1st / 2nd / 11th / 21st / 22nd', () => {
	const place = (n: number) => buildFinisherCertificateSvg(input({ rank: n }));
	assert.ok(place(1).includes('1st place'));
	assert.ok(place(2).includes('2nd place'));
	assert.ok(place(11).includes('11th place'));
	assert.ok(place(21).includes('21st place'));
	assert.ok(place(22).includes('22nd place'));
});

test('escapes XML-special characters in names', () => {
	const svg = buildFinisherCertificateSvg(
		input({ finisherName: 'A & B <Team>', eventTitle: '"Quotes" Run' }),
	);
	assert.ok(svg.includes('A &amp; B &lt;Team&gt;'));
	assert.ok(svg.includes('&quot;Quotes&quot; Run'));
	assert.ok(!svg.includes('<Team>'));
});

test('renders the club name when supplied, drops it otherwise', () => {
	assert.ok(buildFinisherCertificateSvg(input({ clubName: 'Dawn Striders' })).includes('Dawn Striders'));
	const noClub = buildFinisherCertificateSvg(input({ clubName: null }));
	assert.ok(noClub.includes('Certificate of Completion'));
});

test('bad date iso produces no date line but still a valid svg', () => {
	const svg = buildFinisherCertificateSvg(input({ dateIso: 'not-a-date' }));
	assert.ok(svg.trimEnd().endsWith('</svg>'));
});
