const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// True when `value` is shaped like one of our row ids (a uuid).
///
/// Used by the id-resolution lookups behind `/events/[id]` and the `/clubs/
/// [slug]` id fallback: those receive a URL segment that may be a slug, and
/// filtering a uuid column by a non-uuid makes Postgres raise 22P02 rather
/// than return no rows — an error the `const { data }` destructure would then
/// swallow into an indistinguishable null.
export function isEntityId(value: string | null | undefined): boolean {
	return !!value && UUID_RE.test(value);
}
