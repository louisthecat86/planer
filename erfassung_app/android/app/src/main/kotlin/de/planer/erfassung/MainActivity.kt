package de.planer.erfassung

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * „Öffnen mit": Tippt jemand im Dateimanager das Paket aus dem Planer an,
 * liest die Activity seinen Text und hält ihn bereit, bis die App ihn über
 * den Kanal abholt.
 */
class MainActivity : FlutterActivity() {
    private var kanal: MethodChannel? = null
    private var wartend: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        wartend = textAus(intent)
        val neu = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "planer_erfassung/datei")
        neu.setMethodCallHandler { call, result ->
            if (call.method == "geoeffneteDatei") {
                result.success(wartend)
                wartend = null
            } else {
                result.notImplemented()
            }
        }
        kanal = neu
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = textAus(intent) ?: return
        wartend = text
        kanal?.invokeMethod("dateiGeoeffnet", null)
    }

    /** Der Text der Datei, mit der die App geöffnet wurde. */
    private fun textAus(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return null
        val uri = intent.data ?: return null
        return try {
            contentResolver.openInputStream(uri)?.use { strom ->
                String(strom.readBytes(), Charsets.UTF_8)
            }
        } catch (e: Exception) {
            null
        }
    }
}
