#!/usr/bin/env python3
"""Fetch YouTube video transcripts for training the editor's AI features.

Usage:
    python3 fetch_transcripts.py <url_or_id> [<url_or_id> ...]
    python3 fetch_transcripts.py --file urls.txt

Outputs JSON (with timestamps) and plain text files into the transcripts/ directory
alongside this script.
"""

import argparse
import json
import os
import re
import sys

from youtube_transcript_api import YouTubeTranscriptApi


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "transcripts")


def extract_video_id(url_or_id: str) -> str:
    """Extract video ID from a YouTube URL or return as-is if already an ID."""
    patterns = [
        r"(?:youtu\.be/)([a-zA-Z0-9_-]{11})",
        r"(?:youtube\.com/watch\?.*v=)([a-zA-Z0-9_-]{11})",
        r"(?:youtube\.com/embed/)([a-zA-Z0-9_-]{11})",
        r"(?:youtube\.com/shorts/)([a-zA-Z0-9_-]{11})",
    ]
    for pattern in patterns:
        match = re.search(pattern, url_or_id)
        if match:
            return match.group(1)
    # Assume it's already a video ID
    if re.match(r"^[a-zA-Z0-9_-]{11}$", url_or_id.strip()):
        return url_or_id.strip()
    raise ValueError(f"Cannot extract video ID from: {url_or_id}")


def fetch_transcript(api: YouTubeTranscriptApi, video_id: str) -> list[dict]:
    """Fetch transcript and return as list of dicts."""
    transcript = api.fetch(video_id)
    return [{"text": s.text, "start": s.start, "duration": s.duration} for s in transcript]


def save_transcript(video_id: str, entries: list[dict]) -> None:
    """Save transcript as JSON and plain text."""
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    with open(os.path.join(OUTPUT_DIR, f"{video_id}.json"), "w") as f:
        json.dump(entries, f, indent=2)

    text = "\n".join(e["text"] for e in entries)
    with open(os.path.join(OUTPUT_DIR, f"{video_id}.txt"), "w") as f:
        f.write(text)


def main():
    parser = argparse.ArgumentParser(description="Fetch YouTube transcripts")
    parser.add_argument("urls", nargs="*", help="YouTube URLs or video IDs")
    parser.add_argument("--file", "-f", help="File containing URLs, one per line")
    args = parser.parse_args()

    urls = list(args.urls)
    if args.file:
        with open(args.file) as f:
            urls.extend(line.strip() for line in f if line.strip() and not line.startswith("#"))

    if not urls:
        parser.print_help()
        sys.exit(1)

    api = YouTubeTranscriptApi()
    results = {"ok": 0, "failed": 0}

    for url in urls:
        try:
            video_id = extract_video_id(url)
        except ValueError as e:
            print(f"SKIP: {e}")
            results["failed"] += 1
            continue

        print(f"Fetching {video_id}...", end=" ", flush=True)
        try:
            entries = fetch_transcript(api, video_id)
            save_transcript(video_id, entries)
            duration = entries[-1]["start"] + entries[-1]["duration"] if entries else 0
            print(f"OK ({len(entries)} segments, ~{int(duration // 60)}m{int(duration % 60)}s)")
            results["ok"] += 1
        except Exception as e:
            print(f"FAILED: {e}")
            results["failed"] += 1

    print(f"\nDone: {results['ok']} succeeded, {results['failed']} failed")
    print(f"Output: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
