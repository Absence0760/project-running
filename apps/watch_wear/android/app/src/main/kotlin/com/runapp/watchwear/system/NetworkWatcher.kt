package com.runapp.watchwear.system

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.distinctUntilChanged

/// Emits the current "do we have any usable internet" boolean. The
/// ViewModel collects this and triggers `drainQueue()` whenever the
/// edge transitions to `true` — so a run recorded on a flaky cellular
/// connection uploads as soon as WiFi comes back on the watch.
class NetworkWatcher(private val context: Context) {
    fun availability(): Flow<Boolean> = callbackFlow {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        if (cm == null) {
            trySend(true) // unknown — assume online
            awaitClose { }
            return@callbackFlow
        }
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { trySend(true) }
            override fun onLost(network: Network) { trySend(currentlyAvailable(cm)) }
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                trySend(caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET))
            }
        }
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        // Wrap in try/catch — `ACCESS_NETWORK_STATE` is declared in the
        // manifest, but if a future build strips it (or an OEM revokes
        // it) we'd crash on every launch otherwise.
        var registered = false
        try {
            cm.registerNetworkCallback(request, callback)
            registered = true
            trySend(currentlyAvailable(cm))
        } catch (_: SecurityException) {
            trySend(true)
        }
        awaitClose {
            if (registered) {
                runCatching { cm.unregisterNetworkCallback(callback) }
            }
        }
    }.distinctUntilChanged()

    private fun currentlyAvailable(cm: ConnectivityManager): Boolean {
        val active = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(active) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }
}
