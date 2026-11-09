package com.nikhil.yt.playback

import android.content.Context
import android.net.Uri
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.TransferListener

/** Bypass both streaming caches for relocated audio; retain the existing streaming path otherwise. */
class StoredDownloadDataSource(
    private val storage: DownloadStorage,
    private val localFactory: DataSource.Factory,
    private val streamingFactory: DataSource.Factory,
) : DataSource {
    private var source: DataSource? = null
    private val listeners = mutableListOf<TransferListener>()
    override fun addTransferListener(listener: TransferListener) {
        listeners += listener
        source?.addTransferListener(listener)
    }
    override fun open(dataSpec: DataSpec): Long {
        val uri = storage.uriFor(dataSpec.key)
        if (uri != null) {
            val local = localFactory.createDataSource()
            listeners.forEach(local::addTransferListener)
            source = local
            try {
                return local.open(dataSpec.withUri(uri))
            } catch (failure: Exception) {
                runCatching { local.close() }
                storage.reportUnavailable()
                // A removed SD card or revoked folder permission must not break online playback.
            }
        }
        val streaming = streamingFactory.createDataSource()
        listeners.forEach(streaming::addTransferListener)
        source = streaming
        return streaming.open(dataSpec)
    }
    override fun read(buffer: ByteArray, offset: Int, length: Int): Int =
        checkNotNull(source).read(buffer, offset, length)
    override fun getUri(): Uri? = source?.uri
    override fun getResponseHeaders(): Map<String, List<String>> = source?.responseHeaders ?: emptyMap()
    override fun close() {
        try { source?.close() } finally { source = null }
    }

    class Factory(context: Context, private val storage: DownloadStorage, private val streaming: DataSource.Factory) : DataSource.Factory {
        private val local = DefaultDataSource.Factory(context)
        override fun createDataSource(): DataSource = StoredDownloadDataSource(storage, local, streaming)
    }
}
