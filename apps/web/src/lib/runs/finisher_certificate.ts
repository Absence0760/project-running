/// Pure finisher-certificate SVG builder (persona #44 — event organiser).
/// Event organisers wanted a downloadable certificate for finishers; this
/// renders one client-side as an SVG string that `rasterizeSvgToPng`
/// turns into a PNG download — no server PDF service, no new dependency.
/// Pure string concatenation so the wire shape is unit-testable.

export interface FinisherCertificateInput {
	eventTitle: string;
	finisherName: string;
	durationS: number;
	distanceM: number;
	rank: number | null;
	dateIso: string;
	unit: 'km' | 'mi';
	/// Club / organiser name shown under the brand strap. Optional.
	clubName?: string | null;
}

export const CERT_WIDTH = 1400;
export const CERT_HEIGHT = 990;

function fmtTime(seconds: number): string {
	const s = Math.max(0, Math.round(seconds));
	const h = Math.floor(s / 3600);
	const m = Math.floor((s % 3600) / 60);
	const sec = s % 60;
	const mm = String(m).padStart(2, '0');
	const ss = String(sec).padStart(2, '0');
	return h > 0 ? `${h}:${mm}:${ss}` : `${m}:${ss}`;
}

function fmtDistance(meters: number, unit: 'km' | 'mi'): string {
	if (unit === 'mi') return `${(meters / 1609.344).toFixed(2)} mi`;
	return `${(meters / 1000).toFixed(2)} km`;
}

function fmtDate(iso: string): string {
	const d = new Date(iso);
	if (Number.isNaN(d.getTime())) return '';
	const months = [
		'January', 'February', 'March', 'April', 'May', 'June',
		'July', 'August', 'September', 'October', 'November', 'December',
	];
	return `${d.getUTCDate()} ${months[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
}

function ordinal(n: number): string {
	const s = ['th', 'st', 'nd', 'rd'];
	const v = n % 100;
	return n + (s[(v - 20) % 10] ?? s[v] ?? s[0]);
}

function xmlEscape(s: string): string {
	return s
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&apos;');
}

/// Build the finisher-certificate SVG. Landscape, cream background with a
/// brand-accent border; finisher name is the hero, time + distance +
/// placing sit below.
export function buildFinisherCertificateSvg(input: FinisherCertificateInput): string {
	// Multi-word family names use SINGLE quotes: these strings are interpolated
	// into double-quoted SVG attributes (font-family="..."), so a double quote
	// here would terminate the attribute and make the whole SVG malformed XML —
	// the Image load then fails and no certificate is ever produced.
	const F = "Georgia,'Times New Roman',serif";
	const SANS = "system-ui,-apple-system,'Segoe UI',Roboto,sans-serif";
	const W = CERT_WIDTH;
	const H = CERT_HEIGHT;
	const ACCENT = '#b45309'; // amber-700, a "medal" tone
	const INK = '#1f2937'; // slate-800
	const MUTED = '#6b7280';
	const parts: string[] = [];

	parts.push(
		`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">`,
	);
	parts.push(`<rect width="${W}" height="${H}" fill="#fffdf7"/>`);
	// Double border.
	parts.push(
		`<rect x="28" y="28" width="${W - 56}" height="${H - 56}" fill="none" stroke="${ACCENT}" stroke-width="6"/>`,
	);
	parts.push(
		`<rect x="44" y="44" width="${W - 88}" height="${H - 88}" fill="none" stroke="${ACCENT}" stroke-width="2" opacity="0.5"/>`,
	);

	parts.push(
		`<text x="${W / 2}" y="150" font-family="${SANS}" font-size="30" font-weight="800" letter-spacing="6" fill="${ACCENT}" text-anchor="middle">THREKIR</text>`,
	);
	parts.push(
		`<text x="${W / 2}" y="250" font-family="${F}" font-size="58" font-weight="700" fill="${INK}" text-anchor="middle">Certificate of Completion</text>`,
	);
	parts.push(
		`<text x="${W / 2}" y="320" font-family="${SANS}" font-size="28" fill="${MUTED}" text-anchor="middle">This certifies that</text>`,
	);

	parts.push(
		`<text x="${W / 2}" y="430" font-family="${F}" font-size="84" font-weight="700" fill="${INK}" text-anchor="middle">${xmlEscape(input.finisherName)}</text>`,
	);
	// Underline rule beneath the name.
	parts.push(
		`<line x1="${W / 2 - 360}" y1="460" x2="${W / 2 + 360}" y2="460" stroke="${ACCENT}" stroke-width="2" opacity="0.5"/>`,
	);

	parts.push(
		`<text x="${W / 2}" y="540" font-family="${SANS}" font-size="30" fill="${MUTED}" text-anchor="middle">completed</text>`,
	);
	parts.push(
		`<text x="${W / 2}" y="600" font-family="${F}" font-size="46" font-weight="700" fill="${ACCENT}" text-anchor="middle">${xmlEscape(input.eventTitle)}</text>`,
	);

	// Stat row: time · distance · (place).
	const stats: string[] = [
		`Time ${fmtTime(input.durationS)}`,
		`Distance ${fmtDistance(input.distanceM, input.unit)}`,
	];
	if (input.rank != null && input.rank > 0) stats.push(`${ordinal(input.rank)} place`);
	parts.push(
		`<text x="${W / 2}" y="690" font-family="${SANS}" font-size="34" font-weight="600" fill="${INK}" text-anchor="middle">${xmlEscape(stats.join('   •   '))}</text>`,
	);

	const dateStr = fmtDate(input.dateIso);
	if (dateStr) {
		parts.push(
			`<text x="${W / 2}" y="850" font-family="${SANS}" font-size="26" fill="${MUTED}" text-anchor="middle">${xmlEscape(dateStr)}</text>`,
		);
	}
	if (input.clubName) {
		parts.push(
			`<text x="${W / 2}" y="888" font-family="${SANS}" font-size="22" fill="${MUTED}" text-anchor="middle">${xmlEscape(input.clubName)}</text>`,
		);
	}

	parts.push('</svg>');
	return parts.join('');
}
