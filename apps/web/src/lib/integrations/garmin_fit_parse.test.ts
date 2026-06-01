import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { parseFitBuffer } from './garmin-fit';

const SEMI = 2 ** 31 / 180;

function crc16(buf: Uint8Array): number {
	const table = [
		0x0000, 0xcc01, 0xd801, 0x1400, 0xf001, 0x3c00, 0x2800, 0xe401, 0xa001, 0x6c00, 0x7800,
		0xb401, 0x5000, 0x9c01, 0x8801, 0x4400,
	];
	let crc = 0;
	for (let i = 0; i < buf.length; i++) {
		const byte = buf[i];
		let tmp = table[crc & 0xf];
		crc = (crc >> 4) & 0x0fff;
		crc = crc ^ tmp ^ table[byte & 0xf];
		tmp = table[crc & 0xf];
		crc = (crc >> 4) & 0x0fff;
		crc = crc ^ tmp ^ table[(byte >> 4) & 0xf];
	}
	return crc;
}

/// Hand-rolled minimal FIT encoder — a trail run with Running Dynamics +
/// two GPS records. Just enough of the binary protocol for the real
/// `fit-file-parser` to decode it, so the test exercises `parseFitBuffer`
/// end-to-end (F1 sub_sport, F2 running_dynamics, and the track the
/// strava-zip path reuses for F4).
function buildSyntheticTrailFit(): ArrayBuffer {
	const chunks: Buffer[] = [];
	type FieldDef = { num: number; baseType: number; size: number; put: (b: Buffer, o: number, v: number) => void };
	const U8: FieldDef = { num: 0, baseType: 0x02, size: 1, put: (b, o, v) => (b[o] = v) };
	const U16: FieldDef = { num: 0, baseType: 0x84, size: 2, put: (b, o, v) => b.writeUInt16LE(v, o) };
	const U32: FieldDef = { num: 0, baseType: 0x86, size: 4, put: (b, o, v) => b.writeUInt32LE(v >>> 0, o) };
	const S32: FieldDef = { num: 0, baseType: 0x85, size: 4, put: (b, o, v) => b.writeInt32LE(v, o) };
	const ENUM: FieldDef = { num: 0, baseType: 0x00, size: 1, put: (b, o, v) => (b[o] = v) };

	function emit(globalNum: number, localNum: number, fieldDefs: FieldDef[], values: number[]) {
		const def = Buffer.alloc(6 + fieldDefs.length * 3);
		def[0] = 0x40 | localNum;
		def.writeUInt16LE(globalNum, 3);
		def[5] = fieldDefs.length;
		fieldDefs.forEach((f, i) => {
			def[6 + i * 3] = f.num;
			def[6 + i * 3 + 1] = f.size;
			def[6 + i * 3 + 2] = f.baseType;
		});
		chunks.push(def);
		let dataLen = 1;
		fieldDefs.forEach((f) => (dataLen += f.size));
		const data = Buffer.alloc(dataLen);
		data[0] = localNum;
		let off = 1;
		fieldDefs.forEach((f, i) => {
			f.put(data, off, values[i]);
			off += f.size;
		});
		chunks.push(data);
	}

	const t0 = 1000000000;

	emit(
		0,
		0,
		[
			{ ...ENUM, num: 0 },
			{ ...U32, num: 4 },
			{ ...U32, num: 3, baseType: 0x8c },
		],
		[4, t0, 12345],
	);

	const recDefs: FieldDef[] = [
		{ ...U32, num: 253 },
		{ ...S32, num: 0 },
		{ ...S32, num: 1 },
		{ ...U16, num: 2 },
	];
	const lat1 = Math.round(51.5 * SEMI);
	const lon1 = Math.round(-0.12 * SEMI);
	const lat2 = Math.round(51.51 * SEMI);
	const lon2 = Math.round(-0.11 * SEMI);
	emit(20, 1, recDefs, [t0, lat1, lon1, (100 + 500) * 5]);
	{
		const data = Buffer.alloc(1 + 4 + 4 + 4 + 2);
		data[0] = 1;
		let off = 1;
		data.writeUInt32LE(t0 + 60, off);
		off += 4;
		data.writeInt32LE(lat2, off);
		off += 4;
		data.writeInt32LE(lon2, off);
		off += 4;
		data.writeUInt16LE((110 + 500) * 5, off);
		chunks.push(data);
	}

	const sessDefs: FieldDef[] = [
		{ ...U32, num: 2 },
		{ ...ENUM, num: 5 },
		{ ...ENUM, num: 6 },
		{ ...U32, num: 7 },
		{ ...U32, num: 8 },
		{ ...U32, num: 9 },
		{ ...U16, num: 22 },
		{ ...U8, num: 16 },
		{ ...U16, num: 20 },
		{ ...U16, num: 89 },
		{ ...U16, num: 91 },
		{ ...U16, num: 134 },
	];
	emit(18, 2, sessDefs, [
		t0,
		1,
		3,
		3600 * 1000,
		3500 * 1000,
		10000 * 100,
		250,
		152,
		312,
		Math.round(8.4 * 10),
		Math.round(246 * 10),
		Math.round(1180 * 10),
	]);

	const body = Buffer.concat(chunks);
	const header = Buffer.alloc(14);
	header[0] = 14;
	header[1] = 0x10;
	header.writeUInt16LE(2140, 2);
	header.writeUInt32LE(body.length, 4);
	header.write('.FIT', 8, 'ascii');
	header.writeUInt16LE(crc16(header.subarray(0, 12)), 12);

	const full = Buffer.concat([header, body]);
	const crc = Buffer.alloc(2);
	crc.writeUInt16LE(crc16(full), 0);
	const out = Buffer.concat([full, crc]);
	return out.buffer.slice(out.byteOffset, out.byteOffset + out.byteLength) as ArrayBuffer;
}

test('parseFitBuffer — trail run preserves sub_sport + activity_type=run (F1)', async () => {
	const parsed = await parseFitBuffer(buildSyntheticTrailFit());
	assert.ok(parsed, 'expected a parsed run');
	// activity_type collapses to the generic 'run' (there is no 'trail'),
	// but the discipline survives on sub_sport.
	assert.equal(parsed!.activity_type, 'run');
	assert.equal(parsed!.sub_sport, 'trail');
});

test('parseFitBuffer — Running Dynamics land off the session (F2)', async () => {
	const parsed = await parseFitBuffer(buildSyntheticTrailFit());
	assert.deepEqual(parsed!.running_dynamics, {
		vertical_oscillation_mm: 8.4,
		gct_ms: 246,
		stride_length_m: 1.18,
		power_w: 312,
	});
});

test('parseFitBuffer — GPS track survives (the trace strava-zip reuses for F4)', async () => {
	const parsed = await parseFitBuffer(buildSyntheticTrailFit());
	assert.equal(parsed!.track.length, 2);
	assert.ok(Math.abs(parsed!.track[0].lat - 51.5) < 1e-4);
	assert.ok(Math.abs(parsed!.track[0].lng - -0.12) < 1e-4);
	assert.equal(parsed!.track[0].ele, 100);
});

test('parseFitBuffer — core scalars round-trip', async () => {
	const parsed = await parseFitBuffer(buildSyntheticTrailFit());
	assert.equal(parsed!.distance_m, 10000);
	assert.equal(parsed!.duration_s, 3500);
	assert.equal(parsed!.avg_bpm, 152);
	assert.equal(parsed!.total_ascent_m, 250);
	assert.equal(parsed!.indoor, false);
});
