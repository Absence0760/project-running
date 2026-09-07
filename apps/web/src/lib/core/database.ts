/// The schema the app's Supabase clients are typed against.
///
/// `database.types.ts` is generated and committed, and CI's `gen:types:check`
/// compares it byte-for-byte with a fresh generator run — so it cannot be
/// hand-corrected. This module states the one correction the generator's
/// output needs, once, and both clients take it.
///
/// `supabase gen types` emits every function parameter as its bare postgres
/// type and records only whether the parameter carries a SQL default, as a `?`.
/// It carries no nullability at all: `mark_attendance(p_attendance text)` — a
/// parameter whose own body branches on `p_attendance is not null` — is emitted
/// as `p_attendance: string`, and `search_public_routes(p_query text default
/// null)` as `p_query?: string`. Every caller that means NULL therefore fails
/// to compile against the generated shape.
///
/// Saying `null` explicitly is the behaviour we want to keep: omitting the key
/// asks PostgREST for whatever default the migration happens to carry today, so
/// a later `default ''` would silently change what the client requests. So the
/// widening goes here rather than into 26 call-site casts — a cast would
/// disable the checks that are the whole point of a typed client (the function
/// name, the argument key set, the return type), and would have to be repeated
/// and re-justified at every site.
import type { Database } from '../database.types';

/// `A extends never` is the distributive-conditional idiom, not a tautology:
/// a zero-argument function is generated as `Args: never`, and mapping over
/// `keyof never` would otherwise produce an index signature. The naked type
/// parameter distributes, so `never` maps to `never` and every real argument
/// object maps field-by-field.
type NullableArgs<A> = A extends never ? A : { [K in keyof A]: A[K] | null };

type WithNullableArgs<Functions> = {
	[N in keyof Functions]: Functions[N] extends { Args: infer A }
		? Omit<Functions[N], 'Args'> & { Args: NullableArgs<A> }
		: Functions[N];
};

export type AppDatabase = Omit<Database, 'public'> & {
	public: Omit<Database['public'], 'Functions'> & {
		Functions: WithNullableArgs<Database['public']['Functions']>;
	};
};

/// The generated write shapes for one table.
///
/// A patch assembled key-by-key used to be declared `Record<string, unknown>`,
/// which accepts a misspelled column and a value of the wrong postgres type
/// alike — both of which reach the server as a PostgREST 400 with nothing on
/// the client having objected. Naming the table instead checks the object the
/// query will actually send, which is the whole reason the client carries the
/// generated schema at all.
export type Insertable<T extends keyof Database['public']['Tables']> =
	Database['public']['Tables'][T]['Insert'];
export type Updatable<T extends keyof Database['public']['Tables']> =
	Database['public']['Tables'][T]['Update'];

/// The PostgREST select-list separator. A select list is comma-separated; the
/// space is cosmetic and matches the hand-written literals this replaced.
export const SELECT_SEPARATOR = ', ';

/// A tuple of column names as the string a `.select()` takes.
///
/// `Array.prototype.join` is declared to return `string`, and a `string` is
/// what makes supabase-js's select-list parser give up: it answers
/// `GenericStringError`, every property read off the row is an error, and the
/// row degrades to something no consumer can be checked against. The typed
/// client is only as good as the literal it is handed, so a select list built
/// from a tuple is re-stated as the literal that tuple spells.
export type Join<T extends readonly string[], D extends string> = T extends readonly []
	? ''
	: T extends readonly [infer Head extends string]
		? Head
		: T extends readonly [infer Head extends string, ...infer Rest extends readonly string[]]
			? `${Head}${D}${Join<Rest, D>}`
			: string;
