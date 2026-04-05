"""Integration test — runs seed with mocked HTTP, verifies full round trip."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

TOOLS_ROOT = Path(__file__).resolve().parents[1]
if str(TOOLS_ROOT) not in sys.path:
    sys.path.insert(0, str(TOOLS_ROOT))

from broll_library.cli import run_seed, run_search, run_stats


def _fake_download(url: str, dest: str, *, throttle: float = 0.0) -> int:
    """Write a tiny fake file instead of downloading."""
    Path(dest).write_bytes(b"\x00" * 1024)
    return 1024


class TestFullRoundTrip(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.drive = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    @mock.patch("broll_library.cli.download_file", side_effect=_fake_download)
    @mock.patch("broll_library.cli.PixabayProvider")
    @mock.patch("broll_library.cli.PexelsProvider")
    def test_seed_search_stats(self, MockPexels, MockPixabay, _mock_dl):
        MockPexels.return_value.search.return_value = [
            {"id": i, "source": "pexels", "url": f"https://pexels.com/{i}",
             "duration": 10, "width": 1920, "height": 1080,
             "hd_url": f"https://videos.pexels.com/{i}.mp4", "thumbnail": None}
            for i in range(3)
        ]
        MockPexels.return_value.rate_remaining = 190
        MockPixabay.return_value.search.return_value = [
            {"id": i + 100, "source": "pixabay", "url": f"https://pixabay.com/{i}",
             "duration": 12, "width": 1920, "height": 1080,
             "download_url": f"https://cdn.pixabay.com/{i}.mp4", "thumbnail": None}
            for i in range(3)
        ]

        # Seed
        count = run_seed(
            drive=self.drive, pexels_key="pk", pixabay_key="xk", max_total=10,
        )
        self.assertGreater(count, 0)

        # Search
        results = run_search(drive=self.drive, query="cityscape", energy=None, limit=5)
        for r in results:
            self.assertIn("cityscape", r["keywords"])

        # Stats
        stats = run_stats(drive=self.drive)
        self.assertEqual(stats["total"], count)
        self.assertGreater(stats["total_size_bytes"], 0)

        # Verify files exist on disk
        lib = self.drive / "BRollLibrary"
        mp4s = list(lib.rglob("*.mp4"))
        self.assertEqual(len(mp4s), count)


if __name__ == "__main__":
    unittest.main()
