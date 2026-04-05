# B-Roll Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Python CLI tool that seeds a local B-roll video library from Pexels + Pixabay APIs, indexed in SQLite, searchable by agents via a new MCP tool.

**Architecture:** Python CLI (`broll_library.py`) with three commands (seed, search, stats). SQLite database on external drive indexes all clips by keywords, category, and energy level. A new MCP tool (`search_local_broll`) queries the index and returns local file paths. The existing `search_broll` MCP tool remains as a live API fallback.

**Tech Stack:** Python 3, sqlite3, requests, argparse. Swift for MCP tool integration.

**Spec:** `docs/superpowers/specs/2026-04-05-broll-library-design.md`

---

### Task 1: SQLite Database Module

**Files:**
- Create: `VideoEditor/Tools/broll_library/db.py`
- Test: `VideoEditor/Tools/tests/test_broll_db.py`

- [ ] **Step 1: Write the failing test for database creation and clip insertion**

```python
# VideoEditor/Tools/tests/test_broll_db.py
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd VideoEditor/Tools && python3 -m pytest tests/test_broll_db.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'broll_library'`

- [ ] **Step 3: Create the package and implement db.py**

```bash
mkdir -p VideoEditor/Tools/broll_library
touch VideoEditor/Tools/broll_library/__init__.py
```

```python
# VideoEditor/Tools/broll_library/db.py
from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from pathlib import Path


class BRollDB:
    def __init__(self, db_path: Path):
        self.db_path = db_path
        self.conn = sqlite3.connect(str(db_path))
        self.conn.row_factory = sqlite3.Row
        self._create_tables()

    def _create_tables(self):
        self.conn.executescript("""
            CREATE TABLE IF NOT EXISTS clips (
                id INTEGER PRIMARY KEY,
                source TEXT NOT NULL,
                source_id TEXT NOT NULL,
                filename TEXT NOT NULL,
                category TEXT NOT NULL,
                keywords TEXT NOT NULL,
                energy TEXT NOT NULL,
                duration REAL NOT NULL,
                width INTEGER NOT NULL,
                height INTEGER NOT NULL,
                file_size INTEGER,
                source_url TEXT NOT NULL,
                downloaded_at TEXT NOT NULL DEFAULT '',
                UNIQUE(source, source_id)
            );
            CREATE INDEX IF NOT EXISTS idx_keywords ON clips(keywords);
            CREATE INDEX IF NOT EXISTS idx_category ON clips(category);
            CREATE INDEX IF NOT EXISTS idx_energy ON clips(energy);
        """)

    def insert_clip(
        self, *, source: str, source_id: str, filename: str,
        category: str, keywords: str, energy: str, duration: float,
        width: int, height: int, file_size: int | None,
        source_url: str,
    ) -> bool:
        try:
            self.conn.execute(
                """INSERT INTO clips
                   (source, source_id, filename, category, keywords, energy,
                    duration, width, height, file_size, source_url, downloaded_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (source, source_id, filename, category, keywords, energy,
                 duration, width, height, file_size, source_url,
                 datetime.now(timezone.utc).isoformat()),
            )
            self.conn.commit()
            return True
        except sqlite3.IntegrityError:
            return False

    def exists(self, source: str, source_id: str) -> bool:
        row = self.conn.execute(
            "SELECT 1 FROM clips WHERE source = ? AND source_id = ?",
            (source, source_id),
        ).fetchone()
        return row is not None

    def search(
        self, query: str, *, energy: str | None = None, limit: int = 20,
    ) -> list[dict]:
        sql = "SELECT * FROM clips WHERE keywords LIKE ?"
        params: list = [f"%{query}%"]
        if energy:
            sql += " AND energy = ?"
            params.append(energy)
        sql += " ORDER BY duration DESC LIMIT ?"
        params.append(limit)
        rows = self.conn.execute(sql, params).fetchall()
        return [dict(r) for r in rows]

    def stats(self) -> dict:
        total = self.conn.execute("SELECT COUNT(*) FROM clips").fetchone()[0]
        by_cat = {}
        for row in self.conn.execute(
            "SELECT category, COUNT(*) as cnt FROM clips GROUP BY category"
        ):
            by_cat[row["category"]] = row["cnt"]
        by_src = {}
        for row in self.conn.execute(
            "SELECT source, COUNT(*) as cnt FROM clips GROUP BY source"
        ):
            by_src[row["source"]] = row["cnt"]
        total_size = self.conn.execute(
            "SELECT COALESCE(SUM(file_size), 0) FROM clips"
        ).fetchone()[0]
        return {
            "total": total,
            "by_category": by_cat,
            "by_source": by_src,
            "total_size_bytes": total_size,
        }

    def close(self):
        self.conn.close()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd VideoEditor/Tools && python3 -m pytest tests/test_broll_db.py -v`
