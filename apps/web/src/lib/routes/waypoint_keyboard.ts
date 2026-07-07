// Keyboard operation of the route-builder waypoint list (WCAG 2.1.1):
// the map markers are mouse-only (drag to move, right-click to delete),
// so the sidebar renders a roving-tabindex list whose keydowns map to
// the same mutations. This module is the pure layer — key → action
// mapping and the metres → lat/lng nudge geodesy — kept rune-free so
// it is tsx-testable (waypoint_keyboard.test.ts).

export const NUDGE_STEP_M = 10;
export const NUDGE_STEP_LARGE_M = 100;

const METRES_PER_DEG_LAT = 111_320;

export type WaypointKeyAction =
	| { type: 'focus'; index: number }
	| { type: 'nudge'; dNorthM: number; dEastM: number }
	| { type: 'remove' }
	| { type: 'activate' };

// Map a keydown on a focused waypoint row to its action.
// - Arrow / Home / End rove focus through the list (tablist convention).
// - Alt+Arrow nudges the point geographically (Alt+Shift for the large
//   step) — Alt disambiguates "move in the list" from "move on the map".
// - Delete / Backspace removes the point.
// - Enter / Space pans the map to it.
// Returns null for anything else so Tab and typing pass through.
export function waypointKeyAction(
	input: { key: string; altKey: boolean; shiftKey: boolean },
	currentIndex: number,
	count: number,
): WaypointKeyAction | null {
	const { key, altKey, shiftKey } = input;
	if (altKey) {
		const step = shiftKey ? NUDGE_STEP_LARGE_M : NUDGE_STEP_M;
		switch (key) {
			case 'ArrowUp':
				return { type: 'nudge', dNorthM: step, dEastM: 0 };
			case 'ArrowDown':
				return { type: 'nudge', dNorthM: -step, dEastM: 0 };
			case 'ArrowRight':
				return { type: 'nudge', dNorthM: 0, dEastM: step };
			case 'ArrowLeft':
				return { type: 'nudge', dNorthM: 0, dEastM: -step };
			default:
				return null;
		}
	}
	switch (key) {
		case 'ArrowUp':
		case 'ArrowDown':
		case 'Home':
		case 'End': {
			if (count <= 0) return null;
			const next =
				key === 'Home'
					? 0
					: key === 'End'
						? count - 1
						: key === 'ArrowDown'
							? (currentIndex + 1) % count
							: (currentIndex - 1 + count) % count;
			return { type: 'focus', index: next };
		}
		case 'Delete':
		case 'Backspace':
			return { type: 'remove' };
		case 'Enter':
		case ' ':
			return { type: 'activate' };
		default:
			return null;
	}
}

// Offset a lat/lng by metres north / east. Longitude metres shrink by
// cos(lat); near the poles the cosine is clamped so a nudge stays a
// small, finite step instead of wrapping the globe. Latitude clamps to
// the web-mercator renderable band; longitude wraps across the
// antimeridian.
export function nudgeLatLng(
	point: { lat: number; lng: number },
	dNorthM: number,
	dEastM: number,
): { lat: number; lng: number } {
	const lat = Math.max(-85, Math.min(85, point.lat + dNorthM / METRES_PER_DEG_LAT));
	const cosLat = Math.max(0.01, Math.cos((point.lat * Math.PI) / 180));
	let lng = point.lng + dEastM / (METRES_PER_DEG_LAT * cosLat);
	if (lng > 180) lng -= 360;
	if (lng < -180) lng += 360;
	return { lat, lng };
}
