/// Pure helpers for the auth-email send-email hook: Standard Webhooks
/// signature verification, the localized auth-mail catalogue, the
/// per-action send plan (incl. the double-send secure email change),
/// verify-URL construction, and MIME assembly.
///
/// Keep this file pure — no `Deno.env`, no `serve`, no network — so the
/// whole rendering + verification surface is unit-testable in
/// milliseconds. The catalogue mirrors the Go worker's shape
/// (`apps/job_worker/internal/email_i18n.go`): per-locale maps of
/// {subject, preheader, heading, cta, body[]} over the same six app
/// locales, with English as the per-key fallback. The HTML/text layout
/// is a port of the worker's `renderHTMLBody` / `renderTextBody` so
/// auth mail is visually identical to product mail.

import { timingSafeEqual } from '../_shared/webhook_security.ts';

const BRAND_NAME = 'Threkir';
const BRAND_COLOR = '#2C5F6E';

// ─────────────────── Standard Webhooks verification ───────────────────

export type HookVerifyOutcome =
  | 'ok'
  | 'missing_headers'
  | 'bad_secret'
  | 'bad_timestamp'
  | 'stale'
  | 'bad_signature';

/// GoTrue signs send-email hook requests per the Standard Webhooks spec:
/// base64(HMAC-SHA256(key, `${webhook-id}.${webhook-timestamp}.${body}`))
/// where the key is the base64 payload of a `v1,whsec_<base64>` secret.
/// The signature header carries a space-separated list of `v1,<base64>`
/// entries (rotation window) — any one matching passes. Timestamp
/// freshness is bounded to ±5 minutes, the spec's recommended default:
/// a captured POST replayed later fails even though its HMAC is valid.
export async function verifySendEmailHook(
  rawBody: string,
  headers: {
    id: string | null;
    timestamp: string | null;
    signature: string | null;
  },
  secretConfig: string,
  nowMs: number,
  toleranceSec = 300,
): Promise<HookVerifyOutcome> {
  if (!headers.id || !headers.timestamp || !headers.signature) {
    return 'missing_headers';
  }
  const keys = parseHookSecrets(secretConfig);
  if (keys.length === 0) return 'bad_secret';

  const ts = Number.parseInt(headers.timestamp, 10);
  if (!Number.isFinite(ts)) return 'bad_timestamp';
  if (Math.abs(nowMs - ts * 1000) > toleranceSec * 1000) return 'stale';

  const signed = `${headers.id}.${headers.timestamp}.${rawBody}`;
  const candidates = headers.signature
    .split(' ')
    .map((s) => (s.startsWith('v1,') ? s.slice(3) : ''))
    .filter((s) => s.length > 0);
  if (candidates.length === 0) return 'bad_signature';

  for (const key of keys) {
    const expected = await hmacBase64(key, signed);
    for (const sig of candidates) {
      if (timingSafeEqual(sig, expected)) return 'ok';
    }
  }
  return 'bad_signature';
}

/// Accepts the config-file form `v1,whsec_<base64>` (multiple secrets
/// `|`-separated for rotation) and the bare `whsec_<base64>` the
/// dashboard shows. Anything that doesn't base64-decode is dropped —
/// an all-invalid secret config verifies nothing (fail closed).
export function parseHookSecrets(secretConfig: string): Uint8Array[] {
  const keys: Uint8Array[] = [];
  for (const raw of secretConfig.split('|')) {
    let s = raw.trim();
    if (s.startsWith('v1,')) s = s.slice(3);
    if (s.startsWith('whsec_')) s = s.slice(6);
    if (s.length === 0) continue;
    try {
      const bin = atob(s);
      const bytes = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      keys.push(bytes);
    } catch {
      continue;
    }
  }
  return keys;
}

async function hmacBase64(
  key: Uint8Array,
  content: string,
): Promise<string> {
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    new Uint8Array(key) as BufferSource,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'HMAC',
    cryptoKey,
    new TextEncoder().encode(content) as BufferSource,
  );
  let bin = '';
  for (const b of new Uint8Array(sig)) bin += String.fromCharCode(b);
  return btoa(bin);
}

/// Test-side counterpart of verifySendEmailHook: mint a valid signature
/// header value for a synthetic payload.
export async function signSendEmailHook(
  secretConfig: string,
  id: string,
  timestamp: string,
  rawBody: string,
): Promise<string> {
  const keys = parseHookSecrets(secretConfig);
  if (keys.length === 0) throw new Error('no usable hook secret');
  const sig = await hmacBase64(keys[0], `${id}.${timestamp}.${rawBody}`);
  return `v1,${sig}`;
}

// ─────────────────── locale ───────────────────

export const AUTH_EMAIL_LOCALES = ['en', 'de', 'fr', 'es', 'ja', 'pt-BR'] as const;

/// Mirror of the worker's normalizeEmailLocale: region variants collapse
/// to their base language (de-DE → de), Portuguese collapses to pt-BR
/// (the only pt we ship), everything unknown → en.
export function normalizeEmailLocale(tag: string | null | undefined): string {
  const t = (tag ?? '').trim().toLowerCase();
  if (t === '') return 'en';
  if (t.startsWith('pt')) return 'pt-BR';
  const sep = t.search(/[-_]/);
  const base = sep >= 0 ? t.slice(0, sep) : t;
  switch (base) {
    case 'en':
    case 'de':
    case 'fr':
    case 'es':
    case 'ja':
      return base;
    default:
      return 'en';
  }
}

