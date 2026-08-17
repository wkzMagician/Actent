package com.example.actent

import android.content.ComponentName
import android.content.Intent
import android.content.ActivityNotFoundException
import android.net.Uri
import android.os.Bundle
import android.os.Parcelable
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "actent/android_share"
        private const val FILE_PROVIDER_SUFFIX = ".fileprovider"
    }

    private var eventSink: EventChannel.EventSink? = null
    private val pendingMessages = ArrayDeque<Map<String, Any?>>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    while (pendingMessages.isNotEmpty()) eventSink?.success(pendingMessages.removeFirst())
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handleMethod(call, result) }
        handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    private fun handleMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createContentUri" -> {
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
                    val uri = FileProvider.getUriForFile(this, packageName + FILE_PROVIDER_SUFFIX, file)
                    result.success(uri.toString())
                } catch (error: Exception) {
                    result.error("file_provider_error", error.message, null)
                }
            }
            "launchIntent" -> launchIntent(call, result)
            else -> result.notImplemented()
        }
    }

    private fun launchIntent(call: MethodCall, result: MethodChannel.Result) {
        try {
            val intent = Intent(call.argument<String>("action") ?: Intent.ACTION_SEND)
            call.argument<String>("dataUri")?.let { intent.data = Uri.parse(it) }
            call.argument<String>("mimeType")?.let { intent.type = it }
            call.argument<List<String>>("categories")?.forEach { intent.addCategory(it) }
            call.argument<String>("packageName")?.let { intent.setPackage(it) }
            call.argument<String>("componentName")?.let {
                ComponentName.unflattenFromString(it)?.let(intent::setComponent)
            }
            val extras = call.argument<Map<String, Any?>>("extras") ?: emptyMap()
            putExtras(intent, extras)
            if (call.argument<Boolean>("grantReadPermission") == true) {
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val launchIntent = if (call.argument<Boolean>("chooser") == true) {
                Intent.createChooser(intent, null)
            } else {
                intent
            }
            startActivity(launchIntent)
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
                is String -> {
                    if (key == Intent.EXTRA_STREAM && value.startsWith("content://")) {
                        intent.putExtra(key, Uri.parse(value))
                    } else {
                        intent.putExtra(key, value)
                    }
                }
                is Int -> intent.putExtra(key, value)
                is Long -> intent.putExtra(key, value)
                is Double -> intent.putExtra(key, value)
                is Boolean -> intent.putExtra(key, value)
                is List<*> -> {
                    val strings = value.filterIsInstance<String>()
                    if (strings.size != value.size) {
                        throw IllegalArgumentException("Unsupported Parcelable extra: $key")
                    }
                    if (key == Intent.EXTRA_STREAM) {
                        intent.putParcelableArrayListExtra(
                            key,
                            ArrayList(strings.map(Uri::parse))
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

    private fun handleShareIntent(incoming: Intent?) {
        if (incoming == null ||
            (incoming.action != Intent.ACTION_SEND && incoming.action != Intent.ACTION_SEND_MULTIPLE)) {
            return
        }
        try {
            val attachments = copyAttachments(incoming)
            val sharedText = incoming.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
            val mimeType = incoming.type ?: "application/octet-stream"
            val contentType: String
            val content: MutableMap<String, Any?> = mutableMapOf("mimeType" to mimeType)
            contentType = ShareContentClassifier.type(mimeType, sharedText)
            if (!sharedText.isNullOrEmpty()) {
                content[contentType] = sharedText
            }
            content["type"] = contentType
            val source = mapOf<String, Any?>(
                "kind" to "share",
                "platform" to "android",
            )
            val message = mapOf<String, Any?>(
                "id" to "message-${UUID.randomUUID()}",
                "traceId" to UUID.randomUUID().toString(),
                "schemaVersion" to 1,
                "createdAt" to utcNow(),
                "source" to source,
                "content" to content,
                "attachments" to attachments,
                "metadata" to mapOf("intentAction" to incoming.action),
            )
            deliver(message)
        } catch (_: Exception) {
            // A malformed or inaccessible source is rejected before it reaches
            // Dart; the originating app retains ownership of the original URI.
        }
    }

    private fun copyAttachments(incoming: Intent): List<Map<String, Any?>> {
        val uris = mutableListOf<Uri>()
        if (incoming.action == Intent.ACTION_SEND_MULTIPLE) {
            incoming.getParcelableArrayListExtra<Parcelable>(Intent.EXTRA_STREAM)
                ?.mapNotNullTo(uris) { it as? Uri }
        } else {
            incoming.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::add)
        }
        return uris.map { copyAttachment(it) }
    }

    private fun copyAttachment(uri: Uri): Map<String, Any?> {
        val attachmentId = "attachment-${UUID.randomUUID()}"
        val directory = File(filesDir, "actent/attachments/$attachmentId")
        directory.mkdirs()
        val target = File(directory, "payload")
        contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "Unable to open shared attachment" }
            target.outputStream().use { output -> input.copyTo(output) }
        }
        val name = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            } ?: "attachment"
        return mapOf(
            "id" to attachmentId,
            "name" to name,
            "mimeType" to (contentResolver.getType(uri) ?: "application/octet-stream"),
            "byteLength" to target.length(),
            "handle" to target.absolutePath,
        )
    }

    private fun deliver(message: Map<String, Any?>) {
        val sink = eventSink
        if (sink != null) sink.success(message) else pendingMessages.addLast(message)
    }

    private fun utcNow(): String = SimpleDateFormat(
        "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
        Locale.US,
    ).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }.format(Date())
}
