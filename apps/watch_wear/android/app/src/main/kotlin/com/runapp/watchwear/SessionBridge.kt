package com.runapp.watchwear

import android.content.Context
import android.net.Uri
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await

/// Shape of the Supabase session the paired phone pushes over the Wearable
/// Data Layer at `/supabase_session`. The phone's `WearAuthBridge.push`
/// writes this with all six fields populated; the watch caches it to
/// DataStore so a cold-start while offline doesn't lose the session.
data class SessionPayload(
    val accessToken: String,
    val refreshToken: String,
    val userId: String,
    val baseUrl: String,
    val anonKey: String,
    val expiresAtMs: Long,
) {
    companion object {
        const val PATH = "/supabase_session"

        /// Grade a `/supabase_session` DataMap's fields into a payload, or
        /// refuse it.
        ///
        /// All five strings are load-bearing: without them the watch cannot
        /// authenticate one request. Coercing an absent field to `""` — which
        /// is what this did — produced a payload the ViewModel accepted:
        /// `sessionStore.save` OVERWROTE the encrypted cached session, which
        /// is the one credential a watch out of Bluetooth range still has,
        /// and `applySession` then set `authed = true`, hiding the sign-in
        /// affordance behind a session that can never succeed. A partial push
        /// destroyed working credentials and left no way back on the wrist.
        ///
        /// The phone's `WearAuthBridge.parseWearAuthPushArgs` refuses a
        /// half-formed push for exactly this reason, and its own comment says
        /// so — "rather than shipping a half-formed DataItem that the watch's
        /// SessionBridge would silently apply". That was the whole guard: a
        /// sender-side one. A receiver that trusts its sender has no contract,
        /// only a habit, and the phone's own presence-and-type check passes an
        /// EMPTY string through (`session.refreshToken ?? ''` in
        /// `wear_auth_bridge.dart` sends one).
        ///
        /// Refusing is not a sign-out: a malformed push must leave the session
        /// the watch already holds alone rather than tearing it down.
        /// `expiresAtMs` is deliberately not graded — 0 reads as NOT expired
        /// (`StoredSession.isExpired`), which is the documented contract.
        internal fun fromFields(
            accessToken: String?,
            refreshToken: String?,
            userId: String?,
            baseUrl: String?,
            anonKey: String?,
            expiresAtMs: Long,
        ): SessionPayload? {
            if (accessToken.isNullOrBlank()) return null
            if (refreshToken.isNullOrBlank()) return null
            if (userId.isNullOrBlank()) return null
            if (baseUrl.isNullOrBlank()) return null
            if (anonKey.isNullOrBlank()) return null
            return SessionPayload(
                accessToken = accessToken,
                refreshToken = refreshToken,
                userId = userId,
                baseUrl = baseUrl,
                anonKey = anonKey,
                expiresAtMs = expiresAtMs,
            )
        }

        fun fromDataMapOrNull(
            dm: com.google.android.gms.wearable.DataMap,
        ): SessionPayload? = fromFields(
            accessToken = dm.getString("access_token"),
            refreshToken = dm.getString("refresh_token"),
            userId = dm.getString("user_id"),
            baseUrl = dm.getString("base_url"),
            anonKey = dm.getString("anon_key"),
            expiresAtMs = dm.getLong("expires_at_ms"),
        )
    }
}

/// Discriminates between "phone pushed an updated session" and "phone
/// cleared the session (user signed out)". The latter case fires when
/// `WearAuthBridge.kt` on the phone side calls `deleteDataItems` —
/// without this distinction the watch would silently keep a stale
/// session and continue authing API calls as the signed-out user.
sealed class SessionEvent {
    data class Updated(val payload: SessionPayload) : SessionEvent()
    object Cleared : SessionEvent()
}

/// Bridge to the Wearable Data Layer. Exposes a `Flow<SessionEvent>` of
/// session pushes + clears from the paired phone plus a `current()`
/// one-shot read for cold-start recovery (the phone may have pushed a
/// session long before the watch app launched).
class SessionBridge(context: Context) {
    private val dataClient: DataClient = Wearable.getDataClient(context)

    val events: Flow<SessionEvent> = callbackFlow {
        val listener = DataClient.OnDataChangedListener { events ->
            for (event in events) {
                if (event.dataItem.uri.path != SessionPayload.PATH) continue
                when (event.type) {
                    DataEvent.TYPE_CHANGED -> {
                        val dm = DataMapItem.fromDataItem(event.dataItem).dataMap
                        // A push missing a load-bearing field is dropped, not
                        // applied and not treated as a sign-out — see
                        // `SessionPayload.fromFields`.
                        SessionPayload.fromDataMapOrNull(dm)?.let {
                            trySend(SessionEvent.Updated(it))
                        }
                    }
                    DataEvent.TYPE_DELETED -> {
                        // Phone-side `WearAuthBridge.clear` deleted the
                        // /supabase_session DataItem — user signed out
                        // on the phone, propagate to the watch.
                        trySend(SessionEvent.Cleared)
                    }
                }
            }
        }
        dataClient.addListener(listener)
        awaitClose { dataClient.removeListener(listener) }
    }

    suspend fun current(): SessionPayload? {
        val uri = Uri.Builder()
            .scheme("wear")
            .path(SessionPayload.PATH)
            .build()
        val buffer = dataClient.getDataItems(uri).await()
        return try {
            buffer.firstOrNull()?.let { item ->
                SessionPayload.fromDataMapOrNull(DataMapItem.fromDataItem(item).dataMap)
            }
        } finally {
            buffer.release()
        }
    }
}
