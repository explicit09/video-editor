# Post-Fix Calibration — Final Summary

**Generated:** 2026-04-02 03:16
**DB:** /tmp/videoeditor-postfix-calibration/index.sqlite
**Suites tested:** clip_styling_suite, caption_overlay_suite, import_and_verify
**Judges:** disabled (calibration only)

## Overall Results

**Total completed: 174**
**Pass: 144 (82%)**
**Fail: 30**
**Quarantine: 0**

## By Workflow

| Workflow | Total | Pass | Fail | Q | Pass Rate | vs Before |
|----------|-------|------|------|---|-----------|-----------|
| ⚠️ caption_overlay_suite | 46 | 26 | 20 | 0 | 56% | was 11% |
| ⚠️ clip_styling_suite | 64 | 60 | 4 | 0 | 93% | was 30% |
| ⚠️ import_and_verify | 64 | 58 | 6 | 0 | 90% | was 0% |

## Validators

| Validator | Pass | Fail | Q | Total | Rate |
|-----------|------|------|---|-------|------|
| audio_present | 26 | 0 | 2 | 28 | 92% |
| duration_sanity | 26 | 0 | 2 | 28 | 92% |
| export_exists | 26 | 2 | 0 | 28 | 92% |
| no_black_frames | 26 | 0 | 2 | 28 | 92% |
| verify_playback_clean | 118 | 1 | 0 | 119 | 99% |

## Caption Overlay Failures Investigation

**20 failures to investigate:**

By source family:
- ava: 20

### Failure Details

**ava-2ppxig0wu18**
- Reasons: ["Run raised exception: timed out"]

**ava-4zpjkfu6cl8**
- Reasons: ["Run raised exception: Remote end closed connection without response"]

**ava-5bdj0ow5hna**
- Reasons: ["Run raised exception: timed out"]

**ava-7ypf6dntoyw**
- Reasons: ["Run raised exception: timed out"]

**ava-8no5ffbiaog**
- Reasons: ["Run raised exception: timed out"]

**ava-ag-pxilrd48**
- Reasons: ["Run raised exception: transcribe_asset failed validation: Error: Deepgram error (504): {\"err_code\":\"Gateway Timeout\",\"err_msg\":\"Request timeout. Please try again later.\",\"request_id\":\"7b0

**ava-d8vhxbho1fy**
- Reasons: ["Export path was not detected"]
- ❌ audio_present: quarantine — Audio validation skipped because file is missing
- ❌ duration_sanity: quarantine — Duration sanity skipped because file is missing
- ❌ export_exists: fail — Export path was not detected
- ❌ no_black_frames: quarantine — Black frame check skipped because file is missing

**ava-db19rwn5bgo**
- Reasons: ["Run raised exception: timed out"]

**ava-izvoyvmltki**
- Reasons: ["Run raised exception: timed out"]

**ava-j35jnr0q7es**
- Reasons: ["Run raised exception: timed out"]

**ava-k-spqdjnlps**
- Reasons: ["Run raised exception: timed out"]

**ava-kiy2a-nejxg**
- Reasons: ["Run raised exception: timed out"]

**ava-mkcdanjjdcm**
- Reasons: ["Run raised exception: timed out"]

**ava-qclqynt3amo**
- Reasons: ["Run raised exception: timed out"]

**ava-rfgb2ecmcry**
- Reasons: ["Run raised exception: timed out"]

**ava-xglavhaethy**
- Reasons: ["Export path was not detected"]
- ❌ audio_present: quarantine — Audio validation skipped because file is missing
- ❌ duration_sanity: quarantine — Duration sanity skipped because file is missing
- ❌ export_exists: fail — Export path was not detected
- ❌ no_black_frames: quarantine — Black frame check skipped because file is missing

**ava-xmqsaqpzl1e**
- Reasons: ["Run raised exception: [Errno 28] No space left on device: \"/Volumes/Explicit's Hard Drive/eval_corpus/ava_videos/xmqSaQPzL1E.mp4\" -> '/Users/explicit/Library/Containers/com.videoeditor.app/Data/Do

**ava-y7ncweroe9u**
- Reasons: ["Run raised exception: timed out"]

**ava-zfgsrolsxo**
- Reasons: ["Run raised exception: Remote end closed connection without response"]

**ava-zr725vel-di**
- Reasons: ["Run raised exception: [Errno 28] No space left on device: \"/Volumes/Explicit's Hard Drive/eval_corpus/ava_videos/zR725veL-DI.mp4\" -> '/Users/explicit/Library/Containers/com.videoeditor.app/Data/Do
