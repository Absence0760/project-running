#!/usr/bin/env node
// Generates the embedded age-grade factor tables for both the web and mobile
// parity helpers from the authoritative RunScore-format source files in
// ./source_2025/. Run from anywhere:
//
//   node scripts/age_grade/gen_age_grade_tables.mjs
//
// Outputs (both committed, never hand-edit — re-run this instead):
//   apps/web/src/lib/runs/age_grade_tables.ts
//   apps/mobile_android/lib/age_grade_tables.dart
//
// Source: USATF Masters Long Distance Running (MLDR) 2025 age-grade tables,
// compiled by Alan Jones + Tom Bernhard, approved 2025-01-10. Distributed
// CC0 1.0 (public domain) at github.com/AlanLyttonJones/Age-Grade-Tables
// ("2025 Files/AgeGrade.zip"). These are the current road-running age-grade
// standard (the WMA/USATF road tables). See ./source_2025/Readme-2025.txt and
// docs/architecture/decisions.md for the provenance + why this edition.
//
// File format (one file per standard distance, e.g. AgeGrade.5k):
//   line 1:  "M  H:MM:SS"   open-class (world-standard) time, male
//   line 2:  "F  H:MM:SS"   open-class time, female
//   then     "M <age> <factor>"  for ages 5..99, then the same for "F".
// Age grade % = openStandardSec / (actualTimeSec * factor) * 100.

import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC = join(HERE, 'source_2025');
const REPO = join(HERE, '..', '..');

const AGE_MIN = 5;
const AGE_MAX = 99;

// File-extension -> { distanceM, label }. The marathon ships in the source as
// both "42k" and "26m" with identical standards; we keep one (42k) mapped to
// the certified marathon distance and drop the duplicate.
const DISTANCES = {
	'1mi': { distanceM: 1609.344, label: '1 mile' },
	'5k': { distanceM: 5000, label: '5 km' },
	'6k': { distanceM: 6000, label: '6 km' },
	'4mi': { distanceM: 6437.376, label: '4 miles' },
	'8k': { distanceM: 8000, label: '8 km' },
	'5mi': { distanceM: 8046.72, label: '5 miles' },
	'10k': { distanceM: 10000, label: '10 km' },
	'7mi': { distanceM: 11265.408, label: '7 miles' },
	'12k': { distanceM: 12000, label: '12 km' },
	'15k': { distanceM: 15000, label: '15 km' },
	'10mi': { distanceM: 16093.44, label: '10 miles' },
	'20k': { distanceM: 20000, label: '20 km' },
	hm: { distanceM: 21097.5, label: 'Half marathon' },
	'25k': { distanceM: 25000, label: '25 km' },
	'30k': { distanceM: 30000, label: '30 km' },
	'42k': { distanceM: 42195, label: 'Marathon' },
	'50k': { distanceM: 50000, label: '50 km' },
	'50mi': { distanceM: 80467.2, label: '50 miles' },
	'100k': { distanceM: 100000, label: '100 km' },
	'150k': { distanceM: 150000, label: '150 km' },
	'100mi': { distanceM: 160934.4, label: '100 miles' },
	'200k': { distanceM: 200000, label: '200 km' },
};

function parseTimeToSeconds(t) {
	const parts = t.split(':').map((p) => Number(p));
	if (parts.some((n) => Number.isNaN(n))) throw new Error(`bad time: ${t}`);
	let s = 0;
	for (const p of parts) s = s * 60 + p;
	return s;
}

