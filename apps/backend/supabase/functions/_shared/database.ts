/// The generated row types, and the client type every Edge Function's
/// Supabase handle should carry.
///
/// This module holds the ONLY path in the functions tree that reaches out of
/// `apps/backend` — deliberately. `apps/web/src/lib/database.types.ts` is the
/// single committed output of `npm run gen:types`
/// (docs/architecture/schema_codegen.md) and CI's `gen:types:check` fails the
/// PR when it drifts from the migrations. A second copy generated into this
/// tree would need a second drift check and would rot between the two, so the
/// functions read that one file, through here and nowhere else: if the
/// generated file ever moves, exactly one line changes.
///
/// Nothing crosses the boundary at RUNTIME. Every re-export below is
/// `export type`, so the specifier is erased before the Supabase CLI bundles a
/// function and `database.types.ts` never enters a deployed module graph
/// (it carries a runtime `Constants` export that would otherwise be dragged in).
///
/// `?target=deno` on the supabase-js specifier is load-bearing, not cosmetic:
/// this module lands in `clip-public-track`'s graph, whose worker must boot
/// with no network — the default esm.sh build carries bare `node:` specifiers
/// that the runtime resolves from registry.npmjs.org (decisions § 699). Type-
/// only imports still count; `_shared/offline_worker_boot_guard.test.ts` pins
/// both files on the probe path.
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.110.0?target=deno';
import type { Database } from '../../../../web/src/lib/database.types.ts';

export type { Database };
export type { Json } from '../../../../web/src/lib/database.types.ts';

/// A Supabase client bound to this project's schema.
///
/// A service-role client and a user-scoped one are the SAME type: they differ
/// only in which key and which `Authorization` header they were built with,
/// and RLS is enforced by Postgres at request time, not by the type. What one
/// may read is a runtime fact about the caller, so nothing here can encode it
/// — which is why the two never need separate aliases, and why a parameter
/// typed `DbClient` still says nothing about privilege. Where that
/// distinction matters, the parameter name carries it (`service`, `admin`,
/// `userClient`), as it already did before these were typed at all.
export type DbClient = SupabaseClient<Database>;

/// One table's Row / Insert / Update shapes, for a handler that names the row
/// it is building before it hands it to `.insert()` / `.update()`.
export type Tables<T extends keyof Database['public']['Tables']> =
	Database['public']['Tables'][T]['Row'];
export type TablesInsert<T extends keyof Database['public']['Tables']> =
	Database['public']['Tables'][T]['Insert'];
export type TablesUpdate<T extends keyof Database['public']['Tables']> =
	Database['public']['Tables'][T]['Update'];
