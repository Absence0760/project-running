interface Toast {
	id: number;
	message: string;
	type: 'info' | 'error' | 'success';
}

let toasts = $state<Toast[]>([]);
let nextId = 0;

export function showToast(message: string, type: 'info' | 'error' | 'success' = 'info', durationMs = 4000) {
	const id = nextId++;
	toasts = [...toasts, { id, message, type }];
	setTimeout(() => {
		toasts = toasts.filter((t) => t.id !== id);
	}, durationMs);
}

export const toastStore = {
	get toasts() { return toasts; },
};
