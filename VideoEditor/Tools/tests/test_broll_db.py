from __future__ import annotations

import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS_ROOT = Path(__file__).resolve().parents[1]
if str(TOOLS_ROOT) not in sys.path:
    sys.path.insert(0, str(TOOLS_ROOT))

from broll_library.db import BRollDB


class TestBRollDB(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmp.name) / "broll.db"
        self.db = BRollDB(self.db_path)

    def tearDown(self):
        self.db.close()
        self.tmp.cleanup()

    def test_insert_and_retrieve(self):
        self.db.insert_clip(
            source="pexels",
            source_id="12345",
            filename="pexels_12345.mp4",
            category="city",
            keywords="cityscape,downtown",
            energy="low",
            duration=10.5,
            width=1920,
            height=1080,
            file_size=5000000,
            source_url="https://pexels.com/video/12345",
        )
        results = self.db.search("cityscape")
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["source_id"], "12345")
        self.assertEqual(results[0]["energy"], "low")

    def test_search_by_energy(self):
        self.db.insert_clip(
            source="pexels", source_id="1", filename="a.mp4",
            category="city", keywords="skyline", energy="high",
            duration=8.0, width=1920, height=1080,
            file_size=3000000, source_url="https://example.com/1",
        )
        self.db.insert_clip(
            source="pixabay", source_id="2", filename="b.mp4",
            category="city", keywords="skyline", energy="low",
            duration=12.0, width=1920, height=1080,
            file_size=4000000, source_url="https://example.com/2",
        )
        high = self.db.search("skyline", energy="high")
        self.assertEqual(len(high), 1)
        self.assertEqual(high[0]["source"], "pexels")

    def test_duplicate_rejected(self):
        kwargs = dict(
            source="pexels", source_id="99", filename="x.mp4",
            category="nature", keywords="forest", energy="low",
            duration=5.0, width=1920, height=1080,
            file_size=2000000, source_url="https://example.com/99",
        )
        self.db.insert_clip(**kwargs)
        self.db.insert_clip(**kwargs)  # should not raise, just skip
        results = self.db.search("forest")
        self.assertEqual(len(results), 1)

    def test_exists(self):
        self.db.insert_clip(
            source="pexels", source_id="55", filename="y.mp4",
            category="tech", keywords="computer", energy="medium",
            duration=7.0, width=1920, height=1080,
            file_size=3000000, source_url="https://example.com/55",
        )
        self.assertTrue(self.db.exists("pexels", "55"))
        self.assertFalse(self.db.exists("pexels", "999"))

    def test_stats(self):
        self.db.insert_clip(
            source="pexels", source_id="1", filename="a.mp4",
            category="city", keywords="skyline", energy="high",
            duration=8.0, width=1920, height=1080,
            file_size=3000000, source_url="https://example.com/1",
        )
        self.db.insert_clip(
            source="pixabay", source_id="2", filename="b.mp4",
            category="nature", keywords="forest", energy="low",
            duration=12.0, width=1920, height=1080,
            file_size=4000000, source_url="https://example.com/2",
        )
        stats = self.db.stats()
        self.assertEqual(stats["total"], 2)
        self.assertEqual(stats["by_category"]["city"], 1)
        self.assertEqual(stats["by_source"]["pexels"], 1)


if __name__ == "__main__":
    unittest.main()