/// The recipient's chosen app language (user_settings.prefs.locale,
/// decisions §120) wins; a brand-new signup has no settings row yet, so
/// the signup-time locale the clients stamp into user_metadata.locale is
/// the fallback; English is the floor.
export function resolveAuthEmailLocale(
  settingsLocale: string | null,
  metadataLocale: unknown,
): string {
  if (settingsLocale) return normalizeEmailLocale(settingsLocale);
  if (typeof metadataLocale === 'string' && metadataLocale.trim() !== '') {
    return normalizeEmailLocale(metadataLocale);
  }
  return 'en';
}

// ─────────────────── hook payload → send plan ───────────────────

export interface HookUser {
  id?: string;
  email?: string;
  new_email?: string;
  user_metadata?: Record<string, unknown> | null;
}

export interface HookEmailData {
  token?: string;
  token_hash?: string;
  token_new?: string;
  token_hash_new?: string;
  redirect_to?: string;
  email_action_type?: string;
  site_url?: string;
}

export interface PlannedSend {
  to: string;
  catalogueKey: string;
  verifyType: string | null;
  token: string;
  tokenHash: string;
}

/// Wire-safety gate for a hook-supplied recipient before it reaches the
/// MIME `To:` header and the SMTP `RCPT TO` command. GoTrue validates
/// email format at signup, but the hook is its own trust boundary
/// (anything holding the signing secret chooses the field), so header /
/// command injection is rejected here rather than assumed away: no
/// control characters (CR/LF folding), no angle brackets / comma /
/// semicolon / whitespace (RCPT and address-list delimiters), exactly
/// one @ with a non-empty local part and domain, RFC 5321 length cap.
export function isValidRecipient(addr: string): boolean {
  if (addr.length === 0 || addr.length > 254) return false;
  // deno-lint-ignore no-control-regex
  if (/[\x00-\x1f\x7f<>,;\s]/.test(addr)) return false;
  const at = addr.indexOf('@');
  return at > 0 && at === addr.lastIndexOf('@') && at < addr.length - 1;
}

const LINK_ACTIONS: Record<string, string> = {
  signup: 'signup',
  invite: 'invite',
  magiclink: 'magiclink',
  recovery: 'recovery',
  email: 'email',
};

/// One hook invocation can require up to two sends: a secure email
/// change (both token pairs present) confirms from BOTH addresses. Per
/// the documented (backwards-compatibility) field reversal, the mail to
/// the CURRENT address pairs `token` with `token_hash_new`, and the mail
/// to the NEW address pairs `token_new` with `token_hash`. Actions with
/// no verify link (reauthentication, the *_notification kinds, anything
/// future/unknown) fall through to code-only or informational sends —
/// an unknown action type must never fail the hook, or it would block
/// the auth flow that triggered it.
export function planSends(
  user: HookUser,
  emailData: HookEmailData,
): PlannedSend[] {
  const action = emailData.email_action_type ?? '';
  const email = user.email ?? '';

  if (action === 'email_change') {
    const newEmail = user.new_email ?? '';
    const secureChange = !!emailData.token_hash_new && !!newEmail && !!email;
    if (secureChange) {
      return [
        {
          to: email,
          catalogueKey: 'email_change_current',
          verifyType: 'email_change',
          token: emailData.token ?? '',
          tokenHash: emailData.token_hash_new ?? '',
        },
        {
          to: newEmail,
          catalogueKey: 'email_change',
          verifyType: 'email_change',
          token: emailData.token_new ?? '',
          tokenHash: emailData.token_hash ?? '',
        },
      ];
    }
    const to = newEmail || email;
    if (!to) return [];
    return [{
      to,
      catalogueKey: 'email_change',
      verifyType: 'email_change',
      token: emailData.token ?? '',
      tokenHash: emailData.token_hash ?? '',
    }];
  }

  if (!email) return [];

  if (action === 'reauthentication') {
    return [{
      to: email,
      catalogueKey: 'reauthentication',
      verifyType: null,
      token: emailData.token ?? '',
      tokenHash: '',
    }];
  }

  const verifyType = LINK_ACTIONS[action] ?? null;
  if (verifyType) {
    return [{
      to: email,
      catalogueKey: action === 'email' ? 'magiclink' : action,
      verifyType,
      token: emailData.token ?? '',
      tokenHash: emailData.token_hash ?? '',
    }];
  }

  return [{
    to: email,
    catalogueKey: action === 'password_changed_notification'
      ? 'password_changed_notification'
      : 'default',
    verifyType: null,
    token: '',
    tokenHash: '',
  }];
}

// ─────────────────── verify URL ───────────────────

