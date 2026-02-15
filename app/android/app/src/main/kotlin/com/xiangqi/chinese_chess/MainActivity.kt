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
                    // 将 assets 中的 pikafish.nnue 复制到缓存目录
                    // *** 每次都强制重新复制，避免旧版缓存文件导致引擎加载失败 ***
                    try {
                        val destFile = File(cacheDir, "pikafish.nnue")
                        val minExpectedSize = 50L * 1024L * 1024L

                        // 始终删除旧文件并重新复制（避免之前版本遗留的损坏文件）
                        if (destFile.exists()) {
                            destFile.delete()
                            android.util.Log.i("PikafishNNUE", "Deleted old cached NNUE file")
                        }

                        // 使用缓冲IO流式复制（不会一次性加载51MB到内存）
                        val tmpFile = File(cacheDir, "pikafish.nnue.tmp")
                        if (tmpFile.exists()) tmpFile.delete()

                        val startTime = System.currentTimeMillis()
                        assets.open("pikafish.nnue").buffered(65536).use { input ->
                            FileOutputStream(tmpFile).buffered(65536).use { output ->
                                input.copyTo(output, 65536)
                            }
                        }
                        val elapsed = System.currentTimeMillis() - startTime
                        android.util.Log.i("PikafishNNUE", "Copy took ${elapsed}ms, size=${tmpFile.length()}")

                        if (tmpFile.length() < minExpectedSize) {
                            tmpFile.delete()
                            throw IllegalStateException(
                                "NNUE file too small: ${tmpFile.length()} bytes, expected >= $minExpectedSize")
                        }

                        if (!tmpFile.renameTo(destFile)) {
                            throw IllegalStateException("Failed to rename NNUE temp file")
                        }

                        // 确保文件全局可读（引擎子进程需要读取）
                        destFile.setReadable(true, false)
                        destFile.setWritable(false)

                        // 验证文件头：前16字节
                        val header = destFile.inputStream().use { it.readNBytes(16) }
                        val headerHex = header.joinToString(" ") { "%02X".format(it) }
                        android.util.Log.i("PikafishNNUE", "Header: $headerHex")

                        // NNUE raw header 验证:
                        // 前4字节 = Version (0x7AF32F20 LE = 20 2F F3 7A)
                        // 后4字节 = Hash (0x6E24D34A LE = 4A D3 24 6E)
                        val isValidNnue = header.size >= 8 &&
                            header[0] == 0x20.toByte() && header[1] == 0x2F.toByte() &&
                            header[2] == 0xF3.toByte() && header[3] == 0x7A.toByte() &&
                            header[4] == 0x4A.toByte() && header[5] == 0xD3.toByte() &&
                            header[6] == 0x24.toByte() && header[7] == 0x6E.toByte()
                        if (!isValidNnue) {
                            destFile.delete()
                            throw IllegalStateException(
                                "NNUE header invalid: $headerHex, expected 20 2F F3 7A 4A D3 24 6E")
                        }

                        android.util.Log.i("PikafishNNUE",
                            "NNUE ready: ${destFile.absolutePath} (${destFile.length()} bytes)")

                        // *** 计算 SHA256 验证文件完整性 ***
                        val digest = java.security.MessageDigest.getInstance("SHA-256")
                        destFile.inputStream().buffered(65536).use { sha256input ->
                            val buffer = ByteArray(65536)
                            var bytesRead: Int
                            while (sha256input.read(buffer).also { bytesRead = it } != -1) {
                                digest.update(buffer, 0, bytesRead)
                            }
                        }
                        val sha256Hex = digest.digest().joinToString("") { "%02x".format(it) }
                        android.util.Log.i("PikafishNNUE", "SHA256: $sha256Hex")

                        // 预期 SHA256（解压后的 raw NNUE 文件）
                        val expectedSha256 = "ec1649d0f32d000f22f6ee8f7e339ff27c2e967ea1ff5580603bb6bb686bbd56"
                        if (sha256Hex != expectedSha256) {
                            android.util.Log.e("PikafishNNUE",
                                "SHA256 MISMATCH! expected=$expectedSha256, got=$sha256Hex")
                        } else {
                            android.util.Log.i("PikafishNNUE", "SHA256 VERIFIED OK")
                        }

                        // 返回文件路径
                        result.success(destFile.absolutePath)
                    } catch (e: Exception) {
                        android.util.Log.e("PikafishNNUE", "Copy failed", e)
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