function parseFile(ext) {
	const raw = readFileSync(join(SRC, `AgeGrade.${ext}`), 'utf8');
	const lines = raw.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
	const std = { male: null, female: null };
	const factors = { male: new Array(AGE_MAX - AGE_MIN + 1).fill(null), female: new Array(AGE_MAX - AGE_MIN + 1).fill(null) };
	for (const line of lines) {
		const tok = line.split(/\s+/);
		const sex = tok[0] === 'M' ? 'male' : tok[0] === 'F' ? 'female' : null;
		if (!sex) throw new Error(`bad sex token in ${ext}: ${line}`);
		if (tok.length === 2) {
			std[sex] = parseTimeToSeconds(tok[1]);
		} else if (tok.length === 3) {
			const age = Number(tok[1]);
			const fac = Number(tok[2]);
			if (Number.isNaN(age) || Number.isNaN(fac)) throw new Error(`bad row in ${ext}: ${line}`);
			if (age < AGE_MIN || age > AGE_MAX) throw new Error(`age out of range in ${ext}: ${line}`);
			factors[sex][age - AGE_MIN] = fac;
		} else {
			throw new Error(`unexpected token count in ${ext}: ${line}`);
		}
	}
	if (std.male == null || std.female == null) throw new Error(`missing standard in ${ext}`);
	for (const sex of ['male', 'female']) {
		for (let i = 0; i < factors[sex].length; i++) {
			if (factors[sex][i] == null) throw new Error(`missing ${sex} factor age ${i + AGE_MIN} in ${ext}`);
		}
	}
	return { std, factors };
}

// Guard: every file present in the source dir is either mapped or the known
// 26m marathon duplicate — never silently drop a distance.
const present = readdirSync(SRC)
	.filter((f) => f.startsWith('AgeGrade.'))
	.map((f) => f.slice('AgeGrade.'.length));
for (const ext of present) {
	if (ext !== '26m' && !DISTANCES[ext]) throw new Error(`unmapped source file AgeGrade.${ext} — add it to DISTANCES or exclude it explicitly`);
}

const rows = Object.entries(DISTANCES)
	.map(([ext, meta]) => {
		const { std, factors } = parseFile(ext);
		return {
			key: ext,
			label: meta.label,
			distanceM: meta.distanceM,
			openStandardSecMale: std.male,
			openStandardSecFemale: std.female,
			maleFactors: factors.male,
			femaleFactors: factors.female,
		};
	})
	.sort((a, b) => a.distanceM - b.distanceM);

const PROVENANCE = `USATF MLDR 2025 long-distance running age-grade tables (Alan Jones
 * + Tom Bernhard, approved 2025-01-10), the current road-running age-grade
 * standard. Source: github.com/AlanLyttonJones/Age-Grade-Tables (CC0 1.0).
 * GENERATED by scripts/age_grade/gen_age_grade_tables.mjs from the RunScore
 * files in scripts/age_grade/source_2025/ — do not hand-edit; re-run the
 * generator to refresh or swap editions.`;

function facList(arr) {
	return arr.join(', ');
}

// ---- TypeScript ----
let ts = `// ${PROVENANCE.replace(/\n \* /g, '\n// ')}\n//\n`;
ts += `// Factor arrays are indexed by (age - ${AGE_MIN}); they cover ages ${AGE_MIN}..${AGE_MAX}.\n\n`;
ts += `export const AGE_GRADE_AGE_MIN = ${AGE_MIN};\nexport const AGE_GRADE_AGE_MAX = ${AGE_MAX};\n\n`;
ts += `export interface AgeGradeDistance {\n`;
ts += `\t/** Source-file key, e.g. '5k', 'hm', '42k'. */\n\treadonly key: string;\n`;
ts += `\t/** Human label, e.g. '5 km', 'Half marathon', 'Marathon'. */\n\treadonly label: string;\n`;
ts += `\t/** Certified distance in metres. */\n\treadonly distanceM: number;\n`;
ts += `\t/** Open-class (world-standard) time in seconds. */\n\treadonly openStandardSec: { readonly male: number; readonly female: number };\n`;
ts += `\t/** Age factors for ages ${AGE_MIN}..${AGE_MAX}, indexed by (age - ${AGE_MIN}). */\n\treadonly factors: { readonly male: readonly number[]; readonly female: readonly number[] };\n`;
ts += `}\n\n`;
ts += `/** Standard distances ascending by metres. Generated — see header. */\n`;
ts += `export const AGE_GRADE_DISTANCES: readonly AgeGradeDistance[] = [\n`;
for (const r of rows) {
	ts += `\t{\n`;
	ts += `\t\tkey: '${r.key}',\n`;
	ts += `\t\tlabel: '${r.label}',\n`;
	ts += `\t\tdistanceM: ${r.distanceM},\n`;
	ts += `\t\topenStandardSec: { male: ${r.openStandardSecMale}, female: ${r.openStandardSecFemale} },\n`;
	ts += `\t\tfactors: {\n`;
	ts += `\t\t\tmale: [${facList(r.maleFactors)}],\n`;
	ts += `\t\t\tfemale: [${facList(r.femaleFactors)}],\n`;
	ts += `\t\t},\n`;
	ts += `\t},\n`;
}
ts += `];\n`;
writeFileSync(join(REPO, 'apps/web/src/lib/runs/age_grade_tables.ts'), ts);

