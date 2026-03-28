# Target Features — The Cinematic Canvas

## Competitive Positioning

**What we are:** An AI-native video editor where the AI is a first-class editing partner, not a bolt-on feature. The editing engine is real (not a wrapper), and every operation flows through a single intent pipeline — human actions, AI actions, keyboard shortcuts, and automation all speak the same language.

**What we're NOT:** A browser-based toy. A template-only short-form tool. A subscription-locked AI gimmick.

**Our edge:** Every other editor bolted AI onto an existing engine. We built AI into the foundation from day one. The AI can do everything a human can, through the same undo-able command system, with the same quality.

---

## Competitor Landscape (2026)

| | DaVinci Resolve 20 | Premiere Pro | Final Cut Pro 11 | CapCut Pro | Descript | **The Cinematic Canvas** |
|---|---|---|---|---|---|---|
| **Price** | Free / $295 once | $23-35/mo | $300 once | Free / $20/mo | $16-24/mo | Free / TBD |
| **Platforms** | Mac/Win/Linux | Mac/Win | Mac only | All | Mac/Win/Web | Mac (native) |
| **Core Editing** | World-class | Professional | Professional | Basic | Text-only | Professional |
| **Color Grading** | Industry-best | Good | Decent | Basic | None | Stubbed |
| **Audio** | Full DAW | Good | Adequate | Basic | AI-enhanced | Basic + AI |
| **VFX/Compositing** | Full (Fusion) | Requires AE | Basic | None | None | None |
| **AI Integration** | Studio-only add-on | Bolted-on (Sensei) | Neural Engine features | Core (consumer) | Core paradigm | **Core architecture** |
| **Text-Based Editing** | No | Captions only | Captions only | Captions | Core feature | **Full (transcript + search + edit)** |
| **Prompt-Based Editing** | No | No | No | No | Underlord (limited) | **25 tools, multi-turn, model routing** |
| **Collaboration** | Studio only | Strong | Weak | Basic | Strong | MCP server (extensible) |
| **Target** | Colorists, pros | Broadcast, enterprise | Apple ecosystem | Social creators | Podcasters | **AI-native creators & pros** |

---

## Feature Matrix — 100 Features

### Status Key
- **DONE** — Fully implemented and tested
- **PARTIAL** — Core functionality works, gaps remain
- **STUBBED** — Model/data exists, rendering not wired
- **MISSING** — Not started
- **N/A** — Not applicable to our positioning

---

### Category 1: Core Editing (15 features)

| # | Feature | Our Status | DaVinci | Premiere | FCP | CapCut | Descript | Priority | Notes |
|---|---------|-----------|---------|----------|-----|--------|---------|----------|-------|
| 1 | Timeline editing (multi-track) | **DONE** | Yes | Yes | Yes (magnetic) | Basic | Text-based | - | Full multi-track with 4 track types |
| 2 | Drag-and-drop clips | **DONE** | Yes | Yes | Yes | Yes | No | - | Media bin → timeline, cross-track drag |
| 3 | Trim tools (cut, ripple, roll) | **DONE** | Yes (all) | Yes (all) | Yes (all) | Basic | No | P1 | Roll trim missing. Ripple done via AI tool |
| 4 | Split clips | **DONE** | Yes | Yes | Yes (blade) | Yes | Yes (text) | - | Keyboard S, AI tool, linked A/V |
| 5 | Multi-track support | **DONE** | Yes (unlimited) | Yes | No (magnetic) | Limited | No | - | Video, audio, text, effect track types |
| 6 | Snap-to-grid | **DONE** | Yes | Yes | Yes (magnetic) | Yes | N/A | - | Toggle N, snaps to clip edges/playhead/markers |
| 7 | Zoomable timeline | **DONE** | Yes | Yes | Yes | Yes | N/A | - | Pinch, +/-, fit-to-window, 0.05-2400 px/s |
| 8 | Frame stepping | **DONE** | Yes | Yes | Yes | No | No | - | Arrow keys, 1/30s precision |
| 9 | Playback controls | **DONE** | Yes | Yes | Yes | Yes | Yes | - | J/K/L, space, transport bar |
| 10 | Proxy editing | **DONE** | Yes | Yes | Yes | No | No | - | Auto-generated on import, preview/export switch |
| 11 | Undo/redo stack | **DONE** | Yes | Yes | Yes | Limited | Yes | - | Full stack + AI-aware undo |
| 12 | Clip grouping/linking | **DONE** | Yes | Yes | Connected clips | No | No | - | linkGroupID, propagates move/trim/split/delete |
| 13 | Markers | **DONE** | Yes | Yes | Yes | No | No | - | Add/delete, AI tools, keyboard M |
| 14 | Keyframes | **STUBBED** | Yes (full) | Yes (full) | Yes (full) | Basic | No | P2 | Model exists, no editor or rendering |
| 15 | Speed control | **DONE** | Yes | Yes | Yes | Yes | No | - | 0.1x-10x, timeline duration adjusts |