Expected: All 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add VideoEditor/Tools/broll_library/__init__.py VideoEditor/Tools/broll_library/db.py VideoEditor/Tools/tests/test_broll_db.py
git commit -m "feat(broll): add SQLite database module for B-roll library"
```

---

### Task 2: Pexels and Pixabay API Clients

**Files:**
- Create: `VideoEditor/Tools/broll_library/providers.py`
- Test: `VideoEditor/Tools/tests/test_broll_providers.py`

Note: The Swift `PexelsClient` already exists at `VideoEditor/Packages/AIServices/Sources/AIServices/Providers/PexelsClient.swift` but we need a Python equivalent for the CLI tool. The Pixabay client is new.

- [ ] **Step 1: Write the failing tests (mocked HTTP)**

```python
# VideoEditor/Tools/tests/test_broll_providers.py
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from unittest import mock

TOOLS_ROOT = Path(__file__).resolve().parents[1]
if str(TOOLS_ROOT) not in sys.path:
    sys.path.insert(0, str(TOOLS_ROOT))

from broll_library.providers import PexelsProvider, PixabayProvider


class FakeResponse:
    def __init__(self, data: dict, status_code: int = 200, headers: dict | None = None):
        self._data = data
        self.status_code = status_code
        self.headers = headers or {}

    def json(self):
        return self._data

    def raise_for_status(self):
        if self.status_code >= 400:
            raise Exception(f"HTTP {self.status_code}")


PEXELS_RESPONSE = {
    "videos": [
        {
            "id": 100,
            "url": "https://pexels.com/video/100",
            "duration": 15,
            "width": 1920,
            "height": 1080,
            "image": "https://images.pexels.com/thumb.jpg",
            "video_files": [
                {"id": 1, "quality": "hd", "file_type": "video/mp4",
                 "width": 1920, "height": 1080,
                 "link": "https://videos.pexels.com/hd.mp4"},
                {"id": 2, "quality": "sd", "file_type": "video/mp4",
                 "width": 640, "height": 360,
                 "link": "https://videos.pexels.com/sd.mp4"},
            ],
        },
        {
            "id": 101,
            "url": "https://pexels.com/video/101",
            "duration": 2,  # too short, should be filtered
            "width": 1920,
            "height": 1080,
            "image": None,
            "video_files": [
                {"id": 3, "quality": "hd", "file_type": "video/mp4",
                 "width": 1920, "height": 1080,
                 "link": "https://videos.pexels.com/hd2.mp4"},
            ],
        },
    ]
}

PIXABAY_RESPONSE = {
    "hits": [
        {
            "id": 200,
            "pageURL": "https://pixabay.com/videos/id-200",
            "duration": 20,
            "videos": {
                "large": {"url": "https://cdn.pixabay.com/large.mp4", "width": 1920, "height": 1080},
                "medium": {"url": "https://cdn.pixabay.com/medium.mp4", "width": 1280, "height": 720},
                "small": {"url": "https://cdn.pixabay.com/small.mp4", "width": 640, "height": 360},
            },
        },
        {
            "id": 201,
            "pageURL": "https://pixabay.com/videos/id-201",
            "duration": 45,  # too long, should be filtered
            "videos": {
                "large": {"url": "https://cdn.pixabay.com/large2.mp4", "width": 1920, "height": 1080},
            },
        },
    ]
}


