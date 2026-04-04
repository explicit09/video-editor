# Eval Corpus Starter

This directory is the staging area for the production-style evaluation corpus.

The goal is not to find one perfect public dataset. The goal is to build a
repeatable corpus that looks like real app usage:

- long source videos
- expected episode cuts
- expected short clips
- exported outputs
- grader results
- known failure cases

## How To Start

Start with three sources of data:

1. Local real videos
   - Your own long recordings, downloads, or meeting videos
   - Even 3 to 10 videos is enough to start

2. Small public bootstrap sets
   - AVA / AVA-ActiveSpeaker for speaker visibility vs speech
   - TVSum for highlight-style summaries
   - ActivityNet for long temporal localization
   - COIN for segment and step boundaries
   - Ego4D if you want messy long-form multimodal footage

3. Synthetic failure cases
   - incorrect speaker/audio pairing
   - off-by-2-second cuts
   - bad crops
   - subtitle overlap
   - black-frame inserts
   - wrong music bed

The public sets help calibrate judges. The local and synthetic sets tell you
whether the actual product is correct.

## Recommended First Corpus

Do this first:

- 5 local long videos from your real workflow
- 10 to 20 public videos from TVSum or ActivityNet
- 20 synthetic failures created from those same videos

That is enough to start building and validating graders.

## Folder Layout

- `incoming/`: raw downloaded or collected videos before ingestion
- `local_seed/`: ingested local corpus items
- `public_seed/`: ingested public corpus items
- `failure_pack/`: intentionally broken cases
- `manifest.template.json`: template for corpus metadata

Generated corpus folders should contain:

- `source_videos/`
- `exports/`
- `judgments/`
- `manifest.json`

## Public Sources

These are the best starting sources because they already have useful temporal
or multimodal annotations:

- AVA: <https://research.google.com/ava/>
- AVA download: <https://research.google.com/ava/download.html>
- Ego4D docs: <https://ego4d-data.org/docs/>
- ActivityNet about: <https://activity-net.org/about.html>
- ActivityNet download: <https://activity-net.org/download.html>
- TVSum repo and download instructions: <https://github.com/yalesong/tvsum>
- COIN: <https://coin-dataset.github.io/>

## Ingestion

Use the helper script to turn a folder of video, audio, or image assets into a
corpus manifest:

```bash
python3 /Users/explicit/Projects/video-editor/VideoEditor/Tools/prepare_eval_corpus.py \
  --input-dir /absolute/path/to/videos \
  --output-dir /Users/explicit/Projects/video-editor/VideoEditor/Tools/eval_corpus/local_seed \
  --dataset-name local-seed \
  --source-type local \
  --link-mode symlink
```

## What To Label First

Do not try to fully label everything up front. Start with these fields:

- source video ID
- rough content type
- expected tasks to run
- whether the clip contains a visible speaker
- whether it is safe for shorts extraction
- whether it belongs in the holdout set

Then add richer judgments only after the harness can run the pipeline.
