# B-Roll Library — Design Spec

## Purpose

Build a local B-roll video library on an external drive that AI agents can search when auto-editing podcasts and shorts. Agents need instant access to relevant clips without hitting external APIs mid-edit.

## Sources

Two providers, both free for commercial use with no attribution required:

- **Pexels API** — 200 requests/hour, 80 results/page. Already integrated in the editor via `search_broll`.
- **Pixabay API** — 100 requests/minute. Throttle to 1 download/second; no systematic mass downloads per their terms.

## Storage

External hard drive:

```
/Volumes/<drive>/BRollLibrary/
├── broll.db              # SQLite metadata index
├── city/
├── tech/
├── people/
├── business/
├── nature/
├── food/
├── lifestyle/
└── abstract/
```

## Categories & Keywords

One unified set of categories. Clips are tagged by energy level (`low`, `medium`, `high`) rather than separated by use case (podcast vs shorts), since shorts are cut from podcasts — same topics, different energy.

| Category  | Keywords                                              |
|-----------|-------------------------------------------------------|
| city      | cityscape, downtown, traffic, skyline, aerial city    |
| tech      | computer, coding, server room, smartphone, circuit board |
| people    | conversation, meeting, walking, crowd, handshake      |
| business  | office, workspace, presentation, whiteboard, conference |
| nature    | landscape, ocean, mountains, sunset, forest           |
| food      | cooking, restaurant, coffee, kitchen, meal prep       |
| lifestyle | fitness, travel, fashion, luxury, nightlife           |
| abstract  | neon, geometric, liquid, particles, gradient          |

Each keyword pulls ~15-20 clips across both APIs → ~2000 total for the seed.

## Energy Tagging

Each clip gets an energy tag in the metadata:

- **low** — calm, slow, ambient (cityscapes, sunsets, offices)
- **medium** — moderate activity (people walking, cooking, meetings)
- **high** — fast, dramatic, attention-grabbing (extreme sports, explosions, fast timelapses)

Initial energy assignment is heuristic — based on the search keyword and source metadata. AI-based re-tagging is a future enhancement.

## CLI Tool

`VideoEditor/Tools/broll_library.py` with three commands:

### `seed`

```bash
python3 broll_library.py seed --drive /Volumes/<drive> --count 2000
```

1. Iterates category × keyword pairs
2. Searches Pexels first, then Pixabay for the same keyword
3. Downloads HD (1080p) — not 4K
4. Saves to `<drive>/BRollLibrary/<category>/`
5. Filename: `<source>_<id>.mp4` (e.g., `pexels_28374.mp4`)
6. Inserts into `broll.db`: keywords, category, energy, resolution, duration, source URL, source provider
7. Throttles: 1 request/second for Pixabay, respects Pexels `X-Ratelimit-Remaining` headers
8. Skips clips < 3s or > 30s
9. De-dupes across providers by comparing duration + resolution
10. Shows progress bar, can resume if interrupted (skips already-downloaded IDs)

### `search`

```bash
python3 broll_library.py search --query "cityscape" --energy high
```

Queries the SQLite index by keyword (LIKE match against comma-separated keywords field) and/or energy level. Returns local file paths with metadata as JSON.

### `stats`

```bash
python3 broll_library.py stats
```

Shows clip count by category, total disk usage, source breakdown.

## SQLite Schema

```sql
CREATE TABLE clips (
    id INTEGER PRIMARY KEY,
    source TEXT NOT NULL,         -- 'pexels' or 'pixabay'
    source_id TEXT NOT NULL,      -- ID from the provider
    filename TEXT NOT NULL,
    category TEXT NOT NULL,
    keywords TEXT NOT NULL,       -- comma-separated
    energy TEXT NOT NULL,         -- 'low', 'medium', 'high'
    duration REAL NOT NULL,
    width INTEGER NOT NULL,
    height INTEGER NOT NULL,
    file_size INTEGER,
    source_url TEXT NOT NULL,
    downloaded_at TEXT NOT NULL,
    UNIQUE(source, source_id)
);

CREATE INDEX idx_keywords ON clips(keywords);
CREATE INDEX idx_category ON clips(category);
CREATE INDEX idx_energy ON clips(energy);
```

## MCP Integration

One new MCP tool: **`search_local_broll`**

```
Input:  { query: "city skyline", energy: "high", limit: 5 }
Output: [ { path: "/Volumes/.../city/pexels_28374.mp4", duration: 12.3, keywords: [...] }, ... ]
```

### Agent Workflow

1. Agent calls `search_local_broll` first (local, instant)
2. If no good matches, falls back to `search_broll` (Pexels live API) with download enabled
3. Downloaded clip is automatically added to the local library (cache-and-grow)

The existing `search_broll` tool stays unchanged as the live fallback.

## Growth Mechanism

The library grows organically:

- Every `search_broll` API call that downloads a clip also inserts it into the local index
- Over time, frequently-needed categories fill up and agents hit the API less
- No fixed upper limit — disk space is the constraint

## API Keys

- Pexels: already in `VideoEditor/.env`
- Pixabay: needs to be added to `VideoEditor/.env` as `PIXABAY_API_KEY`

## Out of Scope (Future)

- AI-based energy tagging (analyze motion/color/audio)
- AI-based keyword enrichment (CLIP embeddings for semantic search)
- YouTube Creative Commons scraping
- Paid stock API integration
- Thumbnail generation for browsing
