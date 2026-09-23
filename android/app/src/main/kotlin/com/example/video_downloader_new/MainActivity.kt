package com.example.video_downloader_new

import android.content.ContentValues
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import dev.ffmpegkit_maintained.ytdlp.DownloadProgressCallback
import dev.ffmpegkit_maintained.ytdlp.YtDlp
import dev.ffmpegkit_maintained.ytdlp.YtDlpException
import dev.ffmpegkit_maintained.ytdlp.YtDlpRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "video_downloader/ytdlp"
    private lateinit var methodChannel: MethodChannel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            YtDlp.init(applicationContext)
            Log.d("VideoDownloader", "yt-dlp initialized successfully")
        } catch (e: YtDlpException) {
            Log.e("VideoDownloader", "yt-dlp initialization failed", e)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "analyzeUrl" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrBlank()) {
                        result.error("INVALID_URL", "الرابط فارغ", null)
                        return@setMethodCallHandler
                    }
                    analyzeUrl(url.trim(), result)
                }

                "downloadVideo" -> {
                    val url = call.argument<String>("url")
                    val formatId = call.argument<String>("formatId")
                    val title = call.argument<String>("title") ?: "video"

                    if (url.isNullOrBlank()) {
                        result.error("INVALID_URL", "الرابط فارغ", null)
                        return@setMethodCallHandler
                    }
                    if (formatId.isNullOrBlank()) {
                        result.error("INVALID_FORMAT", "لم يتم اختيار جودة", null)
                        return@setMethodCallHandler
                    }

                    downloadVideo(url.trim(), formatId, title, result)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun analyzeUrl(url: String, result: MethodChannel.Result) {
        Thread {
            try {
                val py = com.chaquo.python.Python.getInstance()
                val ytDlp = py.getModule("yt_dlp")
                val youtubeDL = ytDlp.callAttr("YoutubeDL")
                val info = youtubeDL.callAttr(
                    "extract_info",
                    url,
                    com.chaquo.python.Kwarg("download", false)
                )
                val jsonModule = py.getModule("json")
                val jsonOutput = jsonModule.callAttr("dumps", info).toString()
                val json = org.json.JSONObject(jsonOutput)

                val formatsList = mutableListOf<Map<String, Any?>>()
                val formats = json.optJSONArray("formats")
                if (formats != null) {
                    for (i in 0 until formats.length()) {
                        val format = formats.optJSONObject(i) ?: continue
                        val formatId = format.optString("format_id", "")
                        val vcodec = format.optString("vcodec", "")
                        val acodec = format.optString("acodec", "")
                        val height = format.optInt("height", 0)
                        if (vcodec == "none" || height <= 0) continue

                        formatsList.add(
                            mapOf(
                                "format_id" to formatId,
                                "ext" to format.optString("ext", ""),
                                "width" to format.optInt("width", 0),
                                "height" to height,
                                "fps" to format.optDouble("fps", 0.0),
                                "filesize" to if (!format.isNull("filesize")) format.optLong("filesize", 0L) else 0L,
                                "filesize_approx" to if (!format.isNull("filesize_approx")) format.optLong("filesize_approx", 0L) else 0L,
                                "tbr" to format.optDouble("tbr", 0.0),
                                "vcodec" to vcodec,
                                "acodec" to acodec,
                                "format_note" to format.optString("format_note", ""),
                                "protocol" to format.optString("protocol", "")
                            )
                        )
                    }
                }

                val response = mapOf(
                    "success" to true,
                    "url" to url,
                    "webpage_url" to json.optString("webpage_url", url),
                    "id" to json.optString("id", ""),
                    "title" to json.optString("title", "بدون عنوان"),
                    "thumbnail" to json.optString("thumbnail", ""),
                    "uploader" to json.optString("uploader", json.optString("channel", "")),
                    "duration" to json.optDouble("duration", 0.0),
                    "ext" to json.optString("ext", ""),
                    "formats" to formatsList,
                    "raw" to jsonOutput
                )

                runOnUiThread { result.success(response) }
            } catch (e: Exception) {
                Log.e("VideoDownloader", "Metadata extraction failed", e)
                runOnUiThread {
                    result.error("YTDLP_ERROR", e.message ?: "حدث خطأ أثناء تحليل الرابط", null)
                }
            }
        }.start()
    }

    private fun downloadVideo(
        url: String,
        formatId: String,
        title: String,
        result: MethodChannel.Result
    ) {
        Thread {
            val baseDirectory = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            if (baseDirectory == null) {
                runOnUiThread { result.error("STORAGE_ERROR", "تعذر الوصول إلى مجلد التخزين", null) }
                return@Thread
            }

            val workDirectory = File(baseDirectory, "download_${System.currentTimeMillis()}")
            if (!workDirectory.mkdirs() && !workDirectory.exists()) {
                runOnUiThread { result.error("STORAGE_ERROR", "تعذر إنشاء مجلد التنزيل المؤقت", null) }
                return@Thread
            }

            try {
                val safeTitle = title
                    .replace(Regex("[\\\\/:*?\"<>|]"), "_")
                    .trim()
                    .ifEmpty { "video" }
                    .take(100)

                val outputTemplate = File(workDirectory, "${safeTitle}_%(id)s.%(ext)s").absolutePath
                val request = YtDlpRequest(url)
                    .setOutputTemplate(outputTemplate)
                    .addOption("-f", formatId)
                    .addOption("--no-playlist")
                    .addOption("--no-mtime")

                val callback = DownloadProgressCallback { progress, eta, line ->
                    Log.d("VideoDownloader", "DOWNLOAD: $progress% - ETA: $eta - $line")
                    runOnUiThread {
                        if (::methodChannel.isInitialized) {
                            methodChannel.invokeMethod(
                                "downloadProgress",
                                mapOf(
                                    "progress" to (progress / 100.0f).coerceIn(0f, 1f),
                                    "eta" to eta,
                                    "line" to line
                                )
                            )
                        }
                    }
                }

                val response = YtDlp.execute(request, callback)
                if (!response.isSuccess) {
                    runOnUiThread { result.error("DOWNLOAD_FAILED", "فشل تنزيل الفيديو", null) }
                    return@Thread
                }

                val downloadedFile = workDirectory.listFiles()
                    ?.filter { it.isFile && !it.name.endsWith(".part") }
                    ?.maxByOrNull { it.lastModified() }

                if (downloadedFile == null || !downloadedFile.exists()) {
                    runOnUiThread {
                        result.error("FILE_NOT_FOUND", "تم التنزيل ولكن لم يتم العثور على الملف", null)
                    }
                    return@Thread
                }

                val savedFile = saveToDownloads(downloadedFile)
                runOnUiThread {
                    result.success(
                        mapOf(
                            "success" to true,
                            "fileName" to savedFile,
                            "message" to "تم تنزيل الفيديو بنجاح"
                        )
                    )
                }
            } catch (e: Exception) {
                Log.e("VideoDownloader", "Download failed", e)
                runOnUiThread {
                    result.error("DOWNLOAD_ERROR", e.message ?: "حدث خطأ أثناء التنزيل", null)
                }
            } finally {
                workDirectory.deleteRecursively()
            }
        }.start()
    }

    private fun saveToDownloads(sourceFile: File): String {
        val fileName = sourceFile.name

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val mimeType = when (sourceFile.extension.lowercase()) {
                "mp4", "m4v" -> "video/mp4"
                "webm" -> "video/webm"
                "mkv" -> "video/x-matroska"
                "mov" -> "video/quicktime"
                else -> "video/*"
            }

            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }

            val uri = contentResolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                values
            ) ?: throw Exception("تعذر إنشاء ملف في مجلد التنزيلات")

            try {
                contentResolver.openOutputStream(uri)?.use { output ->
                    sourceFile.inputStream().use { input -> input.copyTo(output) }
                } ?: throw Exception("تعذر فتح ملف التنزيل")

                contentResolver.update(
                    uri,
                    ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) },
                    null,
                    null
                )
                return fileName
            } catch (e: Exception) {
                contentResolver.delete(uri, null, null)
                throw e
            }
        }

        @Suppress("DEPRECATION")
        val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!downloads.exists()) downloads.mkdirs()
        val destination = File(downloads, fileName)
        sourceFile.copyTo(destination, overwrite = true)
        return destination.name
    }
}
