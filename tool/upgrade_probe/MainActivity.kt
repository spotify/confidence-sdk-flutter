package dev.confidence.probe.upgrade_probe

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "confidence.upgrade-probe")
            .setMethodCallHandler { call, result ->
                val flags = File(filesDir, "confidence_flags_cache.json")
                val apply = File(filesDir, "confidence_apply_cache.json")
                val events = getDir("events", Context.MODE_PRIVATE)
                val prefs = getSharedPreferences("confidence-visitor", Context.MODE_PRIVATE)
                when (call.method) {
                    "seed" -> {
                        flags.writeText(call.argument<String>("flags")!!)
                        apply.writeText(call.argument<String>("apply")!!)
                        File(events, "batch.ready").writeText(call.argument<String>("sealed")!!)
                        File(events, "unfinished").writeText(call.argument<String>("unfinished")!!)
                        prefs.edit().putString("visitorId", "fixture-visitor").commit()
                        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                            .edit().putString("flutter.visitorId", "wrong-visitor").commit()
                        result.success(mapOf(
                            "flags" to flags.canonicalPath,
                            "apply" to apply.canonicalPath,
                            "events" to events.canonicalPath
                        ))
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
