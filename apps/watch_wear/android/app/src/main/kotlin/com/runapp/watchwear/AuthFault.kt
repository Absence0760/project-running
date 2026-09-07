package com.runapp.watchwear

import androidx.annotation.StringRes

/// Why the watch could not authenticate, as something the wrist can say in the
/// runner's own language.
///
/// The same defect § 1490 closed on the sync banner, one screen over and found
/// by looking for it: `authError` held `e.message ?: e.javaClass.simpleName`,
/// which for a failed sign-in is GoTrue's own English prose lifted out of the
/// error body, and for a failed token refresh was that prose interpolated into
/// a translated frame — so half the sentence was in the runner's language and
/// the half that carried the meaning was not (decisions § 1492).
///
/// The vocabulary is again the runner's next move. [InvalidCredentials] is
/// something they retype; [RateLimited] is something they wait out;
/// [SessionExpired] is a sign-in they have to do again through no fault of
/// their own, which is a different sentence from having typed the wrong
/// password.
enum class AuthFault {
    /// The email and password were not accepted. By far the common case, and
    /// the only one whose remedy is on the keyboard in front of them.
    InvalidCredentials,

    /// GoTrue is rate-limiting this watch. Waiting is the whole remedy;
    /// retyping the password makes it worse.
    RateLimited,

    /// The auth server answered 5xx.
    ServerBusy,

    /// The request never reached the auth server.
    Offline,

    /// A cached session could not be renewed. Distinct from
    /// [InvalidCredentials] because the runner typed nothing wrong: the
    /// refresh token is spent, revoked, or older than the server's window.
    SessionExpired,

    /// Something threw that none of the above describes.
    Unknown,
}

/// The half both endpoints answer the same way: everything that is not the
/// grant itself being refused.
private fun sharedAuthFault(e: Throwable): AuthFault? = when {
    e !is HttpException -> if (isTransientNetworkFailure(e)) AuthFault.Offline else null
    e.code == 429 -> AuthFault.RateLimited
    e.code in 500..599 -> AuthFault.ServerBusy
    else -> null
}

/// Classify a failure of the password grant.
///
/// A 4xx here is the credentials being refused — this endpoint has no token to
/// be stale, so [AuthFault.SessionExpired] is not reachable from it.
internal fun signInFaultFor(e: Throwable): AuthFault = sharedAuthFault(e)
    ?: if (e is HttpException && e.code in 400..499) {
        AuthFault.InvalidCredentials
    } else {
        AuthFault.Unknown
    }

/// Classify a failure of the refresh grant.
///
/// The same status codes mean something else here, which is why this is a
/// second entry point rather than one function with a flag: a 400 on the
/// password grant is a typo, and a 400 on the refresh grant is a session the
/// server will not renew. Telling a runner their password is wrong when they
/// have not typed one is worse than saying nothing.
internal fun refreshFaultFor(e: Throwable): AuthFault = sharedAuthFault(e)
    ?: if (e is HttpException && e.code in 400..499) {
        AuthFault.SessionExpired
    } else {
        AuthFault.Unknown
    }

/// The caption the sign-in surfaces render for a fault.
///
/// A `when` over the enum, so the compiler is what makes the mapping total.
@StringRes
fun authFaultMessage(fault: AuthFault): Int = when (fault) {
    AuthFault.InvalidCredentials -> R.string.auth_fault_credentials
    AuthFault.RateLimited -> R.string.auth_fault_rate_limited
    AuthFault.ServerBusy -> R.string.auth_fault_server
    AuthFault.Offline -> R.string.auth_fault_offline
    AuthFault.SessionExpired -> R.string.auth_fault_session_expired
    AuthFault.Unknown -> R.string.auth_fault_unknown
}
