package com.liita.liita

import android.util.Base64
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream

object Utils {
    fun compressAndEncode(jsonStr: String): String {
        val bos = ByteArrayOutputStream()
        GZIPOutputStream(bos).use { it.write(jsonStr.toByteArray()) }
        return Base64.encodeToString(bos.toByteArray(), Base64.NO_WRAP)
    }

    fun decodeAndDecompress(base64Str: String): String? {
        return try {
            val bytes = Base64.decode(base64Str, Base64.NO_WRAP)
            val bis = ByteArrayInputStream(bytes)
            GZIPInputStream(bis).bufferedReader().use { it.readText() }
        } catch (e: Exception) {
            null
        }
    }
}
