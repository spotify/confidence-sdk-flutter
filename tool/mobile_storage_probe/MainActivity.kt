package dev.confidence.probe.storage_probe

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// Test harness only: writes sentinel data using the same Android APIs as the
// pinned SDK. This channel is never used by the provider.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "confidence.storage-probe")
            .setMethodCallHandler { call, result ->
                val flags = File(filesDir, "confidence_flags_cache.json")
                val apply = File(filesDir, "confidence_apply_cache.json")
                val events = getDir("events", Context.MODE_PRIVATE)
                val prefs = getSharedPreferences("confidence-visitor", Context.MODE_PRIVATE)
                when (call.method) {
                    "seed" -> {
                        flags.writeText("legacy-flags")
                        apply.writeText("legacy-apply")
                        File(events, "batch.ready").writeText("sealed-event")
                        File(events, "unfinished").writeText("unfinished-event")
                        prefs.edit().putString("visitorId", "native-visitor").commit()
                        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                            .edit().putString("flutter.visitorId", "wrong-visitor").commit()
                        result.success(mapOf(
                            "flags" to flags.canonicalPath,
                            "apply" to apply.canonicalPath,
                            "events" to events.canonicalPath
                        ))
                    }
                    "changeIdentity" -> {
                        prefs.edit().putString("visitorId", "updated-native-visitor").commit()
                        result.success(null)
                    }
                    "removeIdentity" -> {
                        prefs.edit().remove("visitorId").commit()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