// ---- Dart ----
let dart = `// ${PROVENANCE.replace(/\n \* /g, '\n// ')}\n//\n`;
dart += `// Factor lists are indexed by (age - ${AGE_MIN}); they cover ages ${AGE_MIN}..${AGE_MAX}.\n\n`;
dart += `const int ageGradeAgeMin = ${AGE_MIN};\nconst int ageGradeAgeMax = ${AGE_MAX};\n\n`;
dart += `class AgeGradeDistance {\n`;
dart += `  /// Source-file key, e.g. '5k', 'hm', '42k'.\n  final String key;\n`;
dart += `  /// Human label, e.g. '5 km', 'Half marathon', 'Marathon'.\n  final String label;\n`;
dart += `  /// Certified distance in metres.\n  final double distanceM;\n`;
dart += `  /// Open-class (world-standard) time in seconds, male.\n  final double openStandardSecMale;\n`;
dart += `  /// Open-class (world-standard) time in seconds, female.\n  final double openStandardSecFemale;\n`;
dart += `  /// Male age factors for ages ${AGE_MIN}..${AGE_MAX}, indexed by (age - ${AGE_MIN}).\n  final List<double> maleFactors;\n`;
dart += `  /// Female age factors for ages ${AGE_MIN}..${AGE_MAX}, indexed by (age - ${AGE_MIN}).\n  final List<double> femaleFactors;\n\n`;
dart += `  const AgeGradeDistance({\n`;
dart += `    required this.key,\n    required this.label,\n    required this.distanceM,\n`;
dart += `    required this.openStandardSecMale,\n    required this.openStandardSecFemale,\n`;
dart += `    required this.maleFactors,\n    required this.femaleFactors,\n  });\n}\n\n`;
dart += `/// Standard distances ascending by metres. Generated — see header.\n`;
dart += `const List<AgeGradeDistance> ageGradeDistances = [\n`;
function dnum(n) {
	// Dart needs a decimal point for doubles in a `double` field.
	return Number.isInteger(n) ? `${n}.0` : `${n}`;
}
for (const r of rows) {
	dart += `  AgeGradeDistance(\n`;
	dart += `    key: '${r.key}',\n`;
	dart += `    label: '${r.label}',\n`;
	dart += `    distanceM: ${dnum(r.distanceM)},\n`;
	dart += `    openStandardSecMale: ${dnum(r.openStandardSecMale)},\n`;
	dart += `    openStandardSecFemale: ${dnum(r.openStandardSecFemale)},\n`;
	dart += `    maleFactors: [${r.maleFactors.map(dnum).join(', ')}],\n`;
	dart += `    femaleFactors: [${r.femaleFactors.map(dnum).join(', ')}],\n`;
	dart += `  ),\n`;
}
dart += `];\n`;
writeFileSync(join(REPO, 'apps/mobile_android/lib/age_grade_tables.dart'), dart);

console.log(`Generated ${rows.length} distances -> age_grade_tables.ts + age_grade_tables.dart`);
