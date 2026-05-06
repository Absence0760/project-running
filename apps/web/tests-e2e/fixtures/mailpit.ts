/**
 * Local Supabase ships an embedded Mailpit instance on
 * http://localhost:54324 (config.toml inbucket section). Auth flows
 * that send email — sign-up confirmations, password recovery, magic
 * links — deliver into Mailpit instead of a real SMTP relay. These
 * helpers give Playwright specs a way to read those mails without
 * hard-coding the API shape across multiple files.
 *
 * The Mailpit JSON API documented at https://mailpit.axllent.org/docs/
 * is stable; the only quirk worth noting is that DELETE /api/v1/messages
 * with no query clears ALL messages — call it in `beforeEach` for tests
 * that expect a specific just-sent email so accumulated mail from
 * other test runs doesn't shadow it.
 */

const BASE = 'http://localhost:54324';

interface MailpitListItem {
	ID: string;
	From: { Address: string; Name: string };
	To: { Address: string; Name: string }[];
	Subject: string;
	Created: string;
}

interface MailpitMessage {
	ID: string;
	From: { Address: string; Name: string };
	To: { Address: string; Name: string }[];
	Subject: string;
	HTML: string;
	Text: string;
}

export async function clearMailpit(): Promise<void> {
	const res = await fetch(`${BASE}/api/v1/messages`, { method: 'DELETE' });
	if (!res.ok) throw new Error(`mailpit clear failed: ${res.status}`);
}

export async function waitForEmail(opts: {
	to: string;
	subjectIncludes?: string;
	timeoutMs?: number;
}): Promise<MailpitMessage> {
	const deadline = Date.now() + (opts.timeoutMs ?? 10_000);
	while (Date.now() < deadline) {
		const res = await fetch(`${BASE}/api/v1/messages`);
		if (res.ok) {
			const list = (await res.json()) as { messages: MailpitListItem[] };
			const match = list.messages.find(
				(m) =>
					m.To.some((t) => t.Address.toLowerCase() === opts.to.toLowerCase()) &&
					(!opts.subjectIncludes || m.Subject.includes(opts.subjectIncludes))
			);
			if (match) {
				const detail = await fetch(`${BASE}/api/v1/message/${match.ID}`);
				if (detail.ok) {
					return (await detail.json()) as MailpitMessage;
				}
			}
		}
		await new Promise((r) => setTimeout(r, 200));
	}
	throw new Error(
		`mailpit waitForEmail timed out after ${opts.timeoutMs ?? 10_000}ms ` +
			`(to=${opts.to}, subject~${opts.subjectIncludes ?? '*'})`
	);
}

/**
 * Pulls the first http(s) URL out of a Mailpit message. Supabase
 * recovery / magic-link / signup-confirmation emails embed the action
 * URL as the only link, so a naive first-match is reliable.
 */
export function extractLink(msg: MailpitMessage): string {
	const source = msg.HTML || msg.Text;
	// Match an absolute URL up to the first quote / whitespace / closing
	// angle bracket. The URL may contain &amp; in HTML; decode it.
	const match = source.match(/https?:\/\/[^\s"'<>]+/);
	if (!match) throw new Error('mailpit extractLink: no URL found in message');
	return match[0].replace(/&amp;/g, '&');
}