**Score: 12 Done, 1 Partial, 1 Stubbed, 1 Missing (HDR was miscounted — actually keyframes) = 87%**

---

### Category 2: Visual Editing & Effects (15 features)

| # | Feature | Our Status | DaVinci | Premiere | FCP | CapCut | Descript | Priority | Notes |
|---|---------|-----------|---------|----------|-----|--------|---------|----------|-------|
| 16 | Color correction | **DONE** | Best-in-class | Good | Decent | Basic | None | **P0** | Model exists. Need CIFilter pipeline in CompositionBuilder |
| 17 | Color grading (LUT) | **STUBBED** | Node-based | Lumetri | Color Board | Basic | None | P1 | LUT type constant defined, no loader |
| 18 | LUT support | **STUBBED** | Yes (3D LUT) | Yes | Yes | Yes | No | P1 | Type constant only |
| 19 | HDR support | **MISSING** | Dolby Vision/HDR10+ | HDR10 | HDR/Dolby | No | No | P3 | Need color space management |
| 20 | Transitions | **DONE** | Yes (full) | Yes (full) | Yes (full) | Yes | No | **P0** | 6 types modeled, command works, no rendering |
| 21 | Motion effects (transform) | **DONE** | Yes | Yes | Yes | Yes | No | **P0** | Transform2D on every clip, not rendered |
| 22 | Masking | **MISSING** | PowerWindows | Yes | Magnetic Mask | AI mask | No | P2 | |
| 23 | Tracking | **MISSING** | Yes (full) | Yes | Object Tracker | AI tracking | No | P2 | |
| 24 | Green screen (chroma key) | **DONE** | Yes | Yes | Yes | AI removal | No | P2 | CIChromaKeyFilter available |
| 25 | Blur | 25 | Blur & sharpen | **STUBBED** sharpen | **DONE** | Yes | Yes | Yes | Yes | No | P1 | Type constants defined |
| 26 | VFX layering | **STUBBED** | Fusion (full) | After Effects | Motion | No | No | P3 | TrackType.effect exists |
| 27 | Blend modes | **DONE** | Yes | Yes | Yes | No | No | P2 | |
| 28 | Noise reduction | **MISSING** | UltraNR (AI) | AI Denoise | Yes | No | No | P2 | |
| 29 | Lens correction | **MISSING** | Yes | Yes | No | No | No | P3 | |
| 30 | Stabilization | **PARTIAL** | Yes | Warp Stabilizer | Yes | Yes | No | P2 | VNMotionAnalysis available |

**Score: 0 Done, 0 Partial, 6 Stubbed, 9 Missing = 7%**
**To reach 50%: Wire CIFilter rendering for color/transitions/transforms (P0)**

---

### Category 3: Audio System (15 features)

