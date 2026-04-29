#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


DEFAULT_TARGET_BYTES = 1_000_000
MAX_RECOMMENDED_INPUT_BYTES = 10_000_000
GOOD_QUALITY_CQ = 45
HIGH_QUALITY_CRF = "18"


def human_size(size: int) -> str:
    units = ("B", "KB", "MB", "GB")
    value = float(size)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.0f} {unit}" if unit == "B" else f"{value:.2f} {unit}"
        value /= 1024
    return f"{size} B"


def parse_size(value: str) -> int:
    text = value.strip().lower().replace(" ", "")
    multipliers = {
        "b": 1,
        "kb": 1000,
        "kib": 1024,
        "mb": 1000 * 1000,
        "mib": 1024 * 1024,
    }
    for suffix, multiplier in sorted(multipliers.items(), key=lambda item: len(item[0]), reverse=True):
        if text.endswith(suffix):
            number = text[: -len(suffix)]
            return int(float(number) * multiplier)
    return int(float(text))


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def require_tool(name: str) -> str:
    path = shutil.which(name)
    if path:
        return path

    for folder in ("/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"):
        candidate = Path(folder) / name
        if candidate.exists():
            return str(candidate)

    raise RuntimeError(f"Missing {name}. Install FFmpeg first, then try again.")


