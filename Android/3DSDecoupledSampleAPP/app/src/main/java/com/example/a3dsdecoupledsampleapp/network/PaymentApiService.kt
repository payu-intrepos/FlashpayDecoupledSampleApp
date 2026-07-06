package com.example.a3dsdecoupledsampleapp.network

import com.example.a3dsdecoupledsampleapp.utils.HashUtils
import com.example.a3dsdecoupledsampleapp.utils.JsonUtils
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

class PaymentApiService {

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    /**
     * Posts payment parameters to the PayU _payment endpoint.
     * Switches to [Dispatchers.IO] internally — callers do not need to manage the dispatcher.
     */
    suspend fun callPaymentsApi(
        params: LinkedHashMap<String, String>,
        salt: String,
        baseUrl: String
    ): JsonObject = withContext(Dispatchers.IO) {
        val hash = HashUtils.sha512(
            listOf(
                params.getValue("key"),
                params.getValue("txnid"),
                params.getValue("amount"),
                params.getValue("productinfo"),
                params.getValue("firstname"),
                params.getValue("email"),
                "", "", "", "", "",
                "", "", "", "", "",
                salt,
            ).joinToString("|")
        )

        val formBody = FormBody.Builder()
            .also { builder -> params.forEach { (key, value) -> builder.add(key, value) } }
            .add("hash", hash)
            .build()

        val request = Request.Builder()
            .url("$baseUrl/_payment")
            .post(formBody)
            .build()

        httpClient.newCall(request).execute().use { response ->
            val body = JsonUtils.decodeBody(response.body?.string().orEmpty())
            if (!response.isSuccessful) error("HTTP ${response.code}: ${body.take(300)}")
            runCatching { JsonParser().parse(body).asJsonObject }
                .getOrElse { error("Unexpected response: ${body.take(300)}") }
        }
    }
}
