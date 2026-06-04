package com.runapp.watchwear

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Pins the at-rest / backup posture for the Wear OS app.
///
/// The watch queues completed runs (track files on disk + DataStore
/// metadata), caches starred routes in DataStore, and stores the auth
/// session in EncryptedSharedPreferences. Android Auto-Backup would
/// otherwise sweep the unencrypted pieces into Google's cloud (and a
/// restored EncryptedSharedPreferences blob is undecryptable garbage on
/// the new device anyway, since its Keystore master key never leaves the
/// original watch). We opt the whole app out via android:allowBackup.
/// See decisions.md (at-rest / backup posture) + remediation plan 3c-b.
class BackupExclusionManifestTest {
    @Test
    fun `allowBackup is disabled in the manifest`() {
        val candidates = listOf(
            "src/main/AndroidManifest.xml",
            "app/src/main/AndroidManifest.xml",
            "apps/watch_wear/android/app/src/main/AndroidManifest.xml",
        )
        val manifest = candidates.map { File(it) }.firstOrNull { it.exists() }
        assertTrue(
            "Could not locate AndroidManifest.xml (cwd=${File(".").absolutePath})",
            manifest != null,
        )
        val body = manifest!!.readText()
        assertTrue(
            "AndroidManifest.xml must set android:allowBackup=\"false\" so the " +
                "watch's queued-run track files, DataStore run metadata, and the " +
                "EncryptedSharedPreferences session blob are never extracted via " +
                "Android Auto-Backup.",
            body.contains("android:allowBackup=\"false\""),
        )
    }
}
