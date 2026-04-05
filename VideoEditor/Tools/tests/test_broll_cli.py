from __future__ import annotations

import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

TOOLS_ROOT = Path(__file__).resolve().parents[1]
if str(TOOLS_ROOT) not in sys.path:
    sys.path.insert(0, str(TOOLS_ROOT))

from broll_library.cli import run_seed, run_search, run_stats
from broll_library.db import BRollDB


class TestCLISeed(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.drive = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    @mock.patch("broll_library.cli.download_file", return_value=5000000)
    @mock.patch("broll_library.cli.PixabayProvider")
    @mock.patch("broll_library.cli.PexelsProvider")
    def test_seed_downloads_and_indexes(self, MockPexels, MockPixabay, mock_dl):
        MockPexels.return_value.search.return_value = [
            {"id": 1, "source": "pexels", "url": "https://pexels.com/1",
             "duration": 10, "width": 1920, "height": 1080,
             "hd_url": "https://videos.pexels.com/1.mp4", "thumbnail": None},
        ]
        MockPexels.return_value.rate_remaining = 190
        MockPixabay.return_value.search.return_value = [
            {"id": 2, "source": "pixabay", "url": "https://pixabay.com/2",
             "duration": 8, "width": 1920, "height": 1080,
             "download_url": "https://cdn.pixabay.com/2.mp4", "thumbnail": None},
        ]

        count = run_seed(
            drive=self.drive,
            pexels_key="pk",
            pixabay_key="xk",
            max_total=5,
        )
        self.assertEqual(count, 2)

        db = BRollDB(self.drive / "BRollLibrary" / "broll.db")
        stats = db.stats()
        self.assertEqual(stats["total"], 2)
        db.close()

        self.assertTrue((self.drive / "BRollLibrary").is_dir())


class TestCLISearch(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.drive = Path(self.tmp.name)
        lib_dir = self.drive / "BRollLibrary"
        lib_dir.mkdir()
        self.db = BRollDB(lib_dir / "broll.db")
        self.db.insert_clip(
            source="pexels", source_id="10", filename="pexels_10.mp4",
            category="city", keywords="cityscape,skyline", energy="low",
            duration=10.0, width=1920, height=1080,
            file_size=5000000, source_url="https://example.com/10",
        )

    def tearDown(self):
        self.db.close()
        self.tmp.cleanup()

    def test_search_returns_results(self):
        results = run_search(drive=self.drive, query="cityscape", energy=None, limit=10)
        self.assertEqual(len(results), 1)
        self.assertIn("pexels_10.mp4", results[0]["filename"])


class TestCLIStats(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.drive = Path(self.tmp.name)
        lib_dir = self.drive / "BRollLibrary"
        lib_dir.mkdir()
        self.db = BRollDB(lib_dir / "broll.db")
        self.db.insert_clip(
            source="pexels", source_id="1", filename="a.mp4",
            category="city", keywords="skyline", energy="low",
            duration=10.0, width=1920, height=1080,
            file_size=5000000, source_url="https://example.com/1",
        )

    def tearDown(self):
        self.db.close()
        self.tmp.cleanup()

    def test_stats_returns_dict(self):
        stats = run_stats(drive=self.drive)
        self.assertEqual(stats["total"], 1)


if __name__ == "__main__":
    unittest.main()
