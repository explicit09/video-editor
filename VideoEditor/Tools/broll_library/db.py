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
