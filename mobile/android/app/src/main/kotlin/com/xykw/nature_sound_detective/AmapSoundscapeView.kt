package com.xykw.nature_sound_detective

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.ContextWrapper
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.amap.api.maps.AMap
import com.amap.api.maps.CameraUpdateFactory
import com.amap.api.maps.MapView
import com.amap.api.maps.MapsInitializer
import com.amap.api.maps.model.BitmapDescriptorFactory
import com.amap.api.maps.model.LatLng
import com.amap.api.maps.model.Marker
import com.amap.api.maps.model.MarkerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

internal const val AMAP_VIEW_TYPE = "com.xykw.nature_sound/amap_soundscape"
internal const val AMAP_PRIVACY_CHANNEL = "com.xykw.nature_sound/amap_privacy"
internal const val AMAP_PRIVACY_PREFERENCES = "amap_privacy"
internal const val AMAP_PRIVACY_ACCEPTED = "accepted"

internal class AmapSoundscapeViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        AmapSoundscapeView(context, messenger, viewId, args as? Map<*, *>)
}

private class AmapSoundscapeView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    args: Map<*, *>?,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "$AMAP_VIEW_TYPE/$viewId")
    private val root = FrameLayout(context)
    private var mapView: MapView? = null
    private var map: AMap? = null
    private val ownerActivity = context.findActivity()
    private var lifecycleRegistered = false
    private val features = mutableMapOf<String, Map<String, Any?>>()
    private var selectedMarker: Marker? = null

    init {
        channel.setMethodCallHandler(this)
        val accepted = context.getSharedPreferences(
            AMAP_PRIVACY_PREFERENCES,
            Context.MODE_PRIVATE,
        ).getBoolean(AMAP_PRIVACY_ACCEPTED, false)
        if (!accepted) {
            showMessage(context, "请先在应用中同意地图隐私说明")
        } else {
            initializeMap(context, args.orEmpty())
        }
    }

    private fun initializeMap(context: Context, args: Map<*, *>) {
        MapsInitializer.updatePrivacyShow(context.applicationContext, true, true)
        MapsInitializer.updatePrivacyAgree(context.applicationContext, true)
        val activeMapView = MapView(context)
        mapView = activeMapView
        root.addView(
            activeMapView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        activeMapView.onCreate(Bundle())
        activeMapView.onResume()
        (context.applicationContext as Application).registerActivityLifecycleCallbacks(
            lifecycleCallbacks,
        )
        lifecycleRegistered = true
        val activeMap = activeMapView.map
        map = activeMap
        activeMap.uiSettings.apply {
            isZoomControlsEnabled = false
            isCompassEnabled = false
            isScaleControlsEnabled = true
            isMyLocationButtonEnabled = false
            isRotateGesturesEnabled = false
            isTiltGesturesEnabled = false
        }
        activeMap.mapType = AMap.MAP_TYPE_NORMAL
        activeMap.moveCamera(
            CameraUpdateFactory.newLatLngZoom(HANGZHOU_CENTER, INITIAL_ZOOM),
        )
        activeMap.setInfoWindowAdapter(object : AMap.InfoWindowAdapter {
            override fun getInfoWindow(marker: Marker): View = createInfoWindow(marker)

            override fun getInfoContents(marker: Marker): View? = null
        })
        addFeatures(activeMap, args["areas"] as? List<*>, "area")
        addFeatures(activeMap, args["parks"] as? List<*>, "park")
        activeMap.setOnMarkerClickListener(::onMarkerClicked)
        activeMap.setOnMapLoadedListener {
            val approvalNumber = activeMap.mapContentApprovalNumber?.trim().orEmpty()
            if (approvalNumber.isEmpty()) {
                channel.invokeMethod("error", mapOf("message" to "地图鉴权未完成"))
                return@setOnMapLoadedListener
            }
            channel.invokeMethod(
                "ready",
                mapOf("approval_number" to approvalNumber),
            )
        }
    }

    private fun addFeatures(activeMap: AMap, values: List<*>?, type: String) {
        values.orEmpty().forEach { raw ->
            val value = raw as? Map<*, *> ?: return@forEach
            val id = value["id"] as? String ?: return@forEach
            val name = value["name"] as? String ?: return@forEach
            val latitude = (value["latitude"] as? Number)?.toDouble() ?: return@forEach
            val longitude = (value["longitude"] as? Number)?.toDouble() ?: return@forEach
            val normalized = value.entries.associate { (key, item) -> key.toString() to item }
            val featureKey = "$type:$id"
            features[featureKey] = normalized
            activeMap.addMarker(
                MarkerOptions()
                    .position(LatLng(latitude, longitude))
                    .title(name)
                    .snippet(
                        if (type == "park") {
                            "亲子倾听地点"
                        } else {
                            "${value["post_count"] ?: 0} 条声音"
                        },
                    )
                    .anchor(.5f, .5f)
                    .icon(createSoundMarker(type = type, selected = false)),
            ).`object` = featureKey
        }
    }

    private fun onMarkerClicked(marker: Marker): Boolean {
        val featureKey = marker.`object` as? String ?: return false
        val feature = features[featureKey] ?: return false
        selectedMarker?.let { previous ->
            val previousKey = previous.`object` as? String
            if (previousKey != null && previous !== marker) {
                previous.setIcon(
                    createSoundMarker(previousKey.substringBefore(':'), selected = false),
                )
            }
        }
        marker.setIcon(createSoundMarker(featureKey.substringBefore(':'), selected = true))
        selectedMarker = marker
        marker.showInfoWindow()
        map?.animateCamera(CameraUpdateFactory.newLatLng(marker.position), 280, null)
        channel.invokeMethod(
            "featureTap",
            mapOf(
                "type" to featureKey.substringBefore(':'),
                "id" to feature["id"],
            ),
        )
        return true
    }

    private fun createInfoWindow(marker: Marker): View {
        val context = root.context
        val container = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.START
            setPadding(dp(14), dp(10), dp(14), dp(10))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(18).toFloat()
                setColor(Color.rgb(255, 252, 243))
                setStroke(dp(1), Color.rgb(30, 91, 70))
            }
            elevation = dp(5).toFloat()
        }
        container.addView(TextView(context).apply {
            text = marker.title.orEmpty()
            textSize = 15f
            setTextColor(Color.rgb(25, 73, 56))
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 1
        })
        container.addView(TextView(context).apply {
            text = marker.snippet.orEmpty()
            textSize = 12f
            setTextColor(Color.rgb(91, 104, 97))
            maxLines = 1
            setPadding(0, dp(2), 0, 0)
        })
        return container
    }

    private fun createSoundMarker(type: String, selected: Boolean) =
        BitmapDescriptorFactory.fromBitmap(
            Bitmap.createBitmap(dp(48), dp(48), Bitmap.Config.ARGB_8888).also { bitmap ->
                val canvas = Canvas(bitmap)
                val center = dp(24).toFloat()
                val foreground = if (type == "park") {
                    Color.rgb(213, 158, 28)
                } else {
                    Color.rgb(27, 88, 66)
                }
                val shadow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.argb(42, 18, 45, 36)
                    setShadowLayer(dp(4).toFloat(), 0f, dp(2).toFloat(), color)
                }
                canvas.drawCircle(center, center, dp(if (selected) 18 else 15).toFloat(), shadow)
                val surface = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = if (selected) foreground else Color.rgb(255, 252, 243)
                    style = Paint.Style.FILL
                }
                canvas.drawCircle(center, center, dp(if (selected) 18 else 15).toFloat(), surface)
                val outline = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = foreground
                    style = Paint.Style.STROKE
                    strokeWidth = dp(2).toFloat()
                }
                canvas.drawCircle(center, center, dp(if (selected) 18 else 15).toFloat(), outline)
                val signal = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = if (selected) Color.WHITE else foreground
                    style = Paint.Style.STROKE
                    strokeWidth = dp(2).toFloat()
                    strokeCap = Paint.Cap.ROUND
                }
                canvas.drawCircle(center - dp(4), center, dp(2).toFloat(), Paint(signal).apply {
                    style = Paint.Style.FILL
                })
                canvas.drawArc(
                    RectF(center - dp(8), center - dp(7), center + dp(6), center + dp(7)),
                    -58f,
                    116f,
                    false,
                    signal,
                )
                canvas.drawArc(
                    RectF(center - dp(10), center - dp(10), center + dp(11), center + dp(10)),
                    -52f,
                    104f,
                    false,
                    signal,
                )
            },
        )

    private fun dp(value: Int): Int =
        (value * root.resources.displayMetrics.density).toInt().coerceAtLeast(1)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val activeMap = map
        if (activeMap == null) {
            result.error("map_unavailable", "地图尚未准备好", null)
            return
        }
        when (call.method) {
            "zoomIn" -> activeMap.animateCamera(CameraUpdateFactory.zoomIn())
            "zoomOut" -> activeMap.animateCamera(CameraUpdateFactory.zoomOut())
            "reset" -> activeMap.animateCamera(
                CameraUpdateFactory.newLatLngZoom(HANGZHOU_CENTER, INITIAL_ZOOM),
            )
            else -> {
                result.notImplemented()
                return
            }
        }
        result.success(null)
    }

    override fun getView(): View = root

    override fun dispose() {
        channel.setMethodCallHandler(null)
        map?.setOnMarkerClickListener(null)
        map?.setOnMapLoadedListener(null)
        map?.setInfoWindowAdapter(null)
        selectedMarker = null
        map = null
        mapView?.onPause()
        mapView?.onDestroy()
        mapView = null
        root.removeAllViews()
        if (lifecycleRegistered) {
            (root.context.applicationContext as Application)
                .unregisterActivityLifecycleCallbacks(lifecycleCallbacks)
            lifecycleRegistered = false
        }
    }

    private fun showMessage(context: Context, message: String) {
        root.setBackgroundColor(Color.rgb(248, 245, 236))
        root.addView(
            TextView(context).apply {
                text = message
                textSize = 15f
                setTextColor(Color.rgb(49, 84, 73))
                gravity = android.view.Gravity.CENTER
                setPadding(48, 48, 48, 48)
            },
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
    }

    companion object {
        private val HANGZHOU_CENTER = LatLng(30.2741, 120.1551)
        private const val INITIAL_ZOOM = 10.4f
    }

    private val lifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityResumed(activity: Activity) {
            if (activity === ownerActivity) mapView?.onResume()
        }

        override fun onActivityPaused(activity: Activity) {
            if (activity === ownerActivity) mapView?.onPause()
        }

        override fun onActivityDestroyed(activity: Activity) {
            if (activity === ownerActivity) {
                mapView?.onDestroy()
                mapView = null
                map = null
            }
        }

        override fun onActivityCreated(activity: Activity, state: Bundle?) = Unit
        override fun onActivityStarted(activity: Activity) = Unit
        override fun onActivityStopped(activity: Activity) = Unit
        override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) = Unit
    }
}

private fun Context.findActivity(): Activity? {
    var current: Context? = this
    while (current is ContextWrapper) {
        if (current is Activity) return current
        current = current.baseContext
    }
    return null
}
