package com.example.confidence_flutter_sdk

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.spotify.confidence.Confidence
import com.spotify.confidence.ConfidenceFactory
import com.spotify.confidence.ConfidenceValue
import com.spotify.confidence.LoggingLevel
import com.spotify.confidence.FlagResolution
import com.spotify.confidence.client.SdkMetadata
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

private const val TAG = "ConfidenceFlutterSdk"

/**
 * Replies to a [Result] exactly once, on the platform (main) thread.
 *
 * Flutter requires channel replies on the main thread, and a second reply
 * throws. The async cases in this plugin complete on [Dispatchers.IO], so
 * neither guarantee holds at the call site — both are enforced here.
 */
private class MainThreadResult(private val delegate: Result) {
  private val replied = AtomicBoolean(false)

  fun success(value: Any?) = replyOnce { delegate.success(value) }

  fun error(code: String, message: String?) = replyOnce { delegate.error(code, message, null) }

  private fun replyOnce(reply: () -> Unit) {
    if (!replied.compareAndSet(false, true)) return
    if (Looper.myLooper() == Looper.getMainLooper()) {
      reply()
    } else {
      Handler(Looper.getMainLooper()).post(reply)
    }
  }
}

/** ConfidenceFlutterSdkPlugin */
class ConfidenceFlutterSdkPlugin: FlutterPlugin, MethodCallHandler, ActivityAware {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel
  private lateinit var confidence: Confidence
  private val coroutineScope = CoroutineScope(Dispatchers.IO)
  private lateinit var context: Context

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "confidence_flutter_sdk")
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when(call.method) {
      "flush" -> {
        try {
          confidence.flush()
          result.success(null)
        } catch (e: Exception) {
          result.error("FLUSH_FAILED", "Failed to flush: ${e.message}", null)
        }
      }
      "setup" -> {
        val apiKey = call.argument<String>("apiKey")!!
        val loggingLevel = call.argument<String>("loggingLevel")!!
        val resolveBaseUrl = call.argument<String>("resolveBaseUrl")
        val resolvedLoggingLevel = LoggingLevel.valueOf(loggingLevel)
        confidence = if (resolveBaseUrl.isNullOrBlank()) {
          ConfidenceFactory.create(
            context,
            apiKey,
            loggingLevel = resolvedLoggingLevel
          )
        } else {
          ConfidenceFactory.create(
            context,
            apiKey,
            resolveBaseUrl = resolveBaseUrl,
            loggingLevel = resolvedLoggingLevel
          )
        }
        result.success(null)
      }
      "fetchAndActivate" -> {
        val reply = MainThreadResult(result)
        coroutineScope.launch {
          try {
            confidence.fetchAndActivate()
            reply.success(null)
          } catch (e: Throwable) {
            Log.e(TAG, "fetchAndActivate failed", e)
            reply.error("FETCH_AND_ACTIVATE_FAILED", e.message)
          }
        }
      }
      "activateAndFetchAsync" -> {
        val reply = MainThreadResult(result)
        coroutineScope.launch {
          try {
            confidence.activate()
            confidence.asyncFetch()
            reply.success(null)
          } catch (e: Throwable) {
            Log.e(TAG, "activateAndFetchAsync failed", e)
            reply.error("ACTIVATE_AND_FETCH_ASYNC_FAILED", e.message)
          }
        }
      }
      "isStorageEmpty" -> {
        val isEmpty = confidence.isStorageEmpty()
        result.success(isEmpty)
      }
      "getString" -> {
        val key = call.argument<String>("key")!!
        val defaultValue = call.argument<String>("defaultValue")
        val value = confidence.getValue(key, defaultValue)
        result.success(value)
      }
      "getDouble" -> {
        val key = call.argument<String>("key")!!
        val defaultValue = call.argument<Double>("defaultValue")
        val value = confidence.getValue(key, defaultValue)
        result.success(value)
      }
      "getBool" -> {
        val key = call.argument<String>("key")!!
        val defaultValue = call.argument<Boolean>("defaultValue")
        val value = confidence.getValue(key, defaultValue)
        result.success(value)
      }
      "getInt" -> {
        val key = call.argument<String>("key")!!
        val defaultValue = call.argument<Int>("defaultValue")
        val value = confidence.getValue(key, defaultValue)
        result.success(value)
      }
      "getObject" -> {
        val key = call.argument<String>("key")!!
        val wrappedDefaultValue = call.argument<Map<String, Map<String, Any>>>("defaultValue")!!
        val defaultValue: ConfidenceValue.Struct = ConfidenceValue.Struct(wrappedDefaultValue.mapValues { (_, value) -> value.convert() })
        val value = confidence.getValue(key, defaultValue)
        result.success(Json.encodeToString(NetworkConfidenceValueSerializer, value))
      }
      "readAllFlags" -> {
        val reply = MainThreadResult(result)
        coroutineScope.launch {
          try {
            val flags = readAllFlags()
            val map = flags.flags.associateBy({ it.flag }, { ConfidenceValue.Struct(it.value) })
            reply.success(Json.encodeToString(NetworkConfidenceValueSerializer, ConfidenceValue.Struct(map)))
          } catch (e: Throwable) {
            // A corrupt or partially written cache file makes decoding throw;
            // without a reply the Dart future would never complete.
            Log.e(TAG, "readAllFlags failed", e)
            reply.error("READ_ALL_FLAGS_FAILED", e.message)
          }
        }
      }
      "putContext" -> {
        val key = call.argument<String>("key")!!
        val value = call.argument<Map<String, Any>>("value")!!.convert()
        confidence.putContext(key, value)
        result.success(null)
      }
      "putAllContext" -> {
        val wrappedContext = call.argument<Map<String, Map<String, Any>>>("context")!!
        val context: Map<String, ConfidenceValue> = wrappedContext.mapValues { (_, value) -> value.convert() }
        confidence.putContext(context)
        result.success(null)
      }
      "track" -> {
        val eventName = call.argument<String>("eventName")!!
        val wrappedData = call.argument<Map<String, Map<String, Any>>>("data")!!
        val data: Map<String, ConfidenceValue> = wrappedData.mapValues { (_, value) -> value.convert() }
        try {
          confidence.track(eventName, data)
          result.success(null)
        } catch (e: Exception) {
          result.error("TRACK_FAILED", "Failed to track event '$eventName': ${e.message}", null)
        }
      }
      else -> result.notImplemented()
    }
  }

  private fun readAllFlags(): FlagResolution {
    val flagsFile = File(context.filesDir, "confidence_flags_cache.json")
    if (!flagsFile.exists()) return FlagResolution.EMPTY
    val fileText: String = flagsFile.bufferedReader().use { it.readText() }
    return if (fileText.isEmpty()) {
      FlagResolution.EMPTY
    } else {
      Json.decodeFromString(fileText)
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    context = binding.activity.applicationContext
  }

  override fun onDetachedFromActivityForConfigChanges() {

  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {

  }

  override fun onDetachedFromActivity() {

  }
}

private fun Map<String, Any>.convert(): ConfidenceValue {
  when(val type = this["type"] as String) {
    "string" -> return ConfidenceValue.String(this["value"] as String)
    "double" -> return ConfidenceValue.Double(this["value"] as Double)
    "bool" -> return ConfidenceValue.Boolean(this["value"] as Boolean)
    "int" -> return ConfidenceValue.Integer(this["value"] as Int)
    // Dart could not map this type (a DateTime, a null, a custom object) and
    // has already sent `value.toString()`. Keep that string rather than
    // throwing: `track` is fire-and-forget from Dart, so an exception here
    // would surface only as a logged handler error while the event is lost.
    "unknown" -> return ConfidenceValue.String(this["value"]?.toString() ?: "")
    "list" -> {
      val list = (this["value"] as List<Map<String, Any>>).map { it.convert() }
      return ConfidenceValue.List(list)
    }
    "map" -> {
      val objectValue = this["value"] as Map<String, Any>
      val map = mutableMapOf<String, ConfidenceValue>()
      for((key, value) in objectValue) {
        map[key] = (value as Map<String, Any>).convert()
      }
      return ConfidenceValue.Struct(map)
    }

    else -> throw IllegalArgumentException("Unknown type $type")
  }
}
