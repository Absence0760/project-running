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

        fun fromDataMap(dm: com.google.android.gms.wearable.DataMap): SessionPayload {
            return SessionPayload(
                accessToken = dm.getString("access_token") ?: "",
                refreshToken = dm.getString("refresh_token") ?: "",
                userId = dm.getString("user_id") ?: "",
                baseUrl = dm.getString("base_url") ?: "",
                anonKey = dm.getString("anon_key") ?: "",
                expiresAtMs = dm.getLong("expires_at_ms"),
            )
        }
    }
}

/// Bridge to the Wearable Data Layer. Exposes a `Flow<SessionPayload>` of
/// session pushes from the paired phone plus a `current()` one-shot read
/// for cold-start recovery (the phone may have pushed a session long
/// before the watch app launched).
class SessionBridge(context: Context) {
    private val dataClient: DataClient = Wearable.getDataClient(context)

    val sessions: Flow<SessionPayload> = callbackFlow {
        val listener = DataClient.OnDataChangedListener { events ->
            for (event in events) {
                if (event.type != DataEvent.TYPE_CHANGED) continue
                if (event.dataItem.uri.path != SessionPayload.PATH) continue
                val dm = DataMapItem.fromDataItem(event.dataItem).dataMap
                trySend(SessionPayload.fromDataMap(dm))
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
                SessionPayload.fromDataMap(DataMapItem.fromDataItem(item).dataMap)
            }
        } finally {
            buffer.release()
        }
    }
}