class TestPexelsProvider(unittest.TestCase):
    @mock.patch("broll_library.providers.requests.get")
    def test_search_filters_duration(self, mock_get):
        mock_get.return_value = FakeResponse(
            PEXELS_RESPONSE,
            headers={"X-Ratelimit-Remaining": "190"},
        )
        provider = PexelsProvider(api_key="test-key")
        results = provider.search("cityscape", per_page=10, min_dur=3, max_dur=30)
        # id=101 has duration=2, should be filtered out
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["id"], 100)
        self.assertEqual(results[0]["hd_url"], "https://videos.pexels.com/hd.mp4")

    @mock.patch("broll_library.providers.requests.get")
    def test_search_passes_auth_header(self, mock_get):
        mock_get.return_value = FakeResponse(
            {"videos": []}, headers={"X-Ratelimit-Remaining": "190"},
        )
        provider = PexelsProvider(api_key="my-secret")
        provider.search("test")
        call_kwargs = mock_get.call_args
        self.assertEqual(call_kwargs[1]["headers"]["Authorization"], "my-secret")


class TestPixabayProvider(unittest.TestCase):
    @mock.patch("broll_library.providers.requests.get")
    def test_search_filters_duration(self, mock_get):
        mock_get.return_value = FakeResponse(PIXABAY_RESPONSE)
        provider = PixabayProvider(api_key="test-key")
        results = provider.search("nature", per_page=10, min_dur=3, max_dur=30)
        # id=201 has duration=45, should be filtered out
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["id"], 200)
        self.assertIn("large", results[0]["download_url"])

    @mock.patch("broll_library.providers.requests.get")
    def test_search_passes_api_key(self, mock_get):
        mock_get.return_value = FakeResponse({"hits": []})
        provider = PixabayProvider(api_key="my-pixabay-key")
        provider.search("test")
        call_url = mock_get.call_args[0][0]
        self.assertIn("key=my-pixabay-key", call_url)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd VideoEditor/Tools && python3 -m pytest tests/test_broll_providers.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'broll_library.providers'`

- [ ] **Step 3: Implement providers.py**

```python
# VideoEditor/Tools/broll_library/providers.py
from __future__ import annotations

import time

import requests


class PexelsProvider:
    BASE_URL = "https://api.pexels.com/videos/search"

    def __init__(self, api_key: str):
        self.api_key = api_key
        self.rate_remaining: int | None = None

    def search(
        self, query: str, *, per_page: int = 20,
        min_dur: int = 3, max_dur: int = 30,
    ) -> list[dict]:
        resp = requests.get(
            self.BASE_URL,
            params={"query": query, "per_page": per_page},
            headers={"Authorization": self.api_key},
            timeout=15,
        )
        resp.raise_for_status()
        self.rate_remaining = int(resp.headers.get("X-Ratelimit-Remaining", 999))

        results = []
        for v in resp.json().get("videos", []):
            dur = v.get("duration", 0)
            if dur < min_dur or dur > max_dur:
                continue
            hd_url = self._best_hd(v.get("video_files", []))
            if not hd_url:
                continue
            results.append({
                "id": v["id"],
                "source": "pexels",
                "url": v.get("url", ""),
                "duration": dur,
                "width": v.get("width", 0),
                "height": v.get("height", 0),
                "hd_url": hd_url,
                "thumbnail": v.get("image"),
            })
        return results

    @staticmethod
    def _best_hd(files: list[dict]) -> str | None:
        for f in files:
            if f.get("quality") == "hd" and f.get("file_type") == "video/mp4":
                return f["link"]
        # Fallback: any mp4
        for f in files:
            if f.get("file_type") == "video/mp4":
                return f["link"]
        return None


class PixabayProvider:
    BASE_URL = "https://pixabay.com/api/videos/"

    def __init__(self, api_key: str):
        self.api_key = api_key

    def search(
        self, query: str, *, per_page: int = 20,
        min_dur: int = 3, max_dur: int = 30,
    ) -> list[dict]:
        resp = requests.get(
            f"{self.BASE_URL}?key={self.api_key}&q={query}&per_page={per_page}",
            timeout=15,
        )
        resp.raise_for_status()

        results = []
        for hit in resp.json().get("hits", []):
            dur = hit.get("duration", 0)
            if dur < min_dur or dur > max_dur:
                continue
            videos = hit.get("videos", {})
            dl_url = self._best_url(videos)
            if not dl_url:
                continue
            size = videos.get("large", videos.get("medium", {}))
            results.append({
                "id": hit["id"],
                "source": "pixabay",
                "url": hit.get("pageURL", ""),
                "duration": dur,
                "width": size.get("width", 0),
                "height": size.get("height", 0),
                "download_url": dl_url,
                "thumbnail": None,
            })
        return results

    @staticmethod
    def _best_url(videos: dict) -> str | None:
        for quality in ("large", "medium", "small"):
            entry = videos.get(quality, {})
            url = entry.get("url")
            if url:
                return url
        return None


