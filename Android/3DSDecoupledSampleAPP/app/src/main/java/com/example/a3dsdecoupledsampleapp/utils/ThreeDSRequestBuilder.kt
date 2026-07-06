package com.example.a3dsdecoupledsampleapp.utils

import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.payu.threedsbase.data.PArqResponse

object ThreeDSRequestBuilder {

    fun buildRequest(parq: PArqResponse): String {
        val pubKey = JsonObject().apply {
            addProperty("crv", parq.crv)
            addProperty("kty", parq.kty)
            addProperty("x",   parq.x)
            addProperty("y",   parq.y)
        }
        val renderOptions = JsonObject().apply {
            addProperty("sdkInterface", "03")
            add("sdkUiType", JsonArray().apply {
                listOf("05", "01", "02", "03", "04").forEach { add(it) }
            })
        }
        val sdkInfo = JsonObject().apply {
            addProperty("sdkEncData",         parq.sdkEncData)
            addProperty("sdkAppID",           parq.sdkAppID)
            addProperty("sdkReferenceNumber", parq.sdkReferenceNumber)
            addProperty("sdkTransID",         parq.sdkTransID)
            addProperty("sdkMaxTimeout",      "05")
            add("deviceRenderOptions", renderOptions)
            add("sdkEphemPubKey",      pubKey)
        }
        return JsonObject().apply {
            add("sdkInfo", sdkInfo)
            addProperty("deviceChannel", "APP")
        }.toString()
    }
}
