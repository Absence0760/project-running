import { en } from './locales/en';

// The catalogue shape: every locale module is `... satisfies Messages`,
// so a missing or extra key is a compile error. Values are plain strings
// (en is declared without `as const`, so the inferred value type is
// `string`, not a literal) — translations are free to differ.
export type Messages = typeof en;
export type MessageKey = keyof Messages;