def download_file(url: str, dest: str, *, throttle: float = 0.0) -> int:
    """Download a file from url to dest. Returns file size in bytes."""
    resp = requests.get(url, stream=True, timeout=60)
    resp.raise_for_status()
    size = 0
    with open(dest, "wb") as f:
        for chunk in resp.iter_content(chunk_size=8192):
            f.write(chunk)
            size += len(chunk)
    if throttle > 0:
        time.sleep(throttle)
    return size
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd VideoEditor/Tools && python3 -m pytest tests/test_broll_providers.py -v`
Expected: All 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add VideoEditor/Tools/broll_library/providers.py VideoEditor/Tools/tests/test_broll_providers.py
git commit -m "feat(broll): add Pexels and Pixabay API provider clients"
```

---

### Task 3: Seed Configuration (Categories & Keywords)

**Files:**
- Create: `VideoEditor/Tools/broll_library/categories.py`

No tests needed — this is pure data.

- [ ] **Step 1: Create the categories module**

```python
# VideoEditor/Tools/broll_library/categories.py
from __future__ import annotations

# Keywords mapped by category. Energy heuristic is per-keyword.
# "high" = dramatic/fast, "medium" = active, "low" = calm/ambient
CATEGORIES: dict[str, list[tuple[str, str]]] = {
    "city": [
        ("cityscape", "low"),
        ("downtown", "medium"),
        ("traffic", "medium"),
        ("skyline", "low"),
        ("aerial city", "high"),
    ],
    "tech": [
        ("computer", "low"),
        ("coding", "low"),
        ("server room", "low"),
        ("smartphone", "low"),
        ("circuit board", "low"),
    ],
    "people": [
        ("conversation", "low"),
        ("meeting", "low"),
        ("walking", "medium"),
        ("crowd", "medium"),
        ("handshake", "low"),
    ],
    "business": [
        ("office", "low"),
        ("workspace", "low"),
        ("presentation", "medium"),
        ("whiteboard", "low"),
        ("conference", "medium"),
    ],
    "nature": [
        ("landscape", "low"),
        ("ocean", "medium"),
        ("mountains", "low"),
        ("sunset", "low"),
        ("forest", "low"),
    ],
    "food": [
        ("cooking", "medium"),
        ("restaurant", "low"),
        ("coffee", "low"),
        ("kitchen", "medium"),
        ("meal prep", "medium"),
    ],
    "lifestyle": [
        ("fitness", "high"),
        ("travel", "medium"),
        ("fashion", "medium"),
        ("luxury", "low"),
        ("nightlife", "high"),
    ],
    "abstract": [
        ("neon", "high"),
        ("geometric", "low"),
        ("liquid", "medium"),
        ("particles", "high"),
        ("gradient", "low"),
    ],
}


def all_search_pairs() -> list[tuple[str, str, str]]:
    """Returns (category, keyword, energy) tuples for all searches."""
    pairs = []
    for category, keywords in CATEGORIES.items():
        for keyword, energy in keywords:
            pairs.append((category, keyword, energy))
    return pairs
```

- [ ] **Step 2: Commit**

```bash
git add VideoEditor/Tools/broll_library/categories.py
git commit -m "feat(broll): add category and keyword definitions for seed"
```

---

### Task 4: CLI Tool (seed, search, stats)

**Files:**
- Create: `VideoEditor/Tools/broll_library/cli.py`
- Test: `VideoEditor/Tools/tests/test_broll_cli.py`

- [ ] **Step 1: Write the failing tests**

