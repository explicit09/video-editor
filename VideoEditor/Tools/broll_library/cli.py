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
    *, drive: Path, pexels_key: str, pixabay_key: str | None = None, max_total: int = 2000,
) -> int:
    pairs = all_search_pairs()
    categories = {cat for cat, _, _ in pairs}
    _ensure_dirs(drive, categories)

    lib = _lib_path(drive)
    db = BRollDB(lib / DB_NAME)
    pexels = PexelsProvider(api_key=pexels_key)
    pixabay = PixabayProvider(api_key=pixabay_key) if pixabay_key else None

    downloaded = 0
    clips_per_keyword = max(1, max_total // len(pairs))

    for category, keyword, energy in pairs:
        if downloaded >= max_total:
            break

        try:
            pexels_results = pexels.search(keyword, per_page=clips_per_keyword)
        except Exception as e:
            print(f"  Pexels error for '{keyword}': {e}")
            pexels_results = []

        if pixabay:
            try:
                pixabay_results = pixabay.search(keyword, per_page=clips_per_keyword)
            except Exception as e:
                print(f"  Pixabay error for '{keyword}': {e}")
                pixabay_results = []
        else:
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
            print("Warning: PIXABAY_API_KEY not found — seeding from Pexels only.")

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
