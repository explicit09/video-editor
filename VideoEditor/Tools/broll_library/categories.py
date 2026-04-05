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
