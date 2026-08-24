package com.example.actent

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Application configuration and outbound Work integration.
///
/// Dartloom's external-input plugin receives incoming shared content.
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "actent/android_share"
        private const val DEVICE_CHANNEL = "actent/device"
        private const val FILE_PROVIDER_SUFFIX = ".fileprovider"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handleMethod(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "displayName") result.success(Build.MODEL)
                else result.notImplemented()
            }
    }

    private fun handleMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createContentUri" -> createContentUri(call, result)
            "launchIntent" -> launchIntent(call, result)
            "queryIntentHandlers" -> queryIntentHandlers(call, result)
            else -> result.notImplemented()
        }
    }

    private fun createContentUri(call: MethodCall, result: MethodChannel.Result) {
        val handle = call.argument<String>("handle")
        if (handle == null) {
            result.error("invalid_handle", "Missing attachment handle", null)
            return
        }
        try {
            val file = File(handle).canonicalFile
            val root = File(filesDir, "actent/attachments").canonicalFile
            if (!file.path.startsWith(root.path + File.separator) || !file.exists()) {
                result.error("invalid_handle", "Attachment is not private to Actent", null)
                return
            }
            val uri = FileProvider.getUriForFile(
                this,
                packageName + FILE_PROVIDER_SUFFIX,
                file,
            )
            result.success(uri.toString())
        } catch (error: Exception) {
            result.error("file_provider_error", error.message, null)
        }
    }

    private fun queryIntentHandlers(call: MethodCall, result: MethodChannel.Result) {
        val intent = Intent(call.argument<String>("action") ?: Intent.ACTION_SEND)
        call.argument<String>("mimeType")?.let { intent.type = it }
        intent.addCategory(Intent.CATEGORY_DEFAULT)
        val handlers = packageManager.queryIntentActivities(
            intent,
            android.content.pm.PackageManager.MATCH_DEFAULT_ONLY,
        ).map { info ->
            mapOf(
                "label" to info.loadLabel(packageManager).toString(),
                "packageName" to info.activityInfo.packageName,
                "componentName" to ComponentName(
                    info.activityInfo.packageName,
                    info.activityInfo.name,
                ).flattenToString(),
            )
        }.distinctBy { it["componentName"] }
        result.success(handlers)
    }

    private fun launchIntent(call: MethodCall, result: MethodChannel.Result) {
        try {
            val intent = Intent(call.argument<String>("action") ?: Intent.ACTION_SEND)
            call.argument<String>("dataUri")?.let { intent.data = Uri.parse(it) }
            call.argument<String>("mimeType")?.let { intent.type = it }
            call.argument<List<String>>("categories")?.forEach(intent::addCategory)
            call.argument<String>("packageName")?.let(intent::setPackage)
            call.argument<String>("componentName")?.let {
                ComponentName.unflattenFromString(it)?.let(intent::setComponent)
            }
            putExtras(intent, call.argument<Map<String, Any?>>("extras") ?: emptyMap())
            if (call.argument<Boolean>("grantReadPermission") == true) {
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(
                if (call.argument<Boolean>("chooser") == true) {
                    Intent.createChooser(intent, null)
                } else {
                    intent
                },
            )
            result.success(null)
        } catch (error: ActivityNotFoundException) {
            result.error("target_unavailable", error.message, null)
        } catch (error: Exception) {
            result.error("launch_failed", error.message, null)
        }
    }

    private fun putExtras(intent: Intent, extras: Map<String, Any?>) {
        for ((key, value) in extras) {
            when (value) {
                is String -> if (key == Intent.EXTRA_STREAM && value.startsWith("content://")) {
                    intent.putExtra(key, Uri.parse(value))
                } else {
                    intent.putExtra(key, value)
                }
                is Int -> intent.putExtra(key, value)
                is Long -> intent.putExtra(key, value)
                is Double -> intent.putExtra(key, value)
                is Boolean -> intent.putExtra(key, value)
                is List<*> -> {
                    val strings = value.filterIsInstance<String>()
                    require(strings.size == value.size) {
                        "Unsupported Parcelable extra: $key"
                    }
                    if (key == Intent.EXTRA_STREAM) {
                        intent.putParcelableArrayListExtra(
                            key,
                            ArrayList(strings.map(Uri::parse)),
                        )
                    } else {
                        intent.putStringArrayListExtra(key, ArrayList(strings))
                    }
                }
                null -> Unit
                else -> throw IllegalArgumentException("Unsupported extra type: $key")
            }
        }
    }
}
