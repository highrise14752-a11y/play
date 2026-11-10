package com.nikhil.yt.playback

import androidx.media3.datasource.DataSource
import dagger.Lazy
import org.junit.Assert.assertNull
import org.junit.Test

class StoredDownloadInitializationTest {
    @Test fun preparingADataSourceDoesNotLoadTheStorageIndex() {
        val index = Lazy<DownloadStorage> { error("Disk index loaded during data-source construction") }
        val unopened = DataSource.Factory { error("Data source opened before playback") }
        val source = StoredDownloadDataSource(index, unopened, unopened)
        assertNull(source.uri)
        source.close()
    }
}
