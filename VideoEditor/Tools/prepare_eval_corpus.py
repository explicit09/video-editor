#!/usr/bin/env python3
"""Prepare, validate, and repair the VideoEditor evaluation corpus."""

from __future__ import annotations

import argparse
import json
import os
import shutil
from pathlib import Path

from eval_system.corpus import CorpusManager, media_type_for_path


def link_or_copy(source: Path, destination: Path, mode: str) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() or destination.is_symlink():
        destination.unlink()
    if mode == "symlink":
        os.symlink(source, destination)
    elif mode == "hardlink":
        os.link(source, destination)
    else:
        shutil.copy2(source, destination)


def iter_media_files(input_dir: Path) -> list[Path]:
    files: list[Path] = []
    for path in sorted(input_dir.rglob("*")):
        if path.is_file() and media_type_for_path(path) is not None:
            files.append(path)
    return files


def target_subdir(source_type: str, media_type: str) -> str:
    if source_type == "synthetic":
        return "synthetic"
    if source_type == "public":
        return "source_videos" if media_type in {"audio", "image"} else "public_seed"
    return "source_videos"


def cmd_ingest(args: argparse.Namespace) -> int:
    input_dir = Path(args.input_dir).expanduser().resolve()
    output_dir = Path(args.output_dir).expanduser().resolve()
    if not input_dir.exists():
        raise SystemExit(f"Input directory does not exist: {input_dir}")

    media_files = iter_media_files(input_dir)
    if not media_files:
        raise SystemExit(f"No supported media files found in: {input_dir}")

    output_dir.mkdir(parents=True, exist_ok=True)
    for source in media_files:
        media_type = media_type_for_path(source)
        assert media_type is not None
        relative_target = Path(target_subdir(args.source_type, media_type)) / source.name
        link_or_copy(source, output_dir / relative_target, args.link_mode)

    manager = CorpusManager(output_dir)
    manifest = manager.repair_manifest()
    if args.dataset_name:
        manifest.name = args.dataset_name
        manager.write_manifest(manifest)

    print(f"Prepared corpus '{manifest.name}'")
    print(f"  Items: {len(manifest.items)}")
    print(f"  Manifest: {manager.manifest_path}")
    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    manifest_path = Path(args.manifest).expanduser().resolve()
    manager = CorpusManager(manifest_path.parent)
    manifest = manager.load_manifest()
    report = manager.validate_manifest(manifest)

    print(f"Manifest: {manifest_path}")
    print(f"Items: {len(manifest.items)}")
    print(f"Status: {'OK' if report.ok else 'ERROR'}")
    if report.errors:
        print("Errors:")
        for error in report.errors:
            print(f"  - {error}")
    if report.warnings:
        print("Warnings:")
        for warning in report.warnings:
            print(f"  - {warning}")
    if report.orphans:
        print("Orphans:")
        for orphan in report.orphans[:50]:
            print(f"  - {orphan}")
        if len(report.orphans) > 50:
            print(f"  ... and {len(report.orphans) - 50} more")
    return 0 if report.ok else 1


def cmd_summarize(args: argparse.Namespace) -> int:
    manifest_path = Path(args.manifest).expanduser().resolve()
    manager = CorpusManager(manifest_path.parent)
    manifest = manager.load_manifest()

    source_counts: dict[str, int] = {}
    split_counts: dict[str, int] = {}
    media_counts: dict[str, int] = {}
    task_counts: dict[str, int] = {}
    total_duration = 0.0
    total_size = 0

    for item in manifest.items:
        source_counts[item.source_family] = source_counts.get(item.source_family, 0) + 1
        split_counts[item.split] = split_counts.get(item.split, 0) + 1
        media_counts[item.media_type] = media_counts.get(item.media_type, 0) + 1
        for task in item.tasks:
            task_counts[task] = task_counts.get(task, 0) + 1
        total_duration += float(item.probe.get("duration_seconds") or 0.0)
        total_size += int(item.probe.get("size_bytes") or 0)

    print(f"Corpus: {manifest.name}")
    print(f"  Version: {manifest.version}")
    print(f"  Created: {manifest.created}")
    print(f"  Items: {len(manifest.items)}")
    print(f"  Total duration: {total_duration:.1f}s ({total_duration / 3600:.2f}h)")
    print(f"  Total size: {total_size / (1024 * 1024 * 1024):.2f} GiB")
    print()
    print("  Sources:")
    for key, value in sorted(source_counts.items()):
        print(f"    {key}: {value}")
    print()
    print("  Splits:")
    for key, value in sorted(split_counts.items()):
        print(f"    {key}: {value}")
    print()
    print("  Media types:")
    for key, value in sorted(media_counts.items()):
        print(f"    {key}: {value}")
    print()
    print("  Tasks:")
    for key, value in sorted(task_counts.items()):
        print(f"    {key}: {value}")
    return 0


def cmd_rescan(args: argparse.Namespace) -> int:
    output_dir = Path(args.output_dir).expanduser().resolve()
    if not output_dir.exists():
        raise SystemExit(f"Directory not found: {output_dir}")
    manager = CorpusManager(output_dir)
    existing = manager.load_manifest() if manager.manifest_path.exists() else None
    manifest = manager.rescan_manifest(existing)
    if args.dataset_name:
        manifest.name = args.dataset_name
    manager.write_manifest(manifest)
    print(f"Rescanned manifest: {manager.manifest_path}")
    print(f"  Items: {len(manifest.items)}")
    return 0


def cmd_repair_manifest(args: argparse.Namespace) -> int:
    output_dir = Path(args.output_dir).expanduser().resolve()
    if not output_dir.exists():
        raise SystemExit(f"Directory not found: {output_dir}")
    manager = CorpusManager(output_dir)
    manifest = manager.repair_manifest()
    report = manager.validate_manifest(manifest)
    print(f"Repaired manifest: {manager.manifest_path}")
    print(f"  Items: {len(manifest.items)}")
    print(f"  Status: {'OK' if report.ok else 'ERROR'}")
    if args.print_json:
        print(json.dumps(manifest.to_dict(), indent=2))
    return 0 if report.ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command")

    p_in = sub.add_parser("ingest", help="Ingest media files into a corpus")
    p_in.add_argument("--input-dir", required=True)
    p_in.add_argument("--output-dir", required=True)
    p_in.add_argument("--dataset-name")
    p_in.add_argument("--source-type", choices=["local", "public", "synthetic"], default="local")
    p_in.add_argument("--link-mode", choices=["symlink", "hardlink", "copy"], default="symlink")
    p_in.set_defaults(func=cmd_ingest)

    p_val = sub.add_parser("validate", help="Validate manifest.json against disk")
    p_val.add_argument("--manifest", required=True)
    p_val.set_defaults(func=cmd_validate)

    p_sum = sub.add_parser("summarize", help="Print corpus summary statistics")
    p_sum.add_argument("--manifest", required=True)
    p_sum.set_defaults(func=cmd_summarize)

    p_res = sub.add_parser("rescan", help="Regenerate manifest.json from the current corpus folders")
    p_res.add_argument("--output-dir", required=True)
    p_res.add_argument("--dataset-name")
    p_res.set_defaults(func=cmd_rescan)

    p_rep = sub.add_parser("repair-manifest", help="Rebuild manifest.json from disk and validate it")
    p_rep.add_argument("--output-dir", required=True)
    p_rep.add_argument("--print-json", action="store_true")
    p_rep.set_defaults(func=cmd_repair_manifest)

    args = parser.parse_args()
    if args.command is None:
        parser.print_help()
        return 1
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
