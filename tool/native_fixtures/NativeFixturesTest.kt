package com.spotify.confidence

import android.content.Context
import com.spotify.confidence.apply.ApplyInstance
import com.spotify.confidence.apply.EventStatus
import com.spotify.confidence.cache.FileDiskStorage
import com.spotify.confidence.client.ResolvedFlag
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File
import java.util.Date

// Run in the pinned Android SDK's test source set. Uses its actual serializers
// and storage implementation; Context is mocked only for the event directory.
class NativeFixturesTest {
    @Test
    fun generate(): Unit = runBlocking {
        val output = File(requireNotNull(System.getenv("CONFIDENCE_FIXTURE_OUTPUT")))
        output.mkdirs()
        val time = Date(1700000000000)
        val context = mapOf(
            "visitor_id" to ConfidenceValue.String("fixture-visitor"),
            "targeting_key" to ConfidenceValue.String("user-a")
        )
        val values = mapOf(
            "enabled" to ConfidenceValue.Boolean(true),
            "count" to ConfidenceValue.Integer(7),
            "ratio" to ConfidenceValue.Double(0.5),
            "label" to ConfidenceValue.String("hello\nworld"),
            "optional" to ConfidenceValue.Null,
            "nested" to ConfidenceValue.Struct(mapOf("items" to ConfidenceValue.integerList(listOf(1, 2)))),
            "timestamp" to ConfidenceValue.Timestamp(time)
        )
        val flags = FlagResolution(
            context,
            listOf(ResolvedFlag("example", "flags/example/variants/on", values, ResolveReason.RESOLVE_REASON_MATCH, true)),
            "fixture-token"
        )
        val storage = FileDiskStorage(File(output, "flags.json"), File(output, "apply.json"))
        storage.store(flags)
        assertEquals(flags, storage.read())
        val apply = mutableMapOf("fixture-token" to mutableMapOf(
            "created" to ApplyInstance(time, EventStatus.CREATED),
            "sending" to ApplyInstance(time, EventStatus.SENDING),
            "sent" to ApplyInstance(time, EventStatus.SENT)
        ))
        storage.writeApplyData(apply)
        assertEquals(apply, storage.readApplyData())

        val eventDirectory = kotlin.io.path.createTempDirectory("confidence-fixture-events").toFile()
        val androidContext = mockk<Context>()
        every { androidContext.getDir("events", Context.MODE_PRIVATE) } returns eventDirectory
        val events = EventStorageImpl(androidContext)
        val event = EngineEvent("checkout", time, context + values)
        try {
            events.writeEvent(event)
            events.rollover()
            val ready = events.batchReadyFiles().single()
            assertEquals(listOf(event), events.eventsFor(ready))
            ready.copyTo(File(output, "events.ready"), overwrite = true)
            events.writeEvent(event)
            val unfinished = eventDirectory.listFiles()!!.single { !it.name.endsWith(".ready") }
            assertEquals(listOf(event), events.eventsFor(unfinished))
            unfinished.copyTo(File(output, "events-unfinished"), overwrite = true)
        } finally {
            events.stop()
        }
    }
}