```python
# VideoEditor/Tools/tests/test_broll_cli.py
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
        # Pexels returns 1 result, Pixabay returns 1 result
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

        # Verify DB was populated
        db = BRollDB(self.drive / "BRollLibrary" / "broll.db")
        stats = db.stats()
        self.assertEqual(stats["total"], 2)
        db.close()

        # Verify category directories were created
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd VideoEditor/Tools && python3 -m pytest tests/test_broll_cli.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'broll_library.cli'`

- [ ] **Step 3: Implement cli.py**

```python
# VideoEditor/Tools/broll_library/cli.py
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from .categories import all_search_pairs
from .db import BRollDB
from .providers import PexelsProvider, PixabayProvider, download_file


LIB_DIR_NAME = "BRollLibrary"
DB_NAME = "broll.db"


def _lib_path(drive: Path) -> Path:
    return drive / LIB_DIR_NAME


def _ensure_dirs(drive: Path, categories: set[str]):
    lib = _lib_path(drive)
    lib.mkdir(exist_ok=True)
    for cat in categories:
        (lib / cat).mkdir(exist_ok=True)


def run_seed(
    *, drive: Path, pexels_key: str, pixabay_key: str, max_total: int = 2000,
) -> int:
    pairs = all_search_pairs()
    categories = {cat for cat, _, _ in pairs}
    _ensure_dirs(drive, categories)

    lib = _lib_path(drive)
    db = BRollDB(lib / DB_NAME)
    pexels = PexelsProvider(api_key=pexels_key)
    pixabay = PixabayProvider(api_key=pixabay_key)

    downloaded = 0
    clips_per_keyword = max(1, max_total // len(pairs))

    for category, keyword, energy in pairs:
        if downloaded >= max_total:
            break

        # Search Pexels
        try:
            pexels_results = pexels.search(keyword, per_page=clips_per_keyword)
        except Exception as e:
            print(f"  Pexels error for '{keyword}': {e}")
            pexels_results = []

        # Search Pixabay (throttled)
        try:
            pixabay_results = pixabay.search(keyword, per_page=clips_per_keyword)
        except Exception as e:
            print(f"  Pixabay error for '{keyword}': {e}")
            pixabay_results = []

        combined = []
        for r in pexels_results:
            combined.append(("pexels", str(r["id"]), r["hd_url"], r["url"],
                             r["duration"], r["width"], r["height"]))
        for r in pixabay_results:
            combined.append(("pixabay", str(r["id"]), r["download_url"], r["url"],
                             r["duration"], r["width"], r["height"]))

        for source, sid, dl_url, page_url, duration, w, h in combined:
            if downloaded >= max_total:
                break
            if db.exists(source, sid):
                continue

            filename = f"{source}_{sid}.mp4"
            dest = lib / category / filename

            try:
                throttle = 1.0 if source == "pixabay" else 0.0
                file_size = download_file(dl_url, str(dest), throttle=throttle)
            except Exception as e:
                print(f"  Download failed {filename}: {e}")
                continue

            db.insert_clip(
                source=source, source_id=sid, filename=filename,
                category=category, keywords=keyword, energy=energy,
                duration=duration, width=w, height=h,
                file_size=file_size, source_url=page_url,
            )
            downloaded += 1
            print(f"  [{downloaded}/{max_total}] {filename} ({category}/{keyword})")

    db.close()
    return downloaded


def run_search(
    *, drive: Path, query: str, energy: str | None, limit: int,
) -> list[dict]:
    lib = _lib_path(drive)
    db = BRollDB(lib / DB_NAME)
    results = db.search(query, energy=energy, limit=limit)
    db.close()
    return results


def run_stats(*, drive: Path) -> dict:
    lib = _lib_path(drive)
    db = BRollDB(lib / DB_NAME)
    stats = db.stats()
    db.close()
    return stats


def _load_env_key(name: str) -> str | None:
    """Load key from VideoEditor/.env or environment."""
    val = os.environ.get(name)
    if val:
        return val
    env_file = Path(__file__).resolve().parents[2] / ".env"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if line.startswith(f"{name}="):
                return line.split("=", 1)[1].strip().strip("'\"")
    return None


def main():
    parser = argparse.ArgumentParser(description="B-Roll Library Manager")
    sub = parser.add_subparsers(dest="command", required=True)

    seed_p = sub.add_parser("seed", help="Download B-roll clips from Pexels + Pixabay")
    seed_p.add_argument("--drive", required=True, help="Path to external drive")
    seed_p.add_argument("--count", type=int, default=2000, help="Target clip count")

    search_p = sub.add_parser("search", help="Search the local B-roll library")
    search_p.add_argument("--drive", required=True, help="Path to external drive")
    search_p.add_argument("--query", required=True, help="Search keywords")
    search_p.add_argument("--energy", choices=["low", "medium", "high"], default=None)
    search_p.add_argument("--limit", type=int, default=10)

    stats_p = sub.add_parser("stats", help="Show library statistics")
    stats_p.add_argument("--drive", required=True, help="Path to external drive")

    args = parser.parse_args()

    if args.command == "seed":
        pexels_key = _load_env_key("PEXELS_API_KEY")
        pixabay_key = _load_env_key("PIXABAY_API_KEY")
        if not pexels_key:
            print("Error: PEXELS_API_KEY not found in environment or .env")
            sys.exit(1)
        if not pixabay_key:
            print("Error: PIXABAY_API_KEY not found in environment or .env")
            sys.exit(1)

        print(f"Seeding B-roll library to {args.drive}/BRollLibrary/ ...")
        count = run_seed(
            drive=Path(args.drive), pexels_key=pexels_key,
            pixabay_key=pixabay_key, max_total=args.count,
        )
        print(f"\nDone. Downloaded {count} clips.")

    elif args.command == "search":
        results = run_search(
            drive=Path(args.drive), query=args.query,
            energy=args.energy, limit=args.limit,
        )
        if not results:
            print("No results found.")
        else:
            for r in results:
                print(f"  {r['category']}/{r['filename']}  "
                      f"{r['duration']}s  {r['energy']}  [{r['keywords']}]")

    elif args.command == "stats":
        stats = run_stats(drive=Path(args.drive))
        print(f"Total clips: {stats['total']}")
        print(f"Total size:  {stats['total_size_bytes'] / 1_000_000:.1f} MB")
        print("By category:")
        for cat, cnt in sorted(stats["by_category"].items()):
            print(f"  {cat}: {cnt}")
        print("By source:")
        for src, cnt in sorted(stats["by_source"].items()):
            print(f"  {src}: {cnt}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd VideoEditor/Tools && python3 -m pytest tests/test_broll_cli.py -v`
