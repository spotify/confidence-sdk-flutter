package com.example.confidence_flutter_sdk

import android.content.Context
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
        confidence.flush()
      }
      "setup" -> {
        val apiKey = call.argument<String>("apiKey")!!
        val loggingLevel = call.argument<String>("loggingLevel")!!
        confidence = ConfidenceFactory.create(
          context,
          apiKey,
          loggingLevel = LoggingLevel.valueOf(loggingLevel)
        )
        result.success(null)
      }
      "fetchAndActivate" -> {
        coroutineScope.launch {
          confidence.fetchAndActivate()
          result.success(null)
        }
      }
      "activateAndFetchAsync" -> {
        coroutineScope.launch {
          confidence.activate()
          confidence.asyncFetch()
          result.success(null)
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
        val flags = readAllFlags()
        val map = flags.flags.associateBy({ it.flag }, { ConfidenceValue.Struct(it.value) })
        result.success(Json.encodeToString(NetworkConfidenceValueSerializer, ConfidenceValue.Struct(map)))
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
        confidence.track(eventName, data)
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