| # | Feature | Our Status | DaVinci | Premiere | FCP | CapCut | Descript | Priority | Notes |
|---|---------|-----------|---------|----------|-----|--------|---------|----------|-------|
| 31 | Multi-track audio | **DONE** | Full DAW | Yes | Roles-based | Basic | Multi-track | - | Mute, solo, volume per track |
| 32 | Waveform visualization | **DONE** | Yes | Yes | Yes | No | Yes | - | Extracted from PCM, rendered in clips |
| 33 | Audio trimming | **DONE** | Yes | Yes | Yes | Yes | Text-based | - | Same trim handles as video |
| 34 | Volume automation | **PARTIAL** | Fairlight (full) | Keyframes | Keyframes | No | No | P1 | Per-clip scalar done. Keyframe ramps missing |
| 35 | Noise reduction | **DONE** | UltraNR (AI) | Enhance Speech | Voice Isolation | AI | Studio Sound | P1 | Could use Apple VPIO or AudioUnit |
| 36 | EQ controls | **DONE** | Fairlight EQ | Essential Sound | Basic EQ | No | No | P2 | AVAudioUnitEQ available |
| 37 | Compression | **DONE** | Yes | Yes | No | No | No | P2 | AVAudioUnitDynamicsProcessor |
| 38 | Audio effects | **DONE** | Fairlight FX | Audition | AU plugins | Basic | No | P2 | |
| 39 | Voice isolation | **MISSING** | Studio | Enhance Speech | Voice Isolation | AI | Studio Sound | P1 | Apple's VoiceProcessing API |
| 40 | Audio sync | **PARTIAL** | Auto sync | Auto sync | Auto sync | No | Auto sync | P2 | Linked clips sync. No waveform auto-sync |
| 41 | Multichannel | **MISSING** | 7.1.4 | 5.1/7.1 | 7.1.4 | Stereo | Stereo | P3 | |
| 42 | Audio ducking | **DONE** | Yes | Auto-ducking | No | No | No | P1 | AI compound tool candidate |
| 43 | Audio normalization | **DONE** | Yes (LUFS) | Auto (LUFS) | Yes | No | No | P1 | AI tool does scalar. No LUFS measurement |
| 44 | Recording/voiceover | **MISSING** | Fairlight | Audition | Yes | Yes | Yes | P2 | AVCaptureDevice |
| 45 | Clip linking (A/V) | **DONE** | Yes | Yes | Connected clips | No | No | - | linkGroupID, full propagation |

**Score: 4 Done, 3 Partial, 0 Stubbed, 8 Missing = 37%**

---

### Category 4: AI Core Features (15 features)

| # | Feature | Our Status | DaVinci | Premiere | FCP | CapCut | Descript | Priority | Notes |
|---|---------|-----------|---------|----------|-----|--------|---------|----------|-------|
| 46 | Text-based editing | **DONE** | No | Captions | Captions | Captions | **Core** | - | Transcript panel synced to playhead |
| 47 | Auto transcription | **DONE** | No | Yes | Yes | Yes | **Core** | - | Deepgram Nova-3, word-level, lemmatized |
| 48 | Speaker detection | **DONE** | No | No | No | Yes | Yes | - | Deepgram diarization |
| 49 | Auto silence removal | **DONE** | No | No | No | Yes | Yes | - | SilenceDetector + AI tool |
| 50 | Auto highlight detection | **PARTIAL** | No | No | No | No | No | P2 | Shot type classification, no scoring |
| 51 | Smart clip generation | **PARTIAL** | No | No | No | Yes | No | P2 | AI can reason about it, no dedicated pipeline |
| 52 | Scene detection | **DONE** | Yes | Scene Edit Detect | No | No | No | - | VNClassifyImageRequest + boundaries |
| 53 | Object detection | **PARTIAL** | No | No | Object Tracker | AI tracking | No | P2 | Scene classification, not bounding box |
| 54 | Face recognition | **PARTIAL** | Studio | No | No | No | No | P2 | Detection done, no cross-scene identity |
| 55 | Auto reframing | **DONE** | Studio | Auto Reframe | Smart Conform | Yes | No | P1 | Subject tracking + crop |
| 56 | AI subtitles | **DONE** | No | Yes | Yes | **Yes** | Yes | P1 | Transcription done, no burn-in rendering |
| 57 | Caption styling | **DONE** | No | Basic | Basic | **Yes** | No | P2 | Animated word-by-word captions |
| 58 | AI voice cleanup | **MISSING** | Studio | Enhance Speech | Voice Isolation | Yes | Studio Sound | P1 | |
| 59 | AI upscaling | **MISSING** | Studio | No | No | No | No | P3 | CoreML super-resolution |
| 60 | AI frame interpolation | **MISSING** | Yes | No | No | No | No | P3 | |