/// GoTrue's own templates leave redirect_to unencoded unless it contains
/// `&`, `=` or `#` (see encodeRedirectURL in supabase/auth) — mirrored
/// here so the link shape is byte-compatible with what the default
/// mailer produced (the web e2e reset flow greps for the literal
/// `/auth/reset` in the link).
export function buildVerifyUrl(
  supabaseUrl: string,
  tokenHash: string,
  verifyType: string,
  redirectTo: string | undefined,
): string {
  const base = supabaseUrl.replace(/\/+$/, '');
  let url = `${base}/auth/v1/verify?token=${encodeURIComponent(tokenHash)}` +
    `&type=${encodeURIComponent(verifyType)}`;
  if (redirectTo) {
    const encoded = /[&=#]/.test(redirectTo)
      ? encodeURIComponent(redirectTo)
      : redirectTo;
    url += `&redirect_to=${encoded}`;
  }
  return url;
}

// ─────────────────── catalogue ───────────────────

export interface AuthEmailStrings {
  subject: string;
  preheader: string;
  heading: string;
  cta: string;
  body: string[];
}

interface AuthEmailShared {
  footer: string;
  altCode: string;
}

export const AUTH_EMAIL_KEYS = [
  'signup',
  'invite',
  'magiclink',
  'recovery',
  'email_change',
  'email_change_current',
  'reauthentication',
  'password_changed_notification',
  'default',
] as const;

export const authEmailShared: Record<string, AuthEmailShared> = {
  en: {
    footer: 'This is a service message about your Threkir account.',
    altCode: 'Alternatively, enter this code:',
  },
  de: {
    footer: 'Dies ist eine Service-Nachricht zu deinem Threkir-Konto.',
    altCode: 'Alternativ kannst du diesen Code eingeben:',
  },
  fr: {
    footer: 'Ceci est un message de service concernant votre compte Threkir.',
    altCode: 'Vous pouvez aussi saisir ce code :',
  },
  es: {
    footer: 'Este es un mensaje de servicio sobre tu cuenta de Threkir.',
    altCode: 'También puedes introducir este código:',
  },
  ja: {
    footer: 'これはThrekirアカウントに関するサービスメッセージです。',
    altCode: 'または、次のコードを入力してください:',
  },
  'pt-BR': {
    footer: 'Esta é uma mensagem de serviço sobre sua conta Threkir.',
    altCode: 'Ou digite este código:',
  },
};

export const authEmailCatalogue: Record<
  string,
  Record<string, AuthEmailStrings>
> = {
  en: {
    signup: {
      subject: 'Confirm your signup',
      preheader: 'Confirm your email address to finish creating your Threkir account.',
      heading: 'Confirm your signup',
      cta: 'Confirm your email',
      body: [
        'Follow the link below to confirm your email address and finish creating your Threkir account.',
        "If you didn't create this account, you can safely ignore this email.",
      ],
    },
    invite: {
      subject: 'You have been invited',
      preheader: 'Accept the invitation to create your Threkir account.',
      heading: 'You have been invited',
      cta: 'Accept the invitation',
      body: [
        'You have been invited to create an account on Threkir. Follow the link below to accept the invitation.',
      ],
    },
    magiclink: {
      subject: 'Your sign-in link',
      preheader: 'Follow the link to sign in to Threkir.',
      heading: 'Your magic link',
      cta: 'Sign in',
      body: [
        'Follow the link below to sign in to your Threkir account.',
        "If you didn't request this link, you can safely ignore this email.",
      ],
    },
    recovery: {
      subject: 'Reset your password',
      preheader: 'Follow the link to choose a new password.',
      heading: 'Reset your password',
      cta: 'Reset password',
      body: [
        'Follow the link below to reset the password for your Threkir account.',
        "If you didn't request a password reset, you can safely ignore this email.",
      ],
    },
    email_change: {
      subject: 'Confirm your new email',
      preheader: 'Confirm your new email address.',
      heading: 'Confirm your new email address',
      cta: 'Confirm new email',
      body: [
        'Follow the link below to confirm this address as the new email for your Threkir account.',
        "If you didn't request this change, you can safely ignore this email.",
      ],
    },
    email_change_current: {
      subject: 'Confirm your email change',
      preheader: 'Approve the email change on your account.',
      heading: 'Confirm your email change',
      cta: 'Approve the change',
      body: [
        'We received a request to change the email address on your Threkir account. Follow the link below to approve the change from this address.',
        "If you didn't request this change, you can safely ignore this email — nothing changes without your confirmation.",
      ],
    },
    reauthentication: {
      subject: 'Confirm reauthentication',
      preheader: 'Enter the code to confirm this action.',
      heading: "Confirm it's you",
      cta: '',
      body: [
        'Enter this code to confirm the action on your Threkir account:',
        "If this wasn't you, you can safely ignore this email.",
      ],
    },
    password_changed_notification: {
      subject: 'Your password was changed',
      preheader: 'The password on your account was just changed.',
      heading: 'Your password was changed',
      cta: '',
      body: [
        'The password for your Threkir account was just changed.',
        "If this was you, no action is needed. If it wasn't, reset your password from the sign-in page right away.",
      ],
    },
    default: {
      subject: 'A message about your account',
      preheader: 'A notice about your account.',
      heading: 'Account notice',
      cta: '',
      body: [
        "This message concerns your Threkir account. If you weren't expecting it, you can safely ignore it.",
      ],
    },
  },
  de: {
    signup: {
      subject: 'Bestätige deine Registrierung',
      preheader: 'Bestätige deine E-Mail-Adresse, um dein Threkir-Konto fertig einzurichten.',
      heading: 'Bestätige deine Registrierung',
      cta: 'E-Mail bestätigen',
      body: [
        'Folge dem Link unten, um deine E-Mail-Adresse zu bestätigen und dein Threkir-Konto fertig einzurichten.',
        'Wenn du dieses Konto nicht erstellt hast, kannst du diese E-Mail einfach ignorieren.',
      ],
    },
    invite: {
      subject: 'Du wurdest eingeladen',
      preheader: 'Nimm die Einladung an und erstelle dein Threkir-Konto.',
      heading: 'Du wurdest eingeladen',
      cta: 'Einladung annehmen',
      body: [
        'Du wurdest eingeladen, ein Konto bei Threkir zu erstellen. Folge dem Link unten, um die Einladung anzunehmen.',
      ],
    },
    magiclink: {
      subject: 'Dein Anmeldelink',
      preheader: 'Folge dem Link, um dich bei Threkir anzumelden.',
      heading: 'Dein Magic Link',
      cta: 'Anmelden',
      body: [
        'Folge dem Link unten, um dich bei deinem Threkir-Konto anzumelden.',
        'Wenn du diesen Link nicht angefordert hast, kannst du diese E-Mail einfach ignorieren.',
      ],
    },
    recovery: {
      subject: 'Setze dein Passwort zurück',
      preheader: 'Folge dem Link, um ein neues Passwort zu wählen.',
      heading: 'Setze dein Passwort zurück',
      cta: 'Passwort zurücksetzen',
      body: [
        'Folge dem Link unten, um das Passwort deines Threkir-Kontos zurückzusetzen.',
        'Wenn du keine Zurücksetzung angefordert hast, kannst du diese E-Mail einfach ignorieren.',
      ],
    },
    email_change: {
      subject: 'Bestätige deine neue E-Mail-Adresse',
      preheader: 'Bestätige deine neue E-Mail-Adresse.',
      heading: 'Bestätige deine neue E-Mail-Adresse',
      cta: 'Neue E-Mail bestätigen',
      body: [
        'Folge dem Link unten, um diese Adresse als neue E-Mail-Adresse deines Threkir-Kontos zu bestätigen.',
        'Wenn du diese Änderung nicht angefordert hast, kannst du diese E-Mail einfach ignorieren.',
      ],
    },
    email_change_current: {
      subject: 'Bestätige die Änderung deiner E-Mail-Adresse',
      preheader: 'Genehmige die Änderung deiner E-Mail-Adresse.',
      heading: 'Bestätige die Änderung deiner E-Mail-Adresse',
      cta: 'Änderung genehmigen',
      body: [
        'Wir haben eine Anfrage erhalten, die E-Mail-Adresse deines Threkir-Kontos zu ändern. Folge dem Link unten, um die Änderung von dieser Adresse aus zu genehmigen.',
        'Wenn du diese Änderung nicht angefordert hast, ignoriere diese E-Mail — ohne deine Bestätigung wird nichts geändert.',
      ],
    },
    reauthentication: {
      subject: 'Bestätige, dass du es bist',
      preheader: 'Gib den Code ein, um die Aktion zu bestätigen.',
      heading: 'Bestätige, dass du es bist',
      cta: '',
      body: [
        'Gib diesen Code ein, um die Aktion in deinem Threkir-Konto zu bestätigen:',
        'Wenn du das nicht warst, kannst du diese E-Mail einfach ignorieren.',
      ],
    },
    password_changed_notification: {
      subject: 'Dein Passwort wurde geändert',
      preheader: 'Das Passwort deines Kontos wurde geändert.',
      heading: 'Dein Passwort wurde geändert',
      cta: '',
      body: [
        'Das Passwort deines Threkir-Kontos wurde soeben geändert.',
        'Wenn du das warst, ist nichts weiter zu tun. Wenn nicht, setze dein Passwort umgehend über die Anmeldeseite zurück.',
      ],
    },
    default: {
      subject: 'Eine Nachricht zu deinem Konto',
      preheader: 'Ein Hinweis zu deinem Konto.',
      heading: 'Hinweis zu deinem Konto',
      cta: '',
      body: [
        'Diese Nachricht betrifft dein Threkir-Konto. Wenn du sie nicht erwartet hast, kannst du sie ignorieren.',
      ],
    },
  },
  fr: {
    signup: {
      subject: 'Confirmez votre inscription',
      preheader: 'Confirmez votre adresse e-mail pour finaliser la création de votre compte Threkir.',
      heading: 'Confirmez votre inscription',
      cta: 'Confirmer mon e-mail',
      body: [
        'Suivez le lien ci-dessous pour confirmer votre adresse e-mail et finaliser la création de votre compte Threkir.',
        "Si vous n'avez pas créé ce compte, vous pouvez ignorer cet e-mail.",
      ],
    },
    invite: {
      subject: 'Vous avez été invité',
      preheader: "Acceptez l'invitation pour créer votre compte Threkir.",
      heading: 'Vous avez été invité',
      cta: "Accepter l'invitation",
      body: [
        "Vous avez été invité à créer un compte sur Threkir. Suivez le lien ci-dessous pour accepter l'invitation.",
      ],
    },
    magiclink: {
      subject: 'Votre lien de connexion',
      preheader: 'Suivez le lien pour vous connecter à Threkir.',
      heading: 'Votre lien magique',
      cta: 'Se connecter',
      body: [
        'Suivez le lien ci-dessous pour vous connecter à votre compte Threkir.',
        "Si vous n'avez pas demandé ce lien, vous pouvez ignorer cet e-mail.",
      ],
    },
    recovery: {
      subject: 'Réinitialisez votre mot de passe',
      preheader: 'Suivez le lien pour choisir un nouveau mot de passe.',
      heading: 'Réinitialisez votre mot de passe',
      cta: 'Réinitialiser le mot de passe',
      body: [
        'Suivez le lien ci-dessous pour réinitialiser le mot de passe de votre compte Threkir.',
        "Si vous n'avez pas demandé de réinitialisation, vous pouvez ignorer cet e-mail.",
      ],
    },
    email_change: {
      subject: 'Confirmez votre nouvelle adresse e-mail',
      preheader: 'Confirmez votre nouvelle adresse e-mail.',
      heading: 'Confirmez votre nouvelle adresse e-mail',
      cta: 'Confirmer la nouvelle adresse',
      body: [
        'Suivez le lien ci-dessous pour confirmer cette adresse comme nouvelle adresse e-mail de votre compte Threkir.',
        "Si vous n'avez pas demandé ce changement, vous pouvez ignorer cet e-mail.",
      ],
    },
    email_change_current: {
      subject: "Confirmez le changement d'adresse e-mail",
      preheader: "Approuvez le changement d'adresse e-mail de votre compte.",
      heading: "Confirmez le changement d'adresse e-mail",
      cta: 'Approuver le changement',
      body: [
        "Nous avons reçu une demande de changement de l'adresse e-mail de votre compte Threkir. Suivez le lien ci-dessous pour approuver le changement depuis cette adresse.",
        "Si vous n'avez pas demandé ce changement, ignorez cet e-mail — rien ne sera modifié sans votre confirmation.",
      ],
    },
    reauthentication: {
      subject: "Confirmez que c'est bien vous",
      preheader: "Saisissez le code pour confirmer l'action.",
      heading: "Confirmez que c'est bien vous",
      cta: '',
      body: [
        "Saisissez ce code pour confirmer l'action sur votre compte Threkir :",
        "Si ce n'était pas vous, vous pouvez ignorer cet e-mail.",
      ],
    },
    password_changed_notification: {
      subject: 'Votre mot de passe a été modifié',
      preheader: 'Le mot de passe de votre compte a été modifié.',
      heading: 'Votre mot de passe a été modifié',
      cta: '',
      body: [
        "Le mot de passe de votre compte Threkir vient d'être modifié.",
        "Si c'était vous, aucune action n'est requise. Sinon, réinitialisez immédiatement votre mot de passe depuis la page de connexion.",
      ],
    },
    default: {
      subject: 'Un message concernant votre compte',
      preheader: 'Un avis concernant votre compte.',
      heading: 'Avis concernant votre compte',
      cta: '',
      body: [
        "Ce message concerne votre compte Threkir. Si vous ne l'attendiez pas, vous pouvez l'ignorer.",
      ],
    },
  },
  es: {
    signup: {
      subject: 'Confirma tu registro',
      preheader: 'Confirma tu dirección de correo para terminar de crear tu cuenta de Threkir.',
      heading: 'Confirma tu registro',
      cta: 'Confirmar mi correo',
      body: [
        'Sigue el enlace de abajo para confirmar tu dirección de correo y terminar de crear tu cuenta de Threkir.',
        'Si no creaste esta cuenta, puedes ignorar este correo.',
      ],
    },
    invite: {
      subject: 'Has recibido una invitación',
      preheader: 'Acepta la invitación para crear tu cuenta de Threkir.',
      heading: 'Has recibido una invitación',
      cta: 'Aceptar la invitación',
      body: [
        'Te han invitado a crear una cuenta en Threkir. Sigue el enlace de abajo para aceptar la invitación.',
      ],
    },
    magiclink: {
      subject: 'Tu enlace de inicio de sesión',
      preheader: 'Sigue el enlace para iniciar sesión en Threkir.',
      heading: 'Tu enlace mágico',
      cta: 'Iniciar sesión',
      body: [
        'Sigue el enlace de abajo para iniciar sesión en tu cuenta de Threkir.',
        'Si no solicitaste este enlace, puedes ignorar este correo.',
      ],
    },
    recovery: {
      subject: 'Restablece tu contraseña',
      preheader: 'Sigue el enlace para elegir una nueva contraseña.',
      heading: 'Restablece tu contraseña',
      cta: 'Restablecer contraseña',
      body: [
        'Sigue el enlace de abajo para restablecer la contraseña de tu cuenta de Threkir.',
        'Si no solicitaste restablecerla, puedes ignorar este correo.',
      ],
    },
    email_change: {
      subject: 'Confirma tu nuevo correo',
      preheader: 'Confirma tu nueva dirección de correo.',
      heading: 'Confirma tu nueva dirección de correo',
      cta: 'Confirmar nuevo correo',
      body: [
        'Sigue el enlace de abajo para confirmar esta dirección como el nuevo correo de tu cuenta de Threkir.',
        'Si no solicitaste este cambio, puedes ignorar este correo.',
      ],
    },
    email_change_current: {
      subject: 'Confirma el cambio de correo',
      preheader: 'Aprueba el cambio de correo de tu cuenta.',
      heading: 'Confirma el cambio de correo',
      cta: 'Aprobar el cambio',
      body: [
        'Recibimos una solicitud para cambiar el correo de tu cuenta de Threkir. Sigue el enlace de abajo para aprobar el cambio desde esta dirección.',
        'Si no solicitaste este cambio, ignora este correo: nada cambiará sin tu confirmación.',
      ],
    },
    reauthentication: {
      subject: 'Confirma que eres tú',
      preheader: 'Introduce el código para confirmar la acción.',
      heading: 'Confirma que eres tú',
      cta: '',
      body: [
        'Introduce este código para confirmar la acción en tu cuenta de Threkir:',
        'Si no fuiste tú, puedes ignorar este correo.',
      ],
    },
    password_changed_notification: {
      subject: 'Tu contraseña ha cambiado',
      preheader: 'La contraseña de tu cuenta ha cambiado.',
      heading: 'Tu contraseña ha cambiado',
      cta: '',
      body: [
        'La contraseña de tu cuenta de Threkir se acaba de cambiar.',
        'Si fuiste tú, no necesitas hacer nada. Si no, restablece tu contraseña de inmediato desde la página de inicio de sesión.',
      ],
    },
    default: {
      subject: 'Un mensaje sobre tu cuenta',
      preheader: 'Un aviso sobre tu cuenta.',
      heading: 'Aviso sobre tu cuenta',
      cta: '',
      body: [
        'Este mensaje es sobre tu cuenta de Threkir. Si no lo esperabas, puedes ignorarlo.',
      ],
    },
  },
  ja: {
    signup: {
      subject: '登録を確認してください',
      preheader: 'メールアドレスを確認して、Threkirアカウントの作成を完了してください。',
      heading: '登録の確認',
      cta: 'メールアドレスを確認',
      body: [
        '下のリンクからメールアドレスを確認し、Threkirアカウントの作成を完了してください。',
        'このアカウントに心当たりがない場合は、このメールを無視してください。',
      ],
    },
    invite: {
      subject: '招待が届いています',
      preheader: '招待を承認して、Threkirアカウントを作成してください。',
      heading: '招待が届いています',
      cta: '招待を承認',
      body: [
        'Threkirのアカウント作成に招待されました。下のリンクから招待を承認してください。',
      ],
    },
    magiclink: {
      subject: 'サインイン用リンク',
      preheader: 'リンクからThrekirにサインインしてください。',
      heading: 'マジックリンク',
      cta: 'サインイン',
      body: [
        '下のリンクから、Threkirアカウントにサインインしてください。',
        'このリンクをリクエストしていない場合は、このメールを無視してください。',
      ],
    },
    recovery: {
      subject: 'パスワードをリセット',
      preheader: 'リンクから新しいパスワードを設定してください。',
      heading: 'パスワードのリセット',
      cta: 'パスワードをリセット',
      body: [
        '下のリンクから、Threkirアカウントのパスワードをリセットしてください。',
        'リセットをリクエストしていない場合は、このメールを無視してください。',
      ],
    },
    email_change: {
      subject: '新しいメールアドレスの確認',
      preheader: '新しいメールアドレスを確認してください。',
      heading: '新しいメールアドレスの確認',
      cta: '新しいアドレスを確認',
      body: [
        '下のリンクから、このアドレスをThrekirアカウントの新しいメールアドレスとして確認してください。',
        'この変更に心当たりがない場合は、このメールを無視してください。',
      ],
    },
    email_change_current: {
      subject: 'メールアドレス変更の確認',
      preheader: 'メールアドレスの変更を承認してください。',
      heading: 'メールアドレス変更の確認',
      cta: '変更を承認',
      body: [
        'Threkirアカウントのメールアドレス変更のリクエストを受け付けました。下のリンクから、このアドレスで変更を承認してください。',
        'この変更に心当たりがない場合は、このメールを無視してください。確認がなければ変更は行われません。',
      ],
    },
    reauthentication: {
      subject: '本人確認',
      preheader: 'コードを入力して操作を確認してください。',
      heading: '本人確認',
      cta: '',
      body: [
        'Threkirアカウントでの操作を確認するには、次のコードを入力してください:',
        '心当たりがない場合は、このメールを無視してください。',
      ],
    },
    password_changed_notification: {
      subject: 'パスワードが変更されました',
      preheader: 'アカウントのパスワードが変更されました。',
      heading: 'パスワードが変更されました',
      cta: '',
      body: [
        'Threkirアカウントのパスワードが変更されました。',
        'ご自身による変更であれば、対応は不要です。心当たりがない場合は、すぐにサインインページからパスワードをリセットしてください。',
      ],
    },
    default: {
      subject: 'アカウントに関するお知らせ',
      preheader: 'アカウントに関するお知らせです。',
      heading: 'アカウントに関するお知らせ',
      cta: '',
      body: [
        'このメッセージはThrekirアカウントに関するものです。心当たりがない場合は無視してください。',
      ],
    },
  },
  'pt-BR': {
    signup: {
      subject: 'Confirme seu cadastro',
      preheader: 'Confirme seu endereço de e-mail para concluir a criação da sua conta Threkir.',
      heading: 'Confirme seu cadastro',
      cta: 'Confirmar meu e-mail',
      body: [
        'Siga o link abaixo para confirmar seu endereço de e-mail e concluir a criação da sua conta Threkir.',
        'Se você não criou esta conta, pode ignorar este e-mail.',
      ],
    },
    invite: {
      subject: 'Você foi convidado',
      preheader: 'Aceite o convite para criar sua conta Threkir.',
      heading: 'Você foi convidado',
      cta: 'Aceitar o convite',
      body: [
        'Você foi convidado a criar uma conta no Threkir. Siga o link abaixo para aceitar o convite.',
      ],
    },
    magiclink: {
      subject: 'Seu link de acesso',
      preheader: 'Siga o link para entrar no Threkir.',
      heading: 'Seu link mágico',
      cta: 'Entrar',
      body: [
        'Siga o link abaixo para entrar na sua conta Threkir.',
        'Se você não pediu este link, pode ignorar este e-mail.',
      ],
    },
    recovery: {
      subject: 'Redefina sua senha',
      preheader: 'Siga o link para escolher uma nova senha.',
      heading: 'Redefina sua senha',
      cta: 'Redefinir senha',
      body: [
        'Siga o link abaixo para redefinir a senha da sua conta Threkir.',
        'Se você não pediu a redefinição, pode ignorar este e-mail.',
      ],
    },
    email_change: {
      subject: 'Confirme seu novo e-mail',
      preheader: 'Confirme seu novo endereço de e-mail.',
      heading: 'Confirme seu novo endereço de e-mail',
      cta: 'Confirmar novo e-mail',
      body: [
        'Siga o link abaixo para confirmar este endereço como o novo e-mail da sua conta Threkir.',
        'Se você não pediu esta alteração, pode ignorar este e-mail.',
      ],
    },
    email_change_current: {
      subject: 'Confirme a alteração de e-mail',
      preheader: 'Aprove a alteração do e-mail da sua conta.',
      heading: 'Confirme a alteração de e-mail',
      cta: 'Aprovar a alteração',
      body: [
        'Recebemos um pedido para alterar o e-mail da sua conta Threkir. Siga o link abaixo para aprovar a alteração a partir deste endereço.',
        'Se você não pediu esta alteração, ignore este e-mail — nada será alterado sem a sua confirmação.',
      ],
    },
    reauthentication: {
      subject: 'Confirme que é você',
      preheader: 'Digite o código para confirmar a ação.',
      heading: 'Confirme que é você',
      cta: '',
      body: [
        'Digite este código para confirmar a ação na sua conta Threkir:',
        'Se não foi você, pode ignorar este e-mail.',
      ],
    },
    password_changed_notification: {
      subject: 'Sua senha foi alterada',
      preheader: 'A senha da sua conta foi alterada.',
      heading: 'Sua senha foi alterada',
      cta: '',
      body: [
        'A senha da sua conta Threkir acabou de ser alterada.',
        'Se foi você, nenhuma ação é necessária. Caso contrário, redefina sua senha imediatamente pela página de login.',
      ],
    },
    default: {
      subject: 'Uma mensagem sobre sua conta',
      preheader: 'Aviso sobre a sua conta.',
      heading: 'Aviso sobre sua conta',
      cta: '',
      body: [
        'Esta mensagem é sobre a sua conta Threkir. Se você não a esperava, pode ignorá-la.',
      ],
    },
  },
};

export function lookupAuthEmailStrings(
  locale: string,
  key: string,
): AuthEmailStrings {
  const loc = authEmailCatalogue[locale];
  if (loc && loc[key]) return loc[key];
  return authEmailCatalogue.en[key] ?? authEmailCatalogue.en.default;
}

// ─────────────────── render ───────────────────

export interface RenderedAuthEmail {
  subject: string;
  text: string;
  html: string;
}

function escapeHtml(s: string): string {
  return s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

/// Layout port of the worker's renderTextBody/renderHTMLBody: hidden
/// preheader, branded header bar, H1, paragraphs, bulletproof CTA
/// button, muted footer. The CTA verify link is the ONLY URL in the
/// message — the web e2e mail fixture extracts the first URL it finds,
/// so nothing may link before it. The OTP code, when present, renders
/// as its own spaced block below the paragraphs.
export function renderAuthEmail(
  locale: string,
  send: PlannedSend,
  opts: { supabaseUrl: string; redirectTo?: string },
): RenderedAuthEmail {
  const loc = normalizeEmailLocale(locale);
  const strings = lookupAuthEmailStrings(loc, send.catalogueKey);
  const shared = authEmailShared[loc] ?? authEmailShared.en;
  const link = send.verifyType && send.tokenHash
    ? buildVerifyUrl(opts.supabaseUrl, send.tokenHash, send.verifyType, opts.redirectTo)
    : '';
  const codeOnly = !link && send.token !== '';
  const altCode = link && send.token !== '' ? send.token : '';

  let text = strings.heading + '\n\n';
  for (const p of strings.body) text += p + '\n\n';
  if (codeOnly) text += send.token + '\n\n';
  if (link) text += `${strings.cta}: ${link}\n\n`;
  if (altCode) text += `${shared.altCode} ${altCode}\n\n`;
  text += '—\n' + shared.footer + '\n';

  let paras = '';
  for (const p of strings.body) {
    paras += `<p style="margin:0 0 16px;font-size:15px;line-height:1.6;color:#374151;">${escapeHtml(p)}</p>`;
  }
  if (codeOnly) {
    paras += `<p style="margin:8px 0 16px;font-size:26px;letter-spacing:6px;font-weight:700;color:#111827;">${escapeHtml(send.token)}</p>`;
  }
  let cta = '';
  if (link) {
    cta = `<table role="presentation" cellpadding="0" cellspacing="0" style="margin:8px 0 4px;"><tr>` +
      `<td bgcolor="${BRAND_COLOR}" style="border-radius:8px;">` +
      `<a href="${escapeHtml(link)}" style="display:inline-block;padding:12px 26px;font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;border-radius:8px;">${escapeHtml(strings.cta)}</a>` +
      `</td></tr></table>`;
    if (altCode) {
      cta += `<p style="margin:16px 0 0;font-size:13px;line-height:1.6;color:#6b7280;">${escapeHtml(shared.altCode)} <span style="font-weight:700;letter-spacing:2px;color:#374151;">${escapeHtml(altCode)}</span></p>`;
    }
  }

  const html = `<!DOCTYPE html>
<html lang="${loc}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="x-apple-disable-message-reformatting"></head>
<body style="margin:0;padding:0;background:#f4f5f7;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${escapeHtml(strings.preheader)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f5f7;"><tr><td align="center" style="padding:24px 12px;">
<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#ffffff;border-radius:12px;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
<tr><td style="background:${BRAND_COLOR};padding:20px 32px;"><span style="color:#ffffff;font-size:20px;font-weight:700;letter-spacing:0.5px;">${BRAND_NAME}</span></td></tr>
<tr><td style="padding:32px;"><h1 style="margin:0 0 16px;font-size:22px;line-height:1.3;color:#111827;">${escapeHtml(strings.heading)}</h1>${paras}${cta}</td></tr>
<tr><td style="padding:20px 32px;border-top:1px solid #e5e7eb;"><p style="margin:0;font-size:12px;line-height:1.5;color:#9ca3af;">${escapeHtml(shared.footer)}</p></td></tr>
</table></td></tr></table>
</body></html>`;

  return { subject: strings.subject, text, html };
}

// ─────────────────── MIME ───────────────────

/// RFC 2047 B-encode a header word when it carries non-ASCII (the
/// de/fr/es/ja/pt-BR subjects do). ASCII passes through untouched.
export function encodeHeaderWord(s: string): string {
  // deno-lint-ignore no-control-regex
  if (!/[^\x20-\x7e]/.test(s)) return s;
  const bytes = new TextEncoder().encode(s);
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return `=?UTF-8?B?${btoa(bin)}?=`;
}

function toCrlf(s: string): string {
  return s.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
}

/// Port of the worker's buildMIME: multipart/alternative, text part
/// first, CRLF line endings, fixed boundary (one message at a time —
/// randomness would only make tests flaky). 8bit CTE because the body
/// is raw UTF-8.
export function buildMime(
  from: string,
  to: string,
  msg: RenderedAuthEmail,
  nowIso: string,
): string {
  const boundary = 'threkir_auth_alt_x7k2';
  let b = '';
  b += `From: ${from}\r\n`;
  b += `To: ${to}\r\n`;
  b += `Subject: ${encodeHeaderWord(msg.subject)}\r\n`;
  b += `Date: ${nowIso}\r\n`;
  b += 'MIME-Version: 1.0\r\n';
  b += `Content-Type: multipart/alternative; boundary="${boundary}"\r\n\r\n`;
  b += `--${boundary}\r\n`;
  b += 'Content-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: 8bit\r\n\r\n';
  b += toCrlf(msg.text) + '\r\n';
  b += `--${boundary}\r\n`;
  b += 'Content-Type: text/html; charset=UTF-8\r\nContent-Transfer-Encoding: 8bit\r\n\r\n';
  b += toCrlf(msg.html) + '\r\n';
  b += `--${boundary}--\r\n`;
  return b;
}

/// Bare address out of an RFC 5322 "Name <addr>" for SMTP MAIL FROM.
export function extractAddr(from: string): string {
  const i = from.lastIndexOf('<');
  if (i >= 0) {
    const j = from.indexOf('>', i);
    if (j >= 0) return from.slice(i + 1, j);
  }
  return from.trim();
}
