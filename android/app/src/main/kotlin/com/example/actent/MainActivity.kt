package com.example.actent

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/// Application configuration and outbound Work integration.
///
/// Dartloom's external-input plugin receives incoming shared content.
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "actent/android_share"
        private const val DEVICE_CHANNEL = "actent/device"
        private const val FILE_PROVIDER_SUFFIX = ".fileprovider"
        private const val IMAGE_PICKER_REQUEST = 1401
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
            "pickImages" -> pickImages(call, result)
            "cleanupPickedImages" -> cleanupPickedImages(call, result)
            else -> result.notImplemented()
        }
    }

    private var pendingImagePickerResult: MethodChannel.Result? = null

    private fun pickImages(call: MethodCall, result: MethodChannel.Result) {
        if (pendingImagePickerResult != null) {
            result.error("picker_busy", "An image picker is already open", null)
            return
        }
        pendingImagePickerResult = result
        val maximum = (call.argument<Int>("maximum") ?: 20).coerceIn(1, 100)
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                type = "image/*"
                putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, maximum)
            }
        } else {
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                type = "image/*"
                addCategory(Intent.CATEGORY_OPENABLE)
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            }
        }
        try {
            startActivityForResult(intent, IMAGE_PICKER_REQUEST)
        } catch (error: Exception) {
            pendingImagePickerResult = null
            result.error("picker_unavailable", error.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != IMAGE_PICKER_REQUEST) return
        val result = pendingImagePickerResult
        pendingImagePickerResult = null
        if (result == null) return
        if (resultCode != RESULT_OK || data == null) {
            result.success(emptyList<String>())
            return
        }
        try {
            result.success(copyPickedImages(data))
        } catch (error: Exception) {
            result.error("picker_copy_failed", error.message, null)
        }
    }

    private fun copyPickedImages(data: Intent): List<String> {
        val uris = mutableListOf<Uri>()
        data.data?.let(uris::add)
        data.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) uris.add(clip.getItemAt(index).uri)
        }
        val directory = File(filesDir, "actent/picker/${System.currentTimeMillis()}")
        directory.mkdirs()
        return uris.distinct().mapIndexedNotNull { index, uri ->
            val destination = File(directory, "image-$index")
            val input = contentResolver.openInputStream(uri) ?: return@mapIndexedNotNull null
            input.use { stream ->
                FileOutputStream(destination).use { output -> stream.copyTo(output) }
            }
            destination.path
        }
    }

    private fun cleanupPickedImages(call: MethodCall, result: MethodChannel.Result) {
        val paths = call.argument<List<String>>("paths") ?: emptyList()
        val root = File(filesDir, "actent/picker").canonicalFile
        for (path in paths) {
            val file = File(path).canonicalFile
            if (file.path.startsWith(root.path + File.separator) && file.exists()) {
                file.delete()
                file.parentFile?.delete()
            }
        }
        result.success(null)
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
