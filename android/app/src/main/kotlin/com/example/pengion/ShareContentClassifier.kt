package com.example.pengion

import java.util.Locale

internal object ShareContentClassifier {
    fun type(mimeType: String, sharedText: String?): String {
        val normalizedMime = mimeType.lowercase(Locale.US)
        if (normalizedMime == "application/json" || normalizedMime.endsWith("+json")) {
            return "json"
        }
        if (!sharedText.isNullOrEmpty()) {
            return if (sharedText.startsWith("http://") || sharedText.startsWith("https://")) {
                "url"
            } else {
                "text"
            }
        }
        return if (normalizedMime.startsWith("image/")) "image" else "file"
    }
}
