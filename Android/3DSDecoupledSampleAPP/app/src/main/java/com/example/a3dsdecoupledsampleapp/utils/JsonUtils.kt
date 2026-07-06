package com.example.a3dsdecoupledsampleapp.utils

import com.google.gson.JsonObject

object JsonUtils {

    fun getStringOrNull(obj: JsonObject?, key: String): String? {
        if (obj == null || !obj.has(key)) return null
        val element = obj[key]
        if (element.isJsonNull) return null
        return element.asString.takeIf { it.isNotBlank() && !it.equals("null", true) }
    }

    fun decodeBody(body: String): String {
        val trimmed = body.trim()
        if (trimmed.startsWith("{") || trimmed.startsWith("[")) return trimmed
        return runCatching {
            String(android.util.Base64.decode(trimmed, android.util.Base64.DEFAULT), Charsets.UTF_8)
        }.getOrDefault(trimmed)
    }

    fun describeFailure(json: JsonObject): String {
        val meta   = json.get("metaData")?.takeIf { it.isJsonObject }?.asJsonObject
        val result = json.get("result")?.takeIf  { it.isJsonObject }?.asJsonObject
        return buildString {
            getStringOrNull(meta,   "txnStatus")?.let  { append("txnStatus=$it ") }
            getStringOrNull(meta,   "statusCode")?.let { append("code=$it ") }
            getStringOrNull(meta,   "message")?.let    { append("msg=$it ") }
            getStringOrNull(result, "error")?.let      { append("errCode=$it ") }
            (getStringOrNull(result, "error_Message") ?: getStringOrNull(result, "field9"))
                ?.let { append("errMsg=$it") }
            if (isEmpty()) append("(no details in response)")
        }
    }
}
