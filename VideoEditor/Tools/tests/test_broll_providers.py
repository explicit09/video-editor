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
            "duration": 2,
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
            "duration": 45,
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
