/// Rasterise an SVG string to a PNG Blob via an offscreen canvas. Shared
/// by the client-rendered share artefacts (recap card, finisher
/// certificate) that are personal/private data with no public URL, so
/// they're drawn in the browser rather than served as an og:image.
///
/// Browser-only (uses Image + canvas). Rejects if the SVG fails to load
/// or the canvas has no 2D context.
export async function rasterizeSvgToPng(
	svg: string,
	width: number,
	height: number,
): Promise<Blob> {
	const url = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml' }));
	try {
		const img = new Image(width, height);
		await new Promise<void>((resolve, reject) => {
			img.onload = () => resolve();
			img.onerror = () => reject(new Error('svg failed to load'));
			img.src = url;
		});
		const canvas = document.createElement('canvas');
		canvas.width = width;
		canvas.height = height;
		const ctx = canvas.getContext('2d');
		if (!ctx) throw new Error('no 2d canvas context');
		ctx.drawImage(img, 0, 0, width, height);
		return await new Promise<Blob>((resolve, reject) => {
			canvas.toBlob(
				(b) => (b ? resolve(b) : reject(new Error('canvas.toBlob returned null'))),
				'image/png',
			);
		});
	} finally {
		URL.revokeObjectURL(url);
	}
}

/// Trigger a browser download of a Blob under `filename`.
export function downloadBlob(blob: Blob, filename: string): void {
	const url = URL.createObjectURL(blob);
	const a = document.createElement('a');
	a.href = url;
	a.download = filename;
	a.click();
	// Defer the revoke: revoking synchronously right after click() can abort
	// the download before the browser has resolved the blob URL (the resolution
	// is async), which manifests as a download that silently never starts.
	setTimeout(() => URL.revokeObjectURL(url), 10_000);
}