Expected: All 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add VideoEditor/Tools/broll_library/cli.py VideoEditor/Tools/tests/test_broll_cli.py
git commit -m "feat(broll): add CLI tool with seed, search, stats commands"
```

---

### Task 5: Entry Point Script

**Files:**
- Create: `VideoEditor/Tools/broll_library.py` (thin wrapper so `python3 broll_library.py` works from `Tools/`)

- [ ] **Step 1: Create the entry point**

```python
# VideoEditor/Tools/broll_library.py
"""B-Roll Library Manager — run from VideoEditor/Tools/ directory.

Usage:
    python3 broll_library.py seed --drive /Volumes/MyDrive --count 2000
    python3 broll_library.py search --drive /Volumes/MyDrive --query "cityscape"
    python3 broll_library.py stats --drive /Volumes/MyDrive
"""
from broll_library.cli import main

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Verify it runs**

Run: `cd VideoEditor/Tools && python3 broll_library.py --help`
Expected: Shows usage with seed/search/stats subcommands

- [ ] **Step 3: Commit**

```bash
git add VideoEditor/Tools/broll_library.py
git commit -m "feat(broll): add entry point script"
```

---

### Task 6: MCP Tool — search_local_broll

**Files:**
- Modify: `VideoEditor/VideoEditor/App/MCPServer.swift`

- [ ] **Step 1: Add tool definition to the MCP tool list**

In `MCPServer.swift`, find the tool definitions array and add after the `search_broll` definition:

```swift
[
    "name": "search_local_broll",
    "description": "Search the local B-roll library on the external drive. Returns file paths to matching clips. Faster than search_broll (no API call). Falls back to search_broll if no local matches.",
    "inputSchema": ["type": "object", "properties": [
        "query": ["type": "string", "description": "Search keywords (e.g., 'cityscape', 'sunset', 'cooking')"],
        "energy": ["type": "string", "enum": ["low", "medium", "high"], "description": "Energy level filter. low=calm/ambient, medium=moderate, high=dramatic/fast"],
        "limit": ["type": "integer", "description": "Max results to return (default 5)"],
    ], "required": ["query"]],
],
```