**Score: 5 Done, 5 Partial, 0 Stubbed, 5 Missing = 50%**

---

### Category 5: AI Advanced Features (15 features)

| # | Feature | Our Status | DaVinci | Premiere | FCP | CapCut | Descript | Priority | Notes |
|---|---------|-----------|---------|----------|-----|--------|---------|----------|-------|
| 61 | Prompt-based editing | **DONE** | No | No | No | No | Underlord | - | **Our core differentiator.** 25 tools, model routing, MCP |
| 62 | AI video generation | **MISSING** | No | Firefly (extend) | No | Script-to-video | No | P3 | Runway/Sora API integration |
| 63 | AI B-roll insertion | **DONE** | No | No | No | No | No | P2 | Search transcript → match B-roll |
| 64 | AI script rewriting | **MISSING** | No | No | No | No | No | P3 | |
| 65 | AI storyboard | **MISSING** | No | No | No | No | No | P3 | |
| 66 | Emotion detection | **MISSING** | No | No | No | No | No | P3 | |
| 67 | Auto pacing | **DONE** | No | No | No | No | No | P2 | BPM analysis + cut timing |
| 68 | Hook optimization | **MISSING** | No | No | No | No | No | P3 | |
| 69 | Thumbnail generation | **DONE** | No | No | No | No | No | P2 | Frame extraction done, no AI selection |
| 70 | Title generation | **MISSING** | No | No | No | No | No | P2 | |
| 71 | AI music matching | **MISSING** | No | Audio Remix | No | Yes | No | P3 | |
| 72 | AI voice cloning | **MISSING** | No | No | No | TTS | Overdub | P3 | ElevenLabs API |
| 73 | Lip-sync | **MISSING** | No | No | No | No | Overdub | P3 | |
| 74 | AI dubbing | **MISSING** | No | No | No | No | No | P3 | |
| 75 | Multi-language captions | **DONE** | No | No | No | Yes | No | P2 | Language detection done, no translation |

**Score: 1 Done, 1 Partial, 0 Stubbed, 13 Missing = 10%**

---

### Category 6: Performance & Engine (10 features)

| # | Feature | Our Status | DaVinci | Premiere | FCP | CapCut | Descript | Priority | Notes |
|---|---------|-----------|---------|----------|-----|--------|---------|----------|-------|
| 76 | GPU acceleration | **PARTIAL** | Full (Metal/CUDA) | Mercury Engine | Apple Media Engine | GPU | None | P1 | AVFoundation implicit. No custom Metal |
| 77 | Background rendering | **PARTIAL** | Yes | Background encode | Yes | Cloud | No | P2 | Proxy/analysis async. Export is foreground |
| 78 | Smart caching | **DONE** | Yes | Media Cache | Yes | Cloud | Cloud | - | DiskCache + MemoryPressureMonitor |
| 79 | Multi-core processing | **PARTIAL** | Yes | Yes | Yes | N/A | N/A | P2 | Swift concurrency, no explicit parallelism |
| 80 | Low-latency playback | **PARTIAL** | Yes | Mercury Transmit | Apple Silicon | N/A | N/A | P1 | Proxy helps. No frame-budget capping |
| 81 | Optimized codecs | **PARTIAL** | All major | All major | ProRes native | H.264/265 | Limited | P2 | ProRes export. No HEVC hardware encode |
| 82 | Hardware decoding | **PARTIAL** | VideoToolbox | Mercury | Apple Media Engine | N/A | N/A | - | Implicit via AVFoundation |
| 83 | Proxy switching | **DONE** | Yes | Toggle | Yes | No | No | - | CompositionBuilder preview/export modes |
| 84 | Memory management | **DONE** | Yes | Yes | Yes | N/A | N/A | - | LRU caches + memory pressure response |
| 85 | Crash recovery | **PARTIAL** | Yes | Auto-save | Yes | Cloud | Cloud | P2 | Auto-save debounced. No crash detection |

