package com.nikhil.yt.playback

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import androidx.core.net.toUri
import androidx.media3.datasource.DataSourceInputStream
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.cache.Cache
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.exoplayer.offline.Download
import com.nikhil.yt.R
import com.nikhil.yt.db.MusicDatabase
import com.nikhil.yt.di.DownloadCache
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.io.InputStream
import javax.inject.Inject
import javax.inject.Singleton

data class DownloadLocation(val id: String, val label: String)
data class StoredDownload(val uri: String, val bytes: Long, val location: String)

/** Keeps Media3's download index, but allows completed audio to live outside its staging cache. */
@Singleton
class DownloadStorage @Inject constructor(
    @ApplicationContext private val context: Context,
    private val database: MusicDatabase,
    @DownloadCache private val cache: Cache,
) {
    private val preferences = context.getSharedPreferences("download_locations", Context.MODE_PRIVATE)
    private val mutex = Mutex()
    val location = MutableStateFlow(
        DownloadLocation(
            preferences.getString("location", PHONE) ?: PHONE,
            preferences.getString("label", null) ?: context.getString(R.string.download_private_phone),
        )
    )
    val files = MutableStateFlow(loadFiles())
    private val pendingRemovals = MutableStateFlow(preferences.all.filter { (key, value) ->
        key.startsWith("removing.") && value == true
    }.keys.map { it.removePrefix("removing.") }.toSet())
    val busy = MutableStateFlow(false)
    val error = MutableStateFlow<String?>(null)

    fun privateLocations(): List<DownloadLocation> {
        val manager = context.getSystemService(StorageManager::class.java)
        return listOf(DownloadLocation(PHONE, context.getString(R.string.download_private_phone))) +
            context.getExternalFilesDirs(Environment.DIRECTORY_MUSIC).filterNotNull()
                .filter { Environment.isExternalStorageRemovable(it) && Environment.getExternalStorageState(it) == Environment.MEDIA_MOUNTED }
                .map { directory ->
                    val name = manager.getStorageVolume(directory)?.getDescription(context)
                        ?: context.getString(R.string.download_sd_card)
                    DownloadLocation("private:${directory.absolutePath}", context.getString(R.string.download_private_volume, name))
                }
    }

    suspend fun selectPrivate(value: DownloadLocation) = withContext(Dispatchers.IO) {
        require(privateLocations().any { it.id == value.id }) { "Storage is unavailable" }
        select(value)
    }

    suspend fun selectFolder(uri: Uri) = withContext(Dispatchers.IO) {
        context.contentResolver.takePersistableUriPermission(
            uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
        )
        val document = DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri))
        val writable = context.contentResolver.query(
            document, arrayOf(DocumentsContract.Document.COLUMN_FLAGS), null, null, null,
        )?.use { cursor ->
            cursor.moveToFirst() && (cursor.getInt(0) and DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE) != 0
        } ?: false
        require(writable) { "This folder is not writable" }
        val name = DocumentsContract.getTreeDocumentId(uri)
        select(DownloadLocation("tree:$uri", context.getString(R.string.download_public_folder, name)))
        // Keep previous grants: existing songs may still be stored in an earlier folder.
    }

    private fun select(value: DownloadLocation) {
        check(preferences.edit().putString("location", value.id).putString("label", value.label).commit())
        location.value = value
        error.value = null
    }

    /** Capture the destination when a download starts, rather than moving old songs implicitly. */
    fun hasCapturedLocation(download: Download): Boolean =
        preferences.contains(targetKey(download)) && download.request.id !in pendingRemovals.value

    fun captureLocation(download: Download, target: String = location.value.id) {
        if (hasCapturedLocation(download)) return
        val id = download.request.id
        val editor = preferences.edit()
        if (!preferences.contains(targetKey(download))) {
            editor.putString(targetKey(download), target)
        }
        editor.remove("removing.$id").apply()
        pendingRemovals.update { it - id }
    }

    fun uriFor(id: String?): Uri? = if (id in pendingRemovals.value) null else files.value[id]?.uri?.toUri()
    fun storedBytes(): Long = files.value.values.sumOf { it.bytes }

    fun reportUnavailable() {
        error.value = context.getString(R.string.download_saved_file_unavailable)
    }

    suspend fun finishPending(download: Download) {
        if (download.request.id in pendingRemovals.value) return
        val target = preferences.getString(targetKey(download), null) ?: return
        move(download, target, fromCache = true)
    }

    suspend fun moveExisting(downloads: List<Download>, target: String) {
        withContext(Dispatchers.IO) {
            error.value = null
            busy.value = true
            try {
                for (download in downloads) {
                    if (download.state == Download.STATE_COMPLETED) move(download, target)
                }
            } finally {
                busy.value = false
            }
        }
    }

    private suspend fun move(download: Download, target: String, fromCache: Boolean = false) = withContext(Dispatchers.IO) {
        mutex.withLock {
            val id = download.request.id
            if (id in pendingRemovals.value) return@withLock
            val previous = files.value[id]
            var created: Uri? = null
            try {
                cleanupPartial(id)
                cleanupRetired(id)
                if ((!fromCache && previous?.location == target) || (previous == null && target == PHONE)) {
                    // A previous process may have committed its record before cleaning the staging cache.
                    if (previous != null) cache.removeResource(id)
                    check(preferences.edit().remove(targetKey(download)).commit())
                    return@withLock
                }
                val sourceRecord = previous.takeUnless { fromCache }
                val expected = sourceRecord?.bytes ?: download.contentLength.takeIf { it > 0 }
                    ?: download.bytesDownloaded
                require(expected > 0) { "Unknown audio length" }
                val title = database.getSongByIdBlocking(id)?.title ?: id
                val destination = openSource(download, sourceRecord, expected).buffered().use { input ->
                    input.mark(12)
                    val header = ByteArray(12)
                    var count = 0
                    while (count < header.size) {
                        val read = input.read(header, count, header.size - count)
                        if (read < 0) break
                        if (read == 0) throw IOException("Could not read audio header")
                        count += read
                    }
                    input.reset()
                    val mime = downloadedAudioMime(header.copyOf(count))
                    val name = downloadedAudioName(title, id, mime)
                    val destination = createDestination(target, name, mime)
                    created = destination
                    check(preferences.edit().putString("partial.$id", destination.toString()).commit())
                    requireNotNull(context.contentResolver.openOutputStream(destination, "wt")).use { output ->
                        copyDownloadedAudio(input, output, expected)
                    }
                    destination
                }
                // The original remains readable until the copy is closed and the new record is durable.
                val record = StoredDownload(destination.toString(), expected, target)
                val editor = preferences.edit().putString("file.$id", encode(record))
                    .remove("partial.$id").remove(targetKey(download))
                previous?.let { editor.putString("retired.$id", it.uri) }
                // SharedPreferences changes memory even when a disk commit returns false.
                // Keep the completed destination in that case; a later write may persist its URI.
                files.value = files.value + (id to record)
                created = null
                check(editor.commit())
                cache.removeResource(id)
                cleanupRetired(id)
            } catch (failure: Exception) {
                created?.let {
                    runCatching { deleteUri(it) }.onSuccess {
                        preferences.edit().remove("partial.$id").commit()
                    }
                }
                if (failure is kotlinx.coroutines.CancellationException) throw failure
                error.value = context.getString(R.string.download_location_failed)
            }
        }
    }

    private fun openSource(download: Download, previous: StoredDownload?, expected: Long): InputStream {
        if (previous != null) return requireNotNull(context.contentResolver.openInputStream(previous.uri.toUri()))
        val source = CacheDataSource.Factory().setCache(cache)
            .setUpstreamDataSourceFactory(null).setCacheWriteDataSinkFactory(null).createDataSource()
        return DataSourceInputStream(source, DataSpec.Builder()
            .setUri(download.request.uri).setKey(download.request.id).setLength(expected).build())
    }

    private fun createDestination(target: String, name: String, mime: String): Uri {
        if (target.startsWith("tree:")) {
            val tree = Uri.parse(target.removePrefix("tree:"))
            val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            return DocumentsContract.createDocument(context.contentResolver, parent, mime, name)
                ?: throw IOException("Could not create audio file")
        }
        val directory = if (target == PHONE) context.filesDir.resolve("offline_audio") else {
            val location = privateLocations().firstOrNull { it.id == target }
                ?: throw IOException("SD card is unavailable")
            File(location.id.removePrefix("private:")).resolve("Play")
        }
        check(directory.isDirectory || directory.mkdirs()) { "Storage is unavailable" }
        // Never overwrite an existing file, even if a previous operation left one behind.
        return File.createTempFile("play-", "-${name.takeLast(80)}", directory).toUri()
    }

    fun markForRemoval(ids: Collection<String>) {
        val editor = preferences.edit()
        ids.forEach { editor.putBoolean("removing.$it", true) }
        editor.apply()
        pendingRemovals.update { it + ids }
    }

    suspend fun retryPendingRemovals() {
        pendingRemovals.value.toList().forEach { remove(it) }
    }

    suspend fun recoverInterruptedTransfers() = withContext(Dispatchers.IO) {
        mutex.withLock {
            val ids = preferences.all.keys.filter { it.startsWith("partial.") || it.startsWith("retired.") }
                .map { it.substringAfter('.') }.toSet()
            ids.forEach { id ->
                try {
                    cleanupPartial(id)
                    cleanupRetired(id)
                } catch (failure: Exception) {
                    if (failure is kotlinx.coroutines.CancellationException) throw failure
                    error.value = context.getString(R.string.download_location_failed)
                }
            }
        }
    }

    fun pendingRemovalIds(): Set<String> = pendingRemovals.value

    suspend fun remove(id: String, download: Download? = null) = withContext(Dispatchers.IO) {
        mutex.withLock {
            try {
                cleanupPartial(id)
                cleanupRetired(id)
                files.value[id]?.let { deleteUri(it.uri.toUri()) }
                val editor = preferences.edit().remove("file.$id").remove("removing.$id")
                if (download != null) editor.remove(targetKey(download))
                check(editor.commit())
                files.value = files.value - id
                pendingRemovals.update { it - id }
            } catch (failure: Exception) {
                if (failure is kotlinx.coroutines.CancellationException) throw failure
                error.value = context.getString(R.string.download_delete_failed)
            }
        }
    }

    private fun cleanupPartial(id: String) {
        preferences.getString("partial.$id", null)?.let { deleteUri(it.toUri()) }
        check(preferences.edit().remove("partial.$id").commit())
    }

    private fun cleanupRetired(id: String) {
        preferences.getString("retired.$id", null)?.let { uri ->
            val replacement = files.value[id] ?: throw IOException("No saved replacement")
            requireNotNull(context.contentResolver.openFileDescriptor(replacement.uri.toUri(), "r")).use {
                if (it.statSize >= 0 && it.statSize != replacement.bytes) throw IOException("Incomplete replacement")
            }
            // Retry a previously failed metadata write before removing the only old copy.
            check(preferences.edit().putString("file.$id", encode(replacement)).commit())
            deleteUri(uri.toUri())
        }
        check(preferences.edit().remove("retired.$id").commit())
    }

    private fun deleteUri(uri: Uri) {
        if (uri.scheme == "file") {
            val file = File(requireNotNull(uri.path))
            if (!file.canonicalPath.startsWith(context.filesDir.canonicalPath + File.separator) &&
                Environment.getExternalStorageState(file) != Environment.MEDIA_MOUNTED) {
                throw IOException("Storage is unavailable")
            }
            if (file.exists() && !file.delete()) throw IOException("Could not delete audio file")
        } else {
            if (uri.authority == "com.android.externalstorage.documents") {
                val volumeId = DocumentsContract.getTreeDocumentId(uri).substringBefore(':')
                val volumes = context.getSystemService(StorageManager::class.java).storageVolumes
                val volume = volumes.firstOrNull {
                    if (volumeId.equals("primary", ignoreCase = true)) it.isPrimary
                    else it.uuid.equals(volumeId, ignoreCase = true)
                }
                if (volume?.state != Environment.MEDIA_MOUNTED) throw IOException("Storage is unavailable")
            }
            // A retry may refer to a document already removed before the process stopped.
            val exists = try {
                context.contentResolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)
                    ?.use { it.moveToFirst() } ?: throw IOException("Storage is unavailable")
            } catch (_: java.io.FileNotFoundException) { false }
            if (exists && !DocumentsContract.deleteDocument(context.contentResolver, uri)) {
                throw IOException("Could not delete audio document")
            }
        }
    }

    private fun loadFiles(): Map<String, StoredDownload> = preferences.all.mapNotNull { (key, value) ->
        if (!key.startsWith("file.")) null else runCatching {
            val json = JSONObject(value as String)
            key.removePrefix("file.") to StoredDownload(json.getString("uri"), json.getLong("bytes"), json.getString("location"))
        }.getOrNull()
    }.toMap()

    private fun encode(value: StoredDownload) = JSONObject().put("uri", value.uri)
        .put("bytes", value.bytes).put("location", value.location).toString()

    private fun targetKey(download: Download) = "target.${download.request.id}.${download.startTimeMs}"

    companion object { const val PHONE = "phone" }
}
