#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


DEFAULT_TARGET_BYTES = 1_000_000
GOOD_QUALITY_CQ = 45
QUALITY_ATTEMPTS = ("18", "20", "21")


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


_ENCODER_CACHE: dict[str, bool] = {}
_DURATION_CACHE: dict[str, float] = {}


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
    source_str = str(source)
    cached = _DURATION_CACHE.get(source_str)
    if cached is not None:
        return cached

    result = run(
        [
            ffprobe,
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "json",
            source_str,
        ]
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Could not read video duration.")
    data = json.loads(result.stdout)
    duration = float(data["format"]["duration"])
    if duration <= 0:
        raise RuntimeError("Could not read a valid video duration.")
    _DURATION_CACHE[source_str] = duration
    return duration


def ffmpeg_supports_encoder(ffmpeg: str, encoder: str) -> bool:
    key = f"{ffmpeg}:{encoder}"
    cached = _ENCODER_CACHE.get(key)
    if cached is not None:
        return cached
    result = run([ffmpeg, "-hide_banner", "-encoders"])
    supported = result.returncode == 0 and encoder in result.stdout
    _ENCODER_CACHE[key] = supported
    return supported


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


def build_video_args(source: Path, encoder: str, quality: str) -> list[str]:
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
            quality,
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
            quality,
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
        quality,
    ]


def _compress_video_quality_fallback(source: Path, output: Path, target_bytes: int) -> tuple[bool, list[str]]:
    ffmpeg = require_tool("ffmpeg")
    ffprobe = require_tool("ffprobe")
    duration = get_duration(ffprobe, source)

    lines = [
        f"Source: {source.name} | {human_size(source.stat().st_size)} | {duration:.1f}s",
        "Mode: High quality 18 with 20/21 fallback | smallest high-quality format",
    ]

    with tempfile.TemporaryDirectory(prefix="compress-video-") as tmp_name:
        temp_output = Path(tmp_name) / "candidate.webm"
        last_error = ""
        source_size = source.stat().st_size
        best_candidate: tuple[Path, int, str, bool, str, str] | None = None

        for quality in QUALITY_ATTEMPTS:
            lines.append(f"Trying quality {quality}...")
            for encoder, codec_label, is_hardware_encoder in encoder_options(ffmpeg):
                if temp_output.exists():
                    temp_output.unlink()
                candidate_output = temp_output.with_suffix(output_extension_for_encoder(encoder))
                if candidate_output.exists():
                    candidate_output.unlink()

                command = [
                    ffmpeg,
                    *build_video_args(source, encoder, quality),
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
                    lines.append(f"[SKIP] {codec_label} quality {quality} was not smaller than the original.")
                    continue

                candidate_copy = Path(tmp_name) / f"best-q{quality}{output_extension_for_encoder(encoder)}"
                shutil.copy2(candidate_output, candidate_copy)
                if best_candidate is None or output_size < best_candidate[1]:
                    best_candidate = (candidate_copy, output_size, codec_label, is_hardware_encoder, encoder, quality)

            if best_candidate is not None:
                break

        if best_candidate is not None:
            candidate_path, output_size, codec_label, is_hardware_encoder, encoder, quality = best_candidate
            final_output = unique_path(output.with_suffix(output_extension_for_encoder(encoder)))
            final_output.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(candidate_path, final_output)
            speed_note = "fast hardware encoding" if is_hardware_encoder else "medium CPU encoding"
            lines.append(
                f"[OK] {source.name} -> {final_output.name} | "
                f"{human_size(source_size)} -> {human_size(output_size)}"
            )
            if encoder == "libvpx-vp9":
                lines.append(f"Selected {codec_label} quality {quality}; preserved original dimensions/frame rate and encoded audio as Opus for WebM.")
            else:
                lines.append(f"Selected {codec_label} quality {quality} {speed_note}; preserved original dimensions, frame rate, and audio stream.")
            lines.append("Saved the smallest result from the first quality level that compressed the video.")
            return True, lines

        final_output = unique_path(output.with_suffix(source.suffix or ".mp4"))
        final_output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, final_output)
        lines.append(
            f"[OK] {source.name} -> {final_output.name} | "
            f"{human_size(source_size)} -> {human_size(source_size)}"
        )
        lines.append("Original file kept because qualities 18, 20, and 21 did not produce a smaller file.")
        return True, lines


def video_has_audio(ffprobe: str, source: Path) -> bool:
    result = run([
        ffprobe, "-v", "error", "-select_streams", "a:0",
        "-show_entries", "stream=index", "-of", "csv=p=0", str(source),
    ])
    return result.returncode == 0 and bool(result.stdout.strip())


