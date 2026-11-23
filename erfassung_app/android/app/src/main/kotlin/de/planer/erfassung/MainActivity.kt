package de.planer.erfassung

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * „Öffnen mit": Tippt jemand im Dateimanager das Paket aus dem Planer an,
 * liest die Activity seinen Text und hält ihn bereit, bis die App ihn über
 * den Kanal abholt.
 *
 * „Per E-Mail": öffnet die E-Mail-App mit dem Ergebnis als Anhang.
 */
class MainActivity : FlutterActivity() {
    private var kanal: MethodChannel? = null
    private var wartend: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        wartend = textAus(intent)
        val neu = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "planer_erfassung/datei")
        neu.setMethodCallHandler { call, result ->
            when (call.method) {
                "geoeffneteDatei" -> {
                    result.success(wartend)
                    wartend = null
                }
                "perMail" -> result.success(
                    perMail(
                        call.argument<String>("pfad") ?: "",
                        call.argument<String>("an") ?: "",
                        call.argument<String>("betreff") ?: "",
                        call.argument<String>("text") ?: "",
                    ),
                )
                else -> result.notImplemented()
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

    /**
     * Öffnet die E-Mail-App mit Empfänger, Betreff, Text und der Datei
     * [pfad] als Anhang. Der Selector „mailto:" sorgt dafür, dass nur
     * E-Mail-Apps zur Wahl stehen, nicht Messenger. Die Datei liegt im
     * Zwischenspeicher; die E-Mail-App darf sie über den FileProvider lesen.
     */
    private fun perMail(pfad: String, an: String, betreff: String, text: String): String {
        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.dateien", File(pfad))
            val senden = Intent(Intent.ACTION_SEND).apply {
                type = "application/json"
                putExtra(Intent.EXTRA_EMAIL, arrayOf(an))
                putExtra(Intent.EXTRA_SUBJECT, betreff)
                putExtra(Intent.EXTRA_TEXT, text)
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newRawUri(betreff, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                selector = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:"))
            }
            try {
                startActivity(senden)
            } catch (e: ActivityNotFoundException) {
                // Manche E-Mail-Apps melden sich nicht für „mailto:" —
                // dann ohne Selector, mit der Auswahl von Android.
                senden.selector = null
                startActivity(Intent.createChooser(senden, betreff))
            }
            "ok"
        } catch (e: ActivityNotFoundException) {
            "keineApp"
        } catch (e: Exception) {
            "fehler"
        }
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