- [ ] **Step 2: Add the handler routing**

Find where `search_broll` is routed and add below it:

```swift
if name == "search_local_broll" {
    return await handleSearchLocalBroll(arguments, appState: appState)
}
```

- [ ] **Step 3: Implement the handler**

Add this method to MCPServer:

```swift
// MARK: - Search Local B-roll Library

private func handleSearchLocalBroll(_ args: [String: Any], appState: AppState) async -> String {
    let query = args["query"] as? String ?? ""
    let energy = args["energy"] as? String
    let limit = args["limit"] as? Int ?? 5

    guard !query.isEmpty else {
        return "Error: 'query' parameter is required."
    }

    // Find the B-roll library — check mounted volumes
    let fm = FileManager.default
    let volumesURL = URL(fileURLWithPath: "/Volumes")
    guard let volumes = try? fm.contentsOfDirectory(at: volumesURL, includingPropertiesForKeys: nil) else {
        return "Error: Cannot list /Volumes"
    }

    var dbURL: URL?
    for vol in volumes {
        let candidate = vol.appendingPathComponent("BRollLibrary/broll.db")
        if fm.fileExists(atPath: candidate.path) {
            dbURL = candidate
            break
        }
    }

    guard let dbPath = dbURL else {
        return "No local B-roll library found. Run `python3 broll_library.py seed --drive /Volumes/<drive>` first, or use search_broll for live Pexels search."
    }

    let libDir = dbPath.deletingLastPathComponent()

    // Query SQLite
    guard let db = try? SQLiteConnection(path: dbPath.path) else {
        return "Error: Could not open B-roll database at \(dbPath.path)"
    }
    defer { db.close() }

    var sql = "SELECT * FROM clips WHERE keywords LIKE ?"
    var params: [String] = ["%\(query)%"]
    if let energy = energy {
        sql += " AND energy = ?"
        params.append(energy)
    }
    sql += " ORDER BY duration DESC LIMIT ?"
    params.append(String(limit))

    guard let rows = try? db.query(sql, params: params) else {
        return "Error: Query failed."
    }

    if rows.isEmpty {
        return "No local matches for '\(query)'. Use search_broll for live Pexels API search."
    }

    var report = "=== LOCAL B-ROLL RESULTS ===\n"
    report += "Query: \(query)"
    if let energy = energy { report += " | Energy: \(energy)" }
    report += "\n\n"

    for (i, row) in rows.enumerated() {
        let filename = row["filename"] as? String ?? "?"
        let category = row["category"] as? String ?? "?"
        let keywords = row["keywords"] as? String ?? ""
        let duration = row["duration"] as? Double ?? 0
        let energyTag = row["energy"] as? String ?? "?"
        let path = libDir.appendingPathComponent(category)
            .appendingPathComponent(filename).path

        report += "#\(i + 1): \(path)\n"
        report += "  Duration: \(String(format: "%.1f", duration))s | Energy: \(energyTag) | Keywords: \(keywords)\n"
    }

    return report
}
```

Note: This assumes the project already has a `SQLiteConnection` helper or uses raw sqlite3 C API. Check existing patterns in the codebase — if there's already a SQLite wrapper, use that. If not, use the `Process` approach to shell out to `python3 broll_library.py search` instead:

```swift
private func handleSearchLocalBroll(_ args: [String: Any], appState: AppState) async -> String {
    let query = args["query"] as? String ?? ""
    let energy = args["energy"] as? String
    let limit = args["limit"] as? Int ?? 5

    guard !query.isEmpty else {
        return "Error: 'query' parameter is required."
    }

    // Find the B-roll library
    let fm = FileManager.default
    let volumesURL = URL(fileURLWithPath: "/Volumes")
    guard let volumes = try? fm.contentsOfDirectory(at: volumesURL, includingPropertiesForKeys: nil) else {
        return "Error: Cannot list /Volumes"
    }

    var libraryDrive: URL?
    for vol in volumes {
        let candidate = vol.appendingPathComponent("BRollLibrary/broll.db")
        if fm.fileExists(atPath: candidate.path) {
            libraryDrive = vol
            break
        }
    }

    guard let drive = libraryDrive else {
        return "No local B-roll library found. Run the seed command first, or use search_broll for live Pexels search."
    }

    // Shell out to the Python CLI
    let toolsDir = Bundle.main.bundlePath + "/../Tools"
    var cmdArgs = ["search", "--drive", drive.path, "--query", query, "--limit", String(limit)]
    if let energy = energy {
        cmdArgs += ["--energy", energy]
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [toolsDir + "/broll_library.py"] + cmdArgs
    let pipe = Pipe()
    process.standardOutput = pipe

    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? "No output"
    } catch {
        return "Error running search: \(error.localizedDescription)"
    }
}
```