def compress_video(
    source: Path,
    output: Path,
    target_bytes: int,
    keep_audio: bool = True,
    keep_metadata: bool = False,
) -> tuple[bool, list[str]]:
    """Encode a predictable MP4 toward the requested maximum size."""
    ffmpeg = require_tool("ffmpeg")
    ffprobe = require_tool("ffprobe")
    duration = get_duration(ffprobe, source)
    source_size = source.stat().st_size
    target_bytes = max(int(target_bytes), 64 * 1024)
    output = output.with_suffix(".mp4")
    output.parent.mkdir(parents=True, exist_ok=True)

    lines = [
        f"Source: {source.name} | {human_size(source_size)} | {duration:.1f}s",
        f"Target: {human_size(target_bytes)} | H.264 MP4 target-bitrate mode",
    ]

    if source.suffix.lower() == ".mp4" and source_size <= target_bytes and keep_audio and keep_metadata:
        shutil.copy2(source, output)
        lines.append(f"[OK] {source.name} -> {output.name} | already under target; copied without re-encoding.")
        return True, lines

    has_audio = keep_audio and video_has_audio(ffprobe, source)
    total_bitrate = max(64_000, int(target_bytes * 8 * 0.92 / max(duration, 0.1)))
    audio_bitrate = min(96_000, max(32_000, int(total_bitrate * 0.18))) if has_audio and total_bitrate >= 160_000 else 0
    video_bitrate = max(64_000, total_bitrate - audio_bitrate)
    best_path: Path | None = None
    best_size: int | None = None

    with tempfile.TemporaryDirectory(prefix="lumashrink-video-") as tmp_name:
        tmp = Path(tmp_name)
        for attempt in range(3):
            candidate = tmp / f"candidate-{attempt}.mp4"
            passlog = tmp / f"pass-{attempt}"
            common = [
                "-y", "-i", str(source), "-map", "0:v:0", "-c:v", "libx264",
                "-preset", "medium", "-profile:v", "main", "-pix_fmt", "yuv420p",
                "-b:v", str(video_bitrate), "-maxrate", str(video_bitrate),
                "-bufsize", str(video_bitrate * 2), "-passlogfile", str(passlog),
            ]
            first = run([ffmpeg, *common, "-pass", "1", "-an", "-f", "mp4", os.devnull])
            if first.returncode != 0:
                lines.append(f"[ERROR] Video analysis pass failed: {first.stderr.strip()[-500:]}")
                return False, lines

            second_args = [ffmpeg, *common, "-pass", "2"]
            if audio_bitrate:
                second_args.extend(["-map", "0:a?", "-c:a", "aac", "-b:a", str(audio_bitrate)])
            else:
                second_args.append("-an")
            second_args.extend(["-map_metadata", "0" if keep_metadata else "-1"])
            second_args.extend(["-movflags", "+faststart", str(candidate)])
            second = run(second_args)
            if second.returncode != 0 or not candidate.exists():
                lines.append(f"[ERROR] Video encode failed: {second.stderr.strip()[-500:]}")
                return False, lines

            size = candidate.stat().st_size
            lines.append(f"Attempt {attempt + 1}: {human_size(size)} at {video_bitrate // 1000} kbps video bitrate")
            if best_size is None or size < best_size:
                best_path, best_size = candidate, size
            if size <= target_bytes:
                best_path, best_size = candidate, size
                break
            ratio = target_bytes / max(size, 1)
            video_bitrate = max(48_000, int(video_bitrate * ratio * 0.90))
            if audio_bitrate and video_bitrate <= 64_000:
                audio_bitrate = 0

        if best_path is None or best_size is None:
            lines.append("[ERROR] No video output was produced.")
            return False, lines
        shutil.copy2(best_path, output)

    status = "OK" if best_size <= target_bytes else "BEST EFFORT"
    lines.append(f"[{status}] {source.name} -> {output.name} | {human_size(source_size)} -> {human_size(best_size)}")
    if status == "BEST EFFORT":
        lines.append("The requested target is too small for the source duration at the minimum practical bitrate.")
    return True, lines


def main() -> int:
    parser = argparse.ArgumentParser(description="Compress a video toward a requested maximum size.")
    parser.add_argument("input", type=Path)
    parser.add_argument("output_dir", nargs="?", type=Path)
    parser.add_argument("-s", "--size", default="auto")
    parser.add_argument("-t", "--target-bytes", type=int)
    parser.add_argument("--keep-audio", dest="keep_audio", action="store_true", default=True)
    parser.add_argument("--no-audio", dest="keep_audio", action="store_false")
    parser.add_argument("--keep-metadata", dest="keep_metadata", action="store_true", default=False)
    parser.add_argument("--no-metadata", dest="keep_metadata", action="store_false")
    args = parser.parse_args()

    source = args.input.expanduser().resolve()
    if not source.is_file():
        print(f"[ERROR] Video file not found: {source}", file=sys.stderr)
        return 1

    try:
        size_text = args.size.strip().lower()
        target_bytes = args.target_bytes or (parse_size("1mb") if size_text == "auto" else parse_size(args.size))
        if args.target_bytes is not None:
            if args.output_dir is None:
                raise ValueError("An output file is required with --target-bytes.")
            output = args.output_dir.expanduser().resolve()
        else:
            output = output_path_for(source, args.output_dir.expanduser().resolve() if args.output_dir else None)
        success, lines = compress_video(
            source, output, target_bytes,
            keep_audio=args.keep_audio,
            keep_metadata=args.keep_metadata,
        )
        for line in lines:
            print(line)
        return 0 if success else 1
    except Exception as error:
        print(f"[ERROR] {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