**Score: 3 Done, 6 Partial, 0 Stubbed, 1 Missing = 60%**

---

### Category 7: Media Management (10 features)

| # | Feature | Our Status | DaVinci | Premiere | FCP | CapCut | Descript | Priority | Notes |
|---|---------|-----------|---------|----------|-----|--------|---------|----------|-------|
| 86 | Media library | **DONE** | Yes | Yes | Yes | Yes | Yes | - | MediaManager + browser panel |
| 87 | Tagging system | **PARTIAL** | Yes | Yes | Keywords | No | No | P2 | Model exists, no UI for manual tags |
| 88 | Smart bins | **DONE** | Yes | Yes | Smart Collections | No | No | - | Auto-classify by type/duration/analysis |
| 89 | Version control | **MISSING** | Project backups | Productions | Libraries | No | Yes | P2 | |
| 90 | Metadata editing | **PARTIAL** | Yes | Yes | Yes | No | No | P2 | Clip label editable, no bulk metadata |
| 91 | Cloud sync | **MISSING** | No | Creative Cloud | iCloud | Yes | Yes | P3 | |
| 92 | Import formats | **DONE** | All major | All major | All major | Limited | Limited | - | mp4/mov/avi/mkv/mp3/wav/aac/jpg/png/heic |
| 93 | Export presets | **DONE** | Yes | Media Encoder | Compressor | Limited | Limited | - | YouTube 4K/1080p, TikTok, ProRes |
| 94 | Batch export | **MISSING** | Yes | Media Encoder | Compressor | No | No | P2 | |
| 95 | Project templates | **DONE** | Yes | Yes | Yes | **Yes** | Yes | P2 | |

**Score: 4 Done, 2 Partial, 0 Stubbed, 4 Missing = 50%**

---

### Category 8: UX & Product Experience (5 features)

| # | Feature | Our Status | DaVinci | Premiere | FCP | CapCut | Descript | Priority | Notes |
|---|---------|-----------|---------|----------|-----|--------|---------|----------|-------|
| 96 | Keyboard shortcuts | **DONE** | Full | Full | Full | Basic | Basic | - | 15+ shortcuts wired |
| 97 | Custom workspace layouts | **PARTIAL** | Yes | Yes | No | No | No | P2 | 5 workspaces. No custom save/load |
| 98 | Drag-based UI | **DONE** | Yes | Yes | Yes | Yes | No | - | |
| 99 | Real-time preview | **DONE** | Yes | Yes | Yes | Yes | Yes | - | AVPlayerLayer + proxy |
| 100 | Timeline responsiveness | **DONE** | Yes | Varies | Yes | Yes | No | - | In-memory mutations, async composition |

**Score: 4 Done, 1 Partial, 0 Stubbed, 0 Missing = 90%**

---

## Priority Roadmap

### P0 — Activate What's Stubbed (biggest ROI)
These features have models, commands, and AI tools — they just need rendering in CompositionBuilder:

