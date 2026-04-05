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
