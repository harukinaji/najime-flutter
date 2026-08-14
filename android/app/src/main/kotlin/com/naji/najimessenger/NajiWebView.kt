package com.naji.najimessenger

import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.view.View
import android.webkit.JavascriptInterface
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

class NajiWebView(
    context: Context,
    messenger: BinaryMessenger,
    id: Int,
    creationParams: Map<String?, Any?>?
) : PlatformView, MethodChannel.MethodCallHandler {

    private val webView: WebView
    private val methodChannel: MethodChannel
    private val handler = Handler(Looper.getMainLooper())

    init {
        methodChannel = MethodChannel(messenger, "naji_webview_$id")
        methodChannel.setMethodCallHandler(this)

        webView = WebView(context)
        webView.settings.javaScriptEnabled = true
        webView.settings.mediaPlaybackRequiresUserGesture = false
        webView.settings.domStorageEnabled = true
        webView.settings.allowFileAccess = false
        webView.settings.allowFileAccessFromFileURLs = false
        webView.settings.allowUniversalAccessFromFileURLs = false
        webView.settings.setGeolocationEnabled(false)

        webView.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) {
                val allowed = request.resources.filter {
                    it == PermissionRequest.RESOURCE_VIDEO_CAPTURE ||
                    it == PermissionRequest.RESOURCE_AUDIO_CAPTURE
                }.toTypedArray()
                if (allowed.isNotEmpty()) {
                    request.grant(allowed)
                } else {
                    request.deny()
                }
            }
        }

        webView.addJavascriptInterface(object : Any() {
            @JavascriptInterface
            fun postMessage(message: String) {
                handler.post {
                    methodChannel.invokeMethod("onJsMessage", message)
                }
            }
        }, "NajiBridge")

        webView.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                handler.post { methodChannel.invokeMethod("onPageStarted", url ?: "") }
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                handler.post { methodChannel.invokeMethod("onPageFinished", url ?: "") }
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?
            ) {
                handler.post {
                    methodChannel.invokeMethod("onWebResourceError", mapOf(
                        "description" to (error?.description?.toString() ?: "Unknown error"),
                        "code" to (error?.errorCode ?: -1)
                    ))
                }
            }
        }

        val url = creationParams?.get("url") as? String
        if (url != null) {
            webView.loadUrl(url)
        }
    }

    override fun getView(): View = webView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadUrl" -> {
                val url = call.argument<String>("url")
                if (url != null) {
                    val uri = android.net.Uri.parse(url)
                    val scheme = uri.scheme?.lowercase() ?: ""
                    if (scheme != "http" && scheme != "https") {
                        result.error("INVALID_URL", "Only http/https URLs allowed", null)
                    } else {
                        webView.loadUrl(url)
                        result.success(true)
                    }
                } else {
                    result.error("INVALID_ARG", "url required", null)
                }
            }
            "runJavaScript" -> {
                val js = call.argument<String>("js")
                if (js != null) {
                    webView.evaluateJavascript(js, null)
                    result.success(true)
                } else {
                    result.error("INVALID_ARG", "js required", null)
                }
            }
            "dispose" -> {
                webView.destroy()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        webView.destroy()
    }
}