def get_duration(ffprobe: str, source: Path) -> float:
    result = run(
        [
            ffprobe,
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "json",
            str(source),
        ]
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Could not read video duration.")
    data = json.loads(result.stdout)
    duration = float(data["format"]["duration"])
    if duration <= 0:
        raise RuntimeError("Could not read a valid video duration.")
    return duration


def ffmpeg_supports_encoder(ffmpeg: str, encoder: str) -> bool:
    result = run([ffmpeg, "-hide_banner", "-encoders"])
    return result.returncode == 0 and encoder in result.stdout


def choose_encoder(ffmpeg: str) -> tuple[str, str, bool]:
    if ffmpeg_supports_encoder(ffmpeg, "hevc_videotoolbox"):
        return "hevc_videotoolbox", "HEVC/H.265 hardware", True
    if ffmpeg_supports_encoder(ffmpeg, "h264_videotoolbox"):
        return "h264_videotoolbox", "H.264 hardware", True
    if ffmpeg_supports_encoder(ffmpeg, "libx265"):
        return "libx265", "HEVC/H.265", False
    return "libx264", "H.264", False


def encoder_options(ffmpeg: str) -> list[tuple[str, str, bool]]:
    options: list[tuple[str, str, bool]] = []
    for encoder, label, is_hardware in (
        ("libvpx-vp9", "WebM/VP9", False),
        ("libx265", "HEVC/H.265", False),
        ("hevc_videotoolbox", "HEVC/H.265 hardware", True),
        ("h264_videotoolbox", "H.264 hardware", True),
        ("libx264", "H.264", False),
    ):
        if encoder.startswith("lib") or ffmpeg_supports_encoder(ffmpeg, encoder):
            options.append((encoder, label, is_hardware))
    return options


def output_path_for(source: Path, output_dir: Path | None, extension: str = ".mp4") -> Path:
    folder = output_dir if output_dir else source.parent
    candidate = folder / f"{source.stem}-video-compressed{extension}"
    return unique_path(candidate)


def unique_path(candidate: Path) -> Path:
    if not candidate.exists():
        return candidate
    index = 2
    while True:
        next_candidate = candidate.with_name(f"{candidate.stem}-{index}{candidate.suffix}")
        if not next_candidate.exists():
            return next_candidate
        index += 1


def output_extension_for_encoder(encoder: str) -> str:
    return ".webm" if encoder == "libvpx-vp9" else ".mp4"


def build_video_args(source: Path, encoder: str) -> list[str]:
    if encoder == "libvpx-vp9":
        return [
            "-y",
            "-i",
            str(source),
            "-map",
            "0:v:0",
            "-c:v",
            "libvpx-vp9",
            "-crf",
            HIGH_QUALITY_CRF,
            "-b:v",
            "0",
            "-row-mt",
            "1",
            "-deadline",
            "good",
            "-cpu-used",
            "4",
            "-pix_fmt",
            "yuv420p",
        ]

    if encoder in {"hevc_videotoolbox", "h264_videotoolbox"}:
        args = [
            "-y",
            "-i",
            str(source),
            "-map",
            "0:v:0",
            "-c:v",
            encoder,
            "-q:v",
            str(GOOD_QUALITY_CQ),
            "-pix_fmt",
            "yuv420p",
        ]
        if encoder == "hevc_videotoolbox":
            args.extend(["-tag:v", "hvc1"])
        return args

    if encoder == "libx265":
        return [
            "-y",
            "-i",
            str(source),
            "-map",
            "0:v:0",
            "-c:v",
            "libx265",
            "-preset",
            "medium",
            "-tag:v",
            "hvc1",
            "-pix_fmt",
            "yuv420p",
            "-crf",
            HIGH_QUALITY_CRF,
        ]

    return [
        "-y",
        "-i",
        str(source),
        "-map",
        "0:v:0",
        "-c:v",
        "libx264",
        "-preset",
        "medium",
        "-profile:v",
        "main",
        "-pix_fmt",
        "yuv420p",
        "-crf",
        HIGH_QUALITY_CRF,
    ]


def compress_video(source: Path, output: Path, target_bytes: int) -> tuple[bool, list[str]]:
    ffmpeg = require_tool("ffmpeg")
    ffprobe = require_tool("ffprobe")
    duration = get_duration(ffprobe, source)

    lines = [
        f"Source: {source.name} | {human_size(source.stat().st_size)} | {duration:.1f}s",
        "Mode: High quality 18 / smallest high-quality format | original dimensions/fps",
    ]

    with tempfile.TemporaryDirectory(prefix="compress-video-") as tmp_name:
        temp_output = Path(tmp_name) / "candidate.webm"
        last_error = ""
        source_size = source.stat().st_size
        best_candidate: tuple[Path, int, str, bool, str] | None = None

        for encoder, codec_label, is_hardware_encoder in encoder_options(ffmpeg):
            if temp_output.exists():
                temp_output.unlink()
            candidate_output = temp_output.with_suffix(output_extension_for_encoder(encoder))
            if candidate_output.exists():
                candidate_output.unlink()

            command = [
                ffmpeg,
                *build_video_args(source, encoder),
            ]
            if encoder == "libvpx-vp9":
                command.extend(["-map", "0:a?", "-c:a", "libopus", "-b:a", "96k"])
            else:
                command.extend(["-map", "0:a?", "-c:a", "copy", "-movflags", "+faststart"])
            command.append(str(candidate_output))
            result = run(command)
            if result.returncode != 0:
                last_error = result.stderr.strip()
                continue

            output_size = candidate_output.stat().st_size
            if output_size >= source_size:
                lines.append(f"[SKIP] {codec_label} was not smaller than the original.")
                continue

            candidate_copy = Path(tmp_name) / f"best{output_extension_for_encoder(encoder)}"
            shutil.copy2(candidate_output, candidate_copy)
            if best_candidate is None or output_size < best_candidate[1]:
                best_candidate = (candidate_copy, output_size, codec_label, is_hardware_encoder, encoder)

        if best_candidate is not None:
            candidate_path, output_size, codec_label, is_hardware_encoder, encoder = best_candidate
            final_output = unique_path(output.with_suffix(output_extension_for_encoder(encoder)))
            final_output.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(candidate_path, final_output)
            speed_note = "fast hardware encoding" if is_hardware_encoder else "medium CPU encoding"
            lines.append(
                f"[OK] {source.name} -> {final_output.name} | "
                f"{human_size(source_size)} -> {human_size(output_size)}"
            )
            if encoder == "libvpx-vp9":
                lines.append(f"Selected {codec_label}; preserved original dimensions/frame rate and encoded audio as Opus for WebM.")
            else:
                lines.append(f"Selected {codec_label} {speed_note}; preserved original dimensions, frame rate, and audio stream.")
            lines.append("Quality 18 candidate picker saved the smallest high-quality result.")
            return True, lines

        final_output = unique_path(output.with_suffix(source.suffix or ".mp4"))
        final_output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, final_output)
        lines.append(
            f"[OK] {source.name} -> {final_output.name} | "
            f"{human_size(source_size)} -> {human_size(source_size)}"
        )
        lines.append("Original file kept because no quality 18 format produced a smaller file.")
        return True, lines


def main() -> int:
    parser = argparse.ArgumentParser(description="Compress a video to around 1 MB or less.")
    parser.add_argument("input", type=Path)
    parser.add_argument("output_dir", nargs="?", type=Path)
    parser.add_argument("-s", "--size", default="auto")
    args = parser.parse_args()

    source = args.input.expanduser().resolve()
    if not source.is_file():
        print(f"[ERROR] Video file not found: {source}", file=sys.stderr)
        return 1

    try:
        size_text = args.size.strip().lower()
        target_bytes = parse_size("1mb") if size_text == "auto" else parse_size(args.size)
        output = output_path_for(source, args.output_dir.expanduser().resolve() if args.output_dir else None)
        if source.stat().st_size > MAX_RECOMMENDED_INPUT_BYTES:
            print(
                f"[WARN] {source.name} is {human_size(source.stat().st_size)}. "
                "This block is tuned for videos around 10 MB or less."
            )
        _, lines = compress_video(source, output, target_bytes)
        for line in lines:
            print(line)
        return 0
    except Exception as error:
        print(f"[ERROR] {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
