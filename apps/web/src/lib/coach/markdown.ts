// Markdown sanitiser for coach responses. Hoisted out of CoachChat.svelte
// so the DOMPurify hook is registered exactly once at module load,
// not on every Svelte HMR / re-mount (DOMPurify's hook registry is a
// module singleton — addHook calls accumulate without removeHook).
//
// The render path is intentionally narrow:
//   - marked → HTML with breaks + gfm enabled
//   - DOMPurify with an explicit ALLOWED_TAGS allowlist of formatting
//     elements marked emits (no class attribute — see below)
//   - afterSanitizeAttributes hook forces target=_blank +
//     rel="noopener noreferrer" on every <a> so an LLM-emitted link
//     can't reach back into window.opener
//
// `class` is NOT in ALLOWED_ATTR. Coach responses should not need to
// emit class-based styling; an LLM-controlled `<span class="modal-backdrop">`
// would otherwise pick up the global class and overlay the page (a
// clickjacking vector documented in the audit pass-2 report).

import { marked } from 'marked';
import DOMPurify from 'isomorphic-dompurify';

marked.setOptions({ breaks: true, gfm: true });

const COACH_ALLOWED_TAGS = [
	'a', 'b', 'blockquote', 'br', 'code', 'del', 'em', 'h1', 'h2', 'h3',
	'h4', 'h5', 'h6', 'hr', 'i', 'li', 'ol', 'p', 'pre', 's', 'span',
	'strong', 'sub', 'sup', 'table', 'tbody', 'td', 'th', 'thead', 'tr',
	'u', 'ul',
];
const COACH_ALLOWED_ATTR = ['href', 'lang', 'title'];

DOMPurify.addHook('afterSanitizeAttributes', (node) => {
	if (node.tagName === 'A') {
		node.setAttribute('target', '_blank');
		node.setAttribute('rel', 'noopener noreferrer');
	}
});

export function renderCoachMarkdown(content: string): string {
	const raw = marked.parse(content, { async: false }) as string;
	return DOMPurify.sanitize(raw, {
		ALLOWED_TAGS: COACH_ALLOWED_TAGS,
		ALLOWED_ATTR: COACH_ALLOWED_ATTR,
		ALLOW_DATA_ATTR: false,
	});
}
