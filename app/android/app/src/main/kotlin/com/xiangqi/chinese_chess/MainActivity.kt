package com.xiangqi.chinese_chess

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.xiangqi.chinese_chess/engine"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getEngineDir" -> {
                    result.success(applicationInfo.nativeLibraryDir)
                }
                "getCacheDir" -> {
                    result.success(cacheDir.absolutePath)
                }
                "getCpuArch" -> {
                    result.success(android.os.Build.SUPPORTED_ABIS.joinToString(","))
                }
                "copyNnueFile" -> {
                    // 将 assets 中的 pikafish.nnue 高效复制到缓存目录
                    try {
                        val destFile = File(cacheDir, "pikafish.nnue")
                        val minExpectedSize = 40L * 1024L * 1024L

                        // 已存在且大小合理时直接复用（避免重复拷贝）
                        if (destFile.exists() && destFile.length() >= minExpectedSize) {
                            result.success(destFile.absolutePath)
                            return@setMethodCallHandler
                        }

                        // 使用缓冲IO流式复制（不会一次性加载51MB到内存）
                        val tmpFile = File(cacheDir, "pikafish.nnue.tmp")
                        assets.open("pikafish.nnue").buffered(8192).use { input ->
                            FileOutputStream(tmpFile).buffered(8192).use { output ->
                                input.copyTo(output, 8192)
                            }
                        }

                        if (tmpFile.length() < minExpectedSize) {
                            tmpFile.delete()
                            throw IllegalStateException("NNUE file is too small after copy")
                        }

                        if (destFile.exists()) {
                            destFile.delete()
                        }
                        if (!tmpFile.renameTo(destFile)) {
                            throw IllegalStateException("Failed to move NNUE temp file")
                        }

                        result.success(destFile.absolutePath)
                    } catch (e: Exception) {
                        result.error("NNUE_COPY_FAILED", e.message, e.stackTraceToString())
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
