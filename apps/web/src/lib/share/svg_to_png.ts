/// Rasterise an SVG string to a PNG blob via an offscreen canvas.
/// The recap card is personal data rendered in the viewer's own browser
/// (never served as an og:image for the in-app share path), so it is
/// converted client-side before being handed to the OS share sheet or a
/// download. Shared by the year + month recap pages.
export async function svgToPngBlob(svg: string, size: number): Promise<Blob> {
	const url = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml' }));
	try {
		const img = new Image(size, size);
		await new Promise<void>((resolve, reject) => {
			img.onload = () => resolve();
			img.onerror = () => reject(new Error('recap card svg failed to load'));
			img.src = url;
		});
		const canvas = document.createElement('canvas');
		canvas.width = size;
		canvas.height = size;
		const ctx = canvas.getContext('2d');
		if (!ctx) throw new Error('no 2d canvas context');
		ctx.drawImage(img, 0, 0, size, size);
		return await new Promise<Blob>((resolve, reject) => {
			canvas.toBlob(
				(b) => (b ? resolve(b) : reject(new Error('canvas.toBlob returned null'))),
				'image/png'
			);
		});
	} finally {
		URL.revokeObjectURL(url);
	}
}