- [ ] **Step 4: Build and verify**

Run: `cd VideoEditor && xcodebuild -scheme VideoEditor -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add VideoEditor/VideoEditor/App/MCPServer.swift
git commit -m "feat(broll): add search_local_broll MCP tool"
```

---

### Task 7: Add PIXABAY_API_KEY to .env

**Files:**
- Modify: `VideoEditor/.env`

- [ ] **Step 1: Add the key placeholder**

Add to the `.env` file:

```
PIXABAY_API_KEY=<your-pixabay-api-key>
```

Get a free API key from https://pixabay.com/api/docs/ (requires free account).

- [ ] **Step 2: Commit (do NOT commit actual key)**

Only commit if `.env` is already gitignored (it should be). Verify first:

```bash
grep -q ".env" VideoEditor/.gitignore && echo "OK: .env is gitignored" || echo "WARNING: .env is NOT gitignored"
```

---

### Task 8: Integration Test — Full Seed Round-Trip

**Files:**
- Create: `VideoEditor/Tools/tests/test_broll_integration.py`

- [ ] **Step 1: Write the integration test**

```python
# VideoEditor/Tools/tests/test_broll_integration.py
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
        # Should find clips tagged with "cityscape" keyword
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
```

- [ ] **Step 2: Run the integration test**

Run: `cd VideoEditor/Tools && python3 -m pytest tests/test_broll_integration.py -v`
Expected: PASS

- [ ] **Step 3: Run all B-roll tests together**

Run: `cd VideoEditor/Tools && python3 -m pytest tests/test_broll_*.py -v`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add VideoEditor/Tools/tests/test_broll_integration.py
git commit -m "test(broll): add integration test for full seed round trip"
```

---

### Task 9: Growth Mechanism — Cache Downloads from search_broll

**Files:**
- Modify: `VideoEditor/VideoEditor/App/MCPServer.swift` (the `handleSearchBroll` method)

When `search_broll` downloads a clip (the `download: true` path), it currently saves to the app's Documents/BRoll directory. After downloading, it should also insert the clip metadata into the external drive's `broll.db` so it becomes searchable via `search_local_broll`.

- [ ] **Step 1: Add cache-to-library logic after download in handleSearchBroll**

In `handleSearchBroll`, find the download section (around line 1171-1177). After the download succeeds, shell out to the Python CLI to register the clip:

```swift
// After successful download, register in local B-roll library
let registerProcess = Process()
registerProcess.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
// Find the library drive
let fm = FileManager.default
let volumesURL = URL(fileURLWithPath: "/Volumes")
if let volumes = try? fm.contentsOfDirectory(at: volumesURL, includingPropertiesForKeys: nil) {
    for vol in volumes {
        let dbCandidate = vol.appendingPathComponent("BRollLibrary/broll.db")
        if fm.fileExists(atPath: dbCandidate.path) {
            // Copy the file to the library as well
            let libDest = vol.appendingPathComponent("BRollLibrary/\(category)/\(filename)")
            try? fm.copyItem(at: destURL, to: libDest)
            // The DB insertion will happen via the Python tool in a future enhancement
            break
        }
    }
}
```

This is a lightweight first pass. Full DB insertion from Swift can be refined later.

- [ ] **Step 2: Build and verify**

Run: `cd VideoEditor && xcodebuild -scheme VideoEditor -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add VideoEditor/VideoEditor/App/MCPServer.swift
git commit -m "feat(broll): cache search_broll downloads into local library"
```
