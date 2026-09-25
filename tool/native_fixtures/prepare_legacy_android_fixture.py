"""Adapt the fixture driver (not native models) to Android SDK 0.3.2 APIs."""
from pathlib import Path
import sys

source = Path(__file__).with_name("NativeFixturesTest.kt").read_text()
replacements = {
    "ResolveReason.RESOLVE_REASON_MATCH, true)": "ResolveReason.RESOLVE_REASON_MATCH)",
    "import io.mockk.every": "import org.mockito.kotlin.whenever",
    "import io.mockk.mockk": "import org.mockito.kotlin.mock",
    "mockk<Context>()": "mock<Context>()",
    'every { androidContext.getDir("events", Context.MODE_PRIVATE) } returns eventDirectory':
        'whenever(androidContext.getDir("events", Context.MODE_PRIVATE)).thenReturn(eventDirectory)',
    'val storage = FileDiskStorage(File(output, "flags.json"), File(output, "apply.json"))':
        'val cacheContext = mock<Context>()\n'
        '        whenever(cacheContext.filesDir).thenReturn(output)\n'
        '        val storage = FileDiskStorage.create(cacheContext)',
    "assertEquals(apply, storage.readApplyData())":
        'assertEquals(apply, storage.readApplyData())\n'
        '        File(output, "confidence_flags_cache.json").renameTo(File(output, "flags.json"))\n'
        '        File(output, "confidence_apply_cache.json").renameTo(File(output, "apply.json"))',
}
for old, new in replacements.items():
    if old not in source:
        raise ValueError("Fixture driver changed; review the compatibility adapter")
    source = source.replace(old, new)
target = Path(sys.argv[1]) / "Confidence/src/test/java/com/spotify/confidence/NativeFixturesTest.kt"
target.write_text(source)