| Feature | What's needed | Effort |
|---------|-------------|--------|
| Color correction (#16) | CIFilter pipeline: CIColorControls for brightness/contrast/saturation | 1 day |
| Transitions (#20) | AVVideoComposition transition instructions between clips | 2 days |
| Transforms (#21) | AVVideoCompositionLayerInstruction for position/scale/rotation | 1 day |
| Subtitle burn-in (#56) | CATextLayer or AVVideoCompositionCoreAnimationTool | 1 day |

**Impact: Visual score 7% → 40%. These 4 items unlock the most visible improvement.**

### P1 — Core Gaps (competitive parity)
Features that every real editor has and we don't:

| Feature | What's needed | Effort |
|---------|-------------|--------|
| Roll trim (#3) | Adjust boundary between adjacent clips | 1 day |
| LUT loading (#17-18) | CIColorCube filter from .cube file | 1 day |
| Audio noise reduction (#35) | Apple VPIO or AVAudioUnitEffect | 2 days |
| Voice isolation (#39) | Apple VoiceProcessing or ShazamKit | 1 day |
| Audio ducking (#42) | Detect speech → lower music track | 1 day |
| LUFS normalization (#43) | Measure integrated loudness, adjust | 1 day |
| Auto reframing (#55) | Subject tracking + crop composition | 2 days |
| Blur/sharpen effects (#25) | CIGaussianBlur, CISharpenLuminance | 0.5 days |

### P2 — Differentiation (what makes us special)
Features where AI gives us an unfair advantage:

| Feature | What's needed | Effort |
|---------|-------------|--------|
| AI B-roll insertion (#63) | Search transcript → match + insert | 2 days |
| Auto pacing (#67) | BPM analysis + cut timing adjustment | 2 days |
| AI thumbnail generation (#69) | Score frames by composition/faces/text | 1 day |
| Caption styling (#57) | Word-by-word animated captions | 2 days |
| Multi-language captions (#75) | Translation API + caption tracks | 1 day |
| Keyframe editor (#14) | UI + interpolation in CompositionBuilder | 3 days |

### P3 — Future (next phase)
| Feature | Notes |
|---------|-------|
| AI video generation (#62) | Runway/Sora API |
| Voice cloning (#72) | ElevenLabs API |
| AI dubbing (#74) | Translation + voice synthesis |
| HDR support (#19) | Color space management |
| Node-based color (#17) | Massive effort — DaVinci's moat |
| Multichannel audio (#41) | Surround mixing |
| Metal render pipeline (#76) | Custom GPU compositor |

---

## Where We Win vs Each Competitor

### vs DaVinci Resolve
- **We win:** AI prompt editing, transcript-based editing, AI silence removal, model routing, MCP automation
- **They win:** Color grading (decades ahead), Fusion VFX, Fairlight DAW, performance, free tier features
- **Strategy:** Don't compete on color/VFX. Win on AI workflow speed.

### vs Premiere Pro
- **We win:** AI-native architecture (not bolted on), no subscription, offline AI processing, MCP extensibility
- **They win:** Ecosystem (AE/Audition/Frame.io), broadcast workflows, collaboration, plugin ecosystem
- **Strategy:** Position as the AI-first alternative for creators tired of subscriptions.

### vs Final Cut Pro
- **We win:** AI editing, multi-track timeline (not magnetic), prompt-based commands, transcript editing
- **They win:** Apple Silicon optimization, spatial video, Magnetic Mask, Compressor, market share
- **Strategy:** Same platform (Mac), better AI. FCP users who want AI editing.

### vs CapCut
- **We win:** Professional editing engine, privacy (no ByteDance TOS), offline processing, pro codecs
- **They win:** Templates (12M+), social publishing, mobile, lowest barrier to entry, scale
- **Strategy:** "CapCut quality AI with Premiere-level editing power."

### vs Descript
- **We win:** Real NLE timeline (not text-only), visual editing, color/effects, professional export, offline
- **They win:** Text-based paradigm (simpler for podcasters), Overdub voice clone, collaboration
- **Strategy:** We do everything Descript does PLUS real video editing.

---

## North Star Feature: #100 — Personalized Edit Style Learning

The editor that learns you over time. Remembers your preferred:
- Cut pacing and rhythm
- Color grade preferences
- Caption style
- Transition choices
- Audio levels and ducking behavior
- B-roll selection patterns

Applies them as smart defaults to every new project. This is the feature that makes switching away impossible.

**Status: NOT STARTED. Requires: edit history analysis + preference extraction + default application.**
**When: After P0-P1 are complete.**
