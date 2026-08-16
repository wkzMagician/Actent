package com.example.pengion

import android.content.Intent
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ShareIntentManifestTest {
    @Test
    fun declaresSingleAndMultipleShareInputs() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val packageManager = context.packageManager
        val single = packageManager.queryIntentActivities(
            Intent(Intent.ACTION_SEND).setType("text/plain"),
            0,
        )
        val multiple = packageManager.queryIntentActivities(
            Intent(Intent.ACTION_SEND_MULTIPLE).setType("image/*"),
            0,
        )
        assertTrue(single.any { it.activityInfo.packageName == context.packageName })
        assertTrue(multiple.any { it.activityInfo.packageName == context.packageName })
    }

    @Test
    fun mapsJsonUrlImageAndFileShareContent() {
        assertEquals(
            "json",
            ShareContentClassifier.type("application/json", "{\"ok\":true}"),
        )
        assertEquals("url", ShareContentClassifier.type("text/plain", "https://example.com"))
        assertEquals("image", ShareContentClassifier.type("image/png", null))
        assertEquals("file", ShareContentClassifier.type("application/pdf", null))
    }

    @Test
    fun receivesSendIntentAndCopiesAttachmentIntoPrivateStorage() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val source = File(context.cacheDir, "instrumented-share.txt").apply {
            writeText("private share payload")
        }
        val attachmentRoot = File(context.filesDir, "pigeon/attachments")
        val before = attachmentRoot.walkTopDown().count { it.isFile }
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_SEND
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, "shared from instrumentation")
            putExtra(Intent.EXTRA_STREAM, Uri.fromFile(source))
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        val activity = instrumentation.startActivitySync(intent)
        try {
            assertTrue(activity is MainActivity)
            instrumentation.waitForIdleSync()
            val copied = attachmentRoot.walkTopDown().count { it.isFile }
            assertTrue("share attachment was not copied", copied > before)
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
        }
    }
}
