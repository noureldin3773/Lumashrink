#!/usr/bin/env python3

from __future__ import annotations

import argparse
import io
import math
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

try:
    from PIL import Image, ImageOps, UnidentifiedImageError, features

    PIL_AVAILABLE = True
except ModuleNotFoundError:
    PIL_AVAILABLE = False
    UnidentifiedImageError = Exception
    features = None


SUPPORTED_INPUT_EXTENSIONS = {
    ".jpg",
    ".jpeg",
    ".png",
    ".webp",
    ".bmp",
    ".tif",
    ".tiff",
}

FORMAT_TO_EXTENSION = {
    "JPEG": ".jpg",
    "PNG": ".png",
    "WEBP": ".webp",
}

EXTENSION_TO_FORMAT = {
    ".jpg": "JPEG",
    ".jpeg": "JPEG",
    ".png": "PNG",
    ".webp": "WEBP",
}

PNG_PALETTE_STEPS = [
    256,
    224,
    192,
    160,
    128,
    112,
    96,
    80,
    72,
    64,
    56,
    48,
    40,
    32,
    24,
    16,
    12,
    8,
]

SIPS_AVAILABLE = shutil.which("sips") is not None


@dataclass
class SourceImage:
    image: Image.Image | None
    exif: bytes | None
    icc_profile: bytes | None
    path: Path
    width: int
    height: int
    detected_format: str


@dataclass
class Candidate:
    data: bytes
    output_format: str
    width: int
    height: int
    quality: int | None
    met_target: bool

    @property
    def size_bytes(self) -> int:
        return len(self.data)


@dataclass
class FileProcessingResult:
    input_path: Path
    output_path: Path
    source_size: int
    output_size: int
    width: int | None
    height: int | None
    output_format: str | None
    quality: int | None
    status: str
    detail: str | None
    met_target: bool


def parse_size_to_bytes(value: str) -> int:
    match = re.fullmatch(r"\s*(\d+(?:\.\d+)?)\s*(b|kb|mb)?\s*", value.lower())
    if not match:
        raise ValueError(
            f"Invalid size '{value}'. Use values like 150kb, 0.5mb, or 200000b."
        )

    amount = float(match.group(1))
    unit = match.group(2) or "b"
    multipliers = {"b": 1, "kb": 1024, "mb": 1024 * 1024}
    return max(1, int(amount * multipliers[unit]))


def human_size(size_bytes: int) -> str:
    if size_bytes >= 1024 * 1024:
        return f"{size_bytes / (1024 * 1024):.2f} MB"
    if size_bytes >= 1024:
        return f"{size_bytes / 1024:.2f} KB"
    return f"{size_bytes} B"


def has_alpha(image: Image.Image) -> bool:
    return "A" in image.getbands() or "transparency" in image.info


def load_source_image(path: Path) -> SourceImage:
    if not PIL_AVAILABLE:
        if not SIPS_AVAILABLE:
            raise ValueError(
                "Pillow is not installed and macOS 'sips' is not available. "
                "Install dependencies with: pip install -r requirements.txt"
            )

        width, height, detected_format = query_sips_image_info(path)
        return SourceImage(
            image=None,
            exif=None,
            icc_profile=None,
            path=path,
            width=width,
            height=height,
            detected_format=detected_format,
        )

    try:
        with Image.open(path) as raw_image:
            if getattr(raw_image, "is_animated", False):
                raise ValueError(
                    f"Animated image '{path.name}' is not supported by this tool."
                )

            exif = raw_image.info.get("exif")
            icc_profile = raw_image.info.get("icc_profile")
            image = ImageOps.exif_transpose(raw_image)
            image.load()
            return SourceImage(
                image=image.copy(),
                exif=exif,
                icc_profile=icc_profile,
                path=path,
                width=image.width,
                height=image.height,
                detected_format=(raw_image.format or path.suffix.lstrip(".")).upper(),
            )
    except UnidentifiedImageError as error:
        raise ValueError(f"'{path}' is not a supported image file.") from error


def query_sips_image_info(path: Path) -> tuple[int, int, str]:
    command = ["sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "format", str(path)]
    result = subprocess.run(command, capture_output=True, text=True, check=False)

    if result.returncode != 0:
        raise ValueError(f"Could not read image info for '{path}'. {result.stderr.strip()}")

    width: int | None = None
    height: int | None = None
    detected_format: str | None = None

    for line in result.stdout.splitlines():
        stripped = line.strip()
        if stripped.startswith("pixelWidth:"):
            width = int(stripped.split(":", 1)[1].strip())
        elif stripped.startswith("pixelHeight:"):
            height = int(stripped.split(":", 1)[1].strip())
        elif stripped.startswith("format:"):
            detected_format = stripped.split(":", 1)[1].strip().upper()

    if width is None or height is None or detected_format is None:
        raise ValueError(f"Could not parse image info for '{path}'.")

    return width, height, detected_format


def choose_output_format(requested_format: str, source: SourceImage) -> str:
    requested_format = requested_format.lower()
    source_suffix = source.path.suffix.lower()
    supports_webp = PIL_AVAILABLE and features is not None and features.check("webp")

    if not PIL_AVAILABLE:
        if requested_format == "webp":
            raise ValueError(
                "WebP output requires Pillow. Install dependencies with: pip install -r requirements.txt"
            )

        if requested_format == "auto":
            return "JPEG"

        if requested_format == "keep":
            if source.detected_format in FORMAT_TO_EXTENSION:
                return source.detected_format
            return "JPEG"

        if requested_format in {"jpeg", "png"}:
            return requested_format.upper()

        raise ValueError(f"Unsupported format '{requested_format}'.")

    if requested_format == "keep":
        if source_suffix in {".jpg", ".jpeg"}:
            return "JPEG"
        if source_suffix == ".png":
            return "PNG"
        if source_suffix == ".webp":
            return "WEBP"
        return "WEBP" if supports_webp else "JPEG"

    if requested_format == "auto":
        if supports_webp:
            return "WEBP"
        return "JPEG"

    if requested_format == "webp":
        if not supports_webp:
            raise ValueError(
                "This Pillow build does not support WebP. Use --format jpeg or --format keep."
            )
        return "WEBP"

    if requested_format == "jpeg":
        return "JPEG"

    if requested_format == "png":
        return "PNG"

    raise ValueError(f"Unsupported format '{requested_format}'.")


def prepare_image_for_output(
    image: Image.Image, output_format: str, background_color: tuple[int, int, int]
) -> Image.Image:
    if output_format == "JPEG":
        if has_alpha(image):
            rgba = image.convert("RGBA")
            flattened = Image.new("RGB", rgba.size, background_color)
            flattened.paste(rgba, mask=rgba.getchannel("A"))
            return flattened
        return image.convert("RGB")

    if output_format == "WEBP":
        if has_alpha(image):
            return image.convert("RGBA")
        return image.convert("RGB")

    if output_format == "PNG":
        if has_alpha(image):
            return image.convert("RGBA")
        return image.convert("RGB")

    raise ValueError(f"Unsupported output format '{output_format}'.")


def quantize_png_image(image: Image.Image, colors: int, dither: bool) -> Image.Image:
    normalized_colors = max(2, min(256, colors))
    dither_mode = Image.Dither.FLOYDSTEINBERG if dither else Image.Dither.NONE

    if has_alpha(image):
        return image.convert("RGBA").quantize(
            colors=normalized_colors,
            method=Image.Quantize.FASTOCTREE,
            dither=dither_mode,
        )

    return image.convert("RGB").quantize(
        colors=normalized_colors,
        method=Image.Quantize.MEDIANCUT,
        dither=dither_mode,
    )


def render_candidate(
    image: Image.Image,
    output_format: str,
    quality: int | None,
    keep_metadata: bool,
    source: SourceImage,
    png_palette_colors: int | None = None,
    png_dither: bool = True,
) -> bytes:
    buffer = io.BytesIO()
    save_kwargs: dict[str, object] = {}
    image_to_save = image

    if output_format == "JPEG":
        save_kwargs.update(
            {
                "format": "JPEG",
                "quality": quality or 85,
                "optimize": True,
                "progressive": True,
            }
        )
    elif output_format == "WEBP":
        save_kwargs.update(
            {
                "format": "WEBP",
                "quality": quality or 85,
                "method": 6,
            }
        )
    elif output_format == "PNG":
        if png_palette_colors is not None:
            image_to_save = quantize_png_image(
                image=image, colors=png_palette_colors, dither=png_dither
            )
        save_kwargs.update({"format": "PNG", "optimize": True, "compress_level": 9})
    else:
        raise ValueError(f"Unsupported output format '{output_format}'.")

    if keep_metadata:
        if source.exif:
            save_kwargs["exif"] = source.exif
        if source.icc_profile:
            save_kwargs["icc_profile"] = source.icc_profile

    image_to_save.save(buffer, **save_kwargs)
    return buffer.getvalue()


def is_better_png_match(candidate: Candidate, current_best: Candidate | None) -> bool:
    if current_best is None:
        return True

    candidate_colors = candidate.quality or 0
    current_colors = current_best.quality or 0
    if candidate_colors != current_colors:
        return candidate_colors > current_colors

    return candidate.size_bytes > current_best.size_bytes


def minimum_png_colors_for_quality(max_quality: int) -> int:
    if max_quality >= 95:
        return 256
    if max_quality >= 85:
        return 224
    if max_quality >= 75:
        return 192
    if max_quality >= 65:
        return 160
    if max_quality >= 55:
        return 128
    if max_quality >= 45:
        return 96
    if max_quality >= 35:
        return 64
    if max_quality >= 25:
        return 48
    if max_quality >= 15:
        return 32
    if max_quality >= 5:
        return 16
    return 8


def search_candidate_at_current_size(
    image: Image.Image,
    output_format: str,
    target_bytes: int,
    min_quality: int,
    max_quality: int,
    keep_metadata: bool,
    source: SourceImage,
) -> tuple[Candidate | None, Candidate]:
    if output_format == "PNG":
        base_data = render_candidate(
            image=image,
            output_format=output_format,
            quality=None,
            keep_metadata=keep_metadata,
            source=source,
        )
        base_candidate = Candidate(
            data=base_data,
            output_format=output_format,
            width=image.width,
            height=image.height,
            quality=None,
            met_target=len(base_data) <= target_bytes,
        )
        if base_candidate.met_target:
            return base_candidate, base_candidate

        smallest_candidate = base_candidate
        best_under_target: Candidate | None = None
        last_too_large_colors: int | None = None
        min_png_colors = minimum_png_colors_for_quality(max_quality)

        for colors in [step for step in PNG_PALETTE_STEPS if step >= min_png_colors]:
            best_this_color: Candidate | None = None

            for use_dither in (True, False):
                data = render_candidate(
                    image=image,
                    output_format=output_format,
                    quality=None,
                    keep_metadata=keep_metadata,
                    source=source,
                    png_palette_colors=colors,
                    png_dither=use_dither,
                )
                candidate = Candidate(
                    data=data,
                    output_format=output_format,
                    width=image.width,
                    height=image.height,
                    quality=colors,
                    met_target=len(data) <= target_bytes,
                )

                if candidate.size_bytes < smallest_candidate.size_bytes:
                    smallest_candidate = candidate

                if candidate.met_target and is_better_png_match(
                    candidate, best_this_color
                ):
                    best_this_color = candidate

            if best_this_color is not None:
                if is_better_png_match(best_this_color, best_under_target):
                    best_under_target = best_this_color

                if last_too_large_colors is not None:
                    for refined_colors in range(last_too_large_colors - 1, colors, -1):
                        for use_dither in (True, False):
                            data = render_candidate(
                                image=image,
                                output_format=output_format,
                                quality=None,
                                keep_metadata=keep_metadata,
                                source=source,
                                png_palette_colors=refined_colors,
                                png_dither=use_dither,
                            )
                            candidate = Candidate(
                                data=data,
                                output_format=output_format,
                                width=image.width,
                                height=image.height,
                                quality=refined_colors,
                                met_target=len(data) <= target_bytes,
                            )

                            if candidate.size_bytes < smallest_candidate.size_bytes:
                                smallest_candidate = candidate

                            if candidate.met_target and is_better_png_match(
                                candidate, best_under_target
                            ):
                                best_under_target = candidate

                break

            last_too_large_colors = colors

        return best_under_target, smallest_candidate

    best_under_target: Candidate | None = None
    low = min_quality
    high = max_quality

    while low <= high:
        quality = (low + high) // 2
        data = render_candidate(
            image=image,
            output_format=output_format,
            quality=quality,
            keep_metadata=keep_metadata,
            source=source,
        )
        size = len(data)

        if size <= target_bytes:
            best_under_target = Candidate(
                data=data,
                output_format=output_format,
                width=image.width,
                height=image.height,
                quality=quality,
                met_target=True,
            )
            low = quality + 1
        else:
            high = quality - 1

    smallest_data = render_candidate(
        image=image,
        output_format=output_format,
        quality=min_quality,
        keep_metadata=keep_metadata,
        source=source,
    )
    smallest_candidate = Candidate(
        data=smallest_data,
        output_format=output_format,
        width=image.width,
        height=image.height,
        quality=min_quality,
        met_target=len(smallest_data) <= target_bytes,
    )
    return best_under_target, smallest_candidate


def estimate_next_dimensions(
    current_width: int,
    current_height: int,
    last_size_bytes: int,
    target_bytes: int,
    min_side: int,
) -> tuple[int, int]:
    if last_size_bytes <= 0:
        factor = 0.9
    else:
        estimated_area_factor = math.sqrt(target_bytes / last_size_bytes)
        factor = min(0.92, max(0.65, estimated_area_factor * 1.08))

    next_width = max(min_side, int(current_width * factor))
    next_height = max(min_side, int(current_height * factor))

    if next_width == current_width and current_width > min_side:
        next_width -= 1
    if next_height == current_height and current_height > min_side:
        next_height -= 1

    return max(min_side, next_width), max(min_side, next_height)


def compress_source_image(
    source: SourceImage,
    target_bytes: int,
    output_format: str,
    min_quality: int,
    max_quality: int,
    min_side: int,
    keep_dimensions: bool,
    keep_metadata: bool,
    background_color: tuple[int, int, int],
) -> Candidate:
    original = source.image
    working_width, working_height = original.size
    best_oversized: Candidate | None = None

    while True:
        current_image = original
        if (working_width, working_height) != original.size:
            current_image = original.resize(
                (working_width, working_height), Image.Resampling.LANCZOS
            )

        prepared_image = prepare_image_for_output(
            current_image, output_format, background_color
        )
        match, smallest_candidate = search_candidate_at_current_size(
            image=prepared_image,
            output_format=output_format,
            target_bytes=target_bytes,
            min_quality=min_quality,
            max_quality=max_quality,
            keep_metadata=keep_metadata,
            source=source,
        )

        if match is not None:
            return match

        if best_oversized is None or smallest_candidate.size_bytes < best_oversized.size_bytes:
            best_oversized = smallest_candidate

        if keep_dimensions:
            break

        if working_width <= min_side and working_height <= min_side:
            break

        next_width, next_height = estimate_next_dimensions(
            current_width=working_width,
            current_height=working_height,
            last_size_bytes=smallest_candidate.size_bytes,
            target_bytes=target_bytes,
            min_side=min_side,
        )

        if (next_width, next_height) == (working_width, working_height):
            break

        working_width, working_height = next_width, next_height

    if best_oversized is None:
        raise RuntimeError("Compression failed before any output could be produced.")
    return best_oversized


def render_sips_candidate(
    input_path: Path,
    output_format: str,
    quality: int | None,
    width: int,
    height: int,
    temp_dir: Path,
) -> bytes:
    output_path = temp_dir / f"candidate{FORMAT_TO_EXTENSION[output_format]}"
    if output_path.exists():
        output_path.unlink()

    command = ["sips"]
    if width > 0 and height > 0:
        command.extend(["-z", str(height), str(width)])

    command.extend(["-s", "format", output_format.lower()])
    if output_format == "JPEG" and quality is not None:
        command.extend(["-s", "formatOptions", str(quality)])

    command.extend([str(input_path), "--out", str(output_path)])
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise ValueError(
            f"Failed to compress '{input_path.name}' with sips. {result.stderr.strip()}"
        )

    return output_path.read_bytes()


def search_sips_candidate_at_current_size(
    input_path: Path,
    output_format: str,
    target_bytes: int,
    min_quality: int,
    max_quality: int,
    width: int,
    height: int,
    temp_dir: Path,
) -> tuple[Candidate | None, Candidate]:
    if output_format == "PNG":
        data = render_sips_candidate(
            input_path=input_path,
            output_format=output_format,
            quality=None,
            width=width,
            height=height,
            temp_dir=temp_dir,
        )
        candidate = Candidate(
            data=data,
            output_format=output_format,
            width=width,
            height=height,
            quality=None,
            met_target=len(data) <= target_bytes,
        )
        return (candidate if candidate.met_target else None, candidate)

    best_under_target: Candidate | None = None
    low = min_quality
    high = max_quality

    while low <= high:
        quality = (low + high) // 2
        data = render_sips_candidate(
            input_path=input_path,
            output_format=output_format,
            quality=quality,
            width=width,
            height=height,
            temp_dir=temp_dir,
        )

        if len(data) <= target_bytes:
            best_under_target = Candidate(
                data=data,
                output_format=output_format,
                width=width,
                height=height,
                quality=quality,
                met_target=True,
            )
            low = quality + 1
        else:
            high = quality - 1

    smallest_data = render_sips_candidate(
        input_path=input_path,
        output_format=output_format,
        quality=min_quality if output_format == "JPEG" else None,
        width=width,
        height=height,
        temp_dir=temp_dir,
    )
    smallest_candidate = Candidate(
        data=smallest_data,
        output_format=output_format,
        width=width,
        height=height,
        quality=min_quality if output_format == "JPEG" else None,
        met_target=len(smallest_data) <= target_bytes,
    )
    return best_under_target, smallest_candidate


def compress_source_image_with_sips(
    source: SourceImage,
    target_bytes: int,
    output_format: str,
    min_quality: int,
    max_quality: int,
    min_side: int,
    keep_dimensions: bool,
) -> Candidate:
    if not SIPS_AVAILABLE:
        raise ValueError(
            "macOS 'sips' is not available, so this fallback backend cannot run."
        )

    working_width, working_height = source.width, source.height
    best_oversized: Candidate | None = None

    with tempfile.TemporaryDirectory(prefix="compress-image-") as temp_dir_name:
        temp_dir = Path(temp_dir_name)

        while True:
            match, smallest_candidate = search_sips_candidate_at_current_size(
                input_path=source.path,
                output_format=output_format,
                target_bytes=target_bytes,
                min_quality=min_quality,
                max_quality=max_quality,
                width=working_width,
                height=working_height,
                temp_dir=temp_dir,
            )

            if match is not None:
                return match

            if best_oversized is None or smallest_candidate.size_bytes < best_oversized.size_bytes:
                best_oversized = smallest_candidate

            if keep_dimensions:
                break

            if working_width <= min_side and working_height <= min_side:
                break

            next_width, next_height = estimate_next_dimensions(
                current_width=working_width,
                current_height=working_height,
                last_size_bytes=smallest_candidate.size_bytes,
                target_bytes=target_bytes,
                min_side=min_side,
            )

            if (next_width, next_height) == (working_width, working_height):
                break

            working_width, working_height = next_width, next_height

    if best_oversized is None:
        raise RuntimeError("Compression failed before any output could be produced.")
    return best_oversized


def classify_output_argument(output_argument: Path | None) -> tuple[Path | None, Path | None]:
    if output_argument is None:
        return None, None

    if output_argument.exists() and output_argument.is_dir():
        return None, output_argument

    if output_argument.suffix:
        return output_argument, None

    output_argument.mkdir(parents=True, exist_ok=True)
    return None, output_argument


def preferred_extension_for_format(input_path: Path, output_format: str) -> str:
    original_suffix = input_path.suffix.lower()
    if EXTENSION_TO_FORMAT.get(original_suffix) == output_format:
        return original_suffix
    return FORMAT_TO_EXTENSION[output_format]


def detect_output_format_from_path(output_argument: Path | None) -> str | None:
    if output_argument is None or not output_argument.suffix:
        return None
    return EXTENSION_TO_FORMAT.get(output_argument.suffix.lower())


def resolve_output_format(
    requested_format: str, source: SourceImage, output_argument: Path | None
) -> str:
    path_format = detect_output_format_from_path(output_argument)
    chosen_format = choose_output_format(requested_format, source)

    if path_format is None:
        return chosen_format

    if requested_format in {"auto", "keep"}:
        if path_format == "WEBP" and not PIL_AVAILABLE:
            raise ValueError(
                "A .webp output file requires Pillow. Install dependencies with: pip install -r requirements.txt"
            )
        return path_format

    if chosen_format != path_format:
        raise ValueError(
            f"Output file extension '{output_argument.suffix}' conflicts with --format {requested_format}."
        )

    return chosen_format


def build_output_path(
    input_path: Path,
    output_argument: Path | None,
    output_format: str,
    name_mode: str,
    suffix: str,
) -> Path:
    explicit_file, output_directory = classify_output_argument(output_argument)
    if explicit_file is not None:
        return explicit_file

    if name_mode == "overwrite":
        if output_argument is not None:
            raise ValueError(
                "--name-mode overwrite cannot be combined with a separate output file or folder."
            )

        if EXTENSION_TO_FORMAT.get(input_path.suffix.lower()) != output_format:
            raise ValueError(
                "Overwriting the original requires a compatible format and extension. "
                "Use --format keep or choose a different name mode."
            )

        return input_path

    destination_directory = output_directory or input_path.parent
    extension = preferred_extension_for_format(input_path, output_format)

    if name_mode == "same-name":
        output_path = destination_directory / f"{input_path.stem}{extension}"
        if output_path == input_path:
            raise ValueError(
                "Saving with the same name in the same folder would overwrite the original. "
                "Choose --name-mode overwrite or pick a different output folder."
            )
        return output_path

    return destination_directory / f"{input_path.stem}{suffix}{extension}"


def can_passthrough_original(input_path: Path, output_path: Path) -> bool:
    return input_path.suffix.lower() == output_path.suffix.lower()


def write_original_to_output(input_path: Path, output_path: Path) -> None:
    if output_path == input_path:
        return

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(input_path.read_bytes())


def iter_input_files(input_path: Path) -> Iterable[Path]:
    if input_path.is_file():
        yield input_path
        return

    for path in sorted(input_path.rglob("*")):
        if path.is_file() and path.suffix.lower() in SUPPORTED_INPUT_EXTENSIONS:
            yield path


def collect_input_files(input_paths: Iterable[Path]) -> list[Path]:
    files: list[Path] = []
    seen: set[Path] = set()

    for input_path in input_paths:
        for path in iter_input_files(input_path):
            resolved = path.resolve()
            if resolved not in seen:
                seen.add(resolved)
                files.append(resolved)

    return files


def format_processing_result(result: FileProcessingResult) -> list[str]:
    if result.status == "UNCHANGED":
        return [
            f"[{result.status}] {result.input_path.name} -> {result.output_path.name} | "
            f"{human_size(result.source_size)} | {result.detail or 'kept as-is'}"
        ]

    primary_line = (
        f"[{result.status}] {result.input_path.name} -> {result.output_path.name} | "
        f"{human_size(result.source_size)} -> {human_size(result.output_size)} | "
        f"{result.width}x{result.height} | "
        f"{result.output_format} | quality={result.quality if result.quality is not None else 'n/a'}"
    )

    lines = [primary_line]
    if result.detail:
        lines.append(f"  {result.detail}")
    return lines


def parse_background(value: str) -> tuple[int, int, int]:
    text = value.strip().lstrip("#")
    if not re.fullmatch(r"[0-9a-fA-F]{6}", text):
        raise ValueError("Background must be a hex color like FFFFFF or 111111.")

    return tuple(int(text[index : index + 2], 16) for index in (0, 2, 4))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Compress images to a target file size with minimal visible loss. "
            "The tool tries quality reduction first and only resizes if needed."
        )
    )
    parser.add_argument("input", help="Input image file or a folder of images.")
    parser.add_argument(
        "output",
        nargs="?",
        help=(
            "Optional output file or folder. "
            "If omitted, the result is written next to the input file."
        ),
    )
    parser.add_argument(
        "-s",
        "--max-size",
        default="150kb",
        help="Target maximum output size, for example 150kb or 0.5mb. Default: 150kb.",
    )
    parser.add_argument(
        "--format",
        choices=["auto", "keep", "jpeg", "png", "webp"],
        default="auto",
        help=(
            "Output format. "
            "Default 'auto' prefers WebP for better quality-per-byte."
        ),
    )
    parser.add_argument(
        "--name-mode",
        choices=["suffix", "same-name", "overwrite"],
        default="suffix",
        help=(
            "How to name the output file. "
            "Default 'suffix' creates a new file like photo-compressed.jpg."
        ),
    )
    parser.add_argument(
        "--suffix",
        default="-compressed",
        help="Suffix used when --name-mode suffix. Default: -compressed.",
    )
    parser.add_argument(
        "--min-quality",
        type=int,
        default=35,
        help="Lowest quality to try before the tool starts shrinking dimensions. Default: 35.",
    )
    parser.add_argument(
        "--max-quality",
        type=int,
        default=95,
        help="Highest quality to try. Default: 95.",
    )
    parser.add_argument(
        "--min-side",
        type=int,
        default=320,
        help="Do not shrink width or height below this size. Default: 320.",
    )
    parser.add_argument(
        "--keep-metadata",
        action="store_true",
        help="Keep EXIF and ICC metadata. Off by default because metadata increases file size.",
    )
    parser.add_argument(
        "--background",
        default="FFFFFF",
        help="Background hex color used if a transparent image is saved as JPEG. Default: FFFFFF.",
    )
    parser.add_argument(
        "--keep-dimensions",
        action="store_true",
        help="Never resize width/height. If target size cannot be reached, returns best effort at original dimensions.",
    )
    return parser


def validate_args(args: argparse.Namespace) -> None:
    if args.min_quality < 1 or args.min_quality > 100:
        raise ValueError("--min-quality must be between 1 and 100.")
    if args.max_quality < 1 or args.max_quality > 100:
        raise ValueError("--max-quality must be between 1 and 100.")
    if args.min_quality > args.max_quality:
        raise ValueError("--min-quality cannot be greater than --max-quality.")
    if args.min_side < 1:
        raise ValueError("--min-side must be at least 1.")
    if args.name_mode == "suffix" and args.suffix == "":
        raise ValueError("--suffix cannot be empty when --name-mode suffix is used.")


def process_one_file(
    input_path: Path,
    output_argument: Path | None,
    args: argparse.Namespace,
) -> FileProcessingResult:
    source = load_source_image(input_path)
    target_bytes = parse_size_to_bytes(args.max_size)
    source_size = input_path.stat().st_size

    output_format = resolve_output_format(args.format, source, output_argument)
    keep_dimensions = bool(getattr(args, "keep_dimensions", False))
    output_path = build_output_path(
        input_path=input_path,
        output_argument=output_argument,
        output_format=output_format,
        name_mode=args.name_mode,
        suffix=args.suffix,
    )
    passthrough_allowed = can_passthrough_original(input_path, output_path)
    background_color = parse_background(args.background)

    if source_size <= target_bytes and args.format in {"auto", "keep"} and passthrough_allowed:
        write_original_to_output(input_path, output_path)
        return FileProcessingResult(
            input_path=input_path,
            output_path=output_path,
            source_size=source_size,
            output_size=source_size,
            width=source.width,
            height=source.height,
            output_format=source.detected_format,
            quality=None,
            status="UNCHANGED",
            detail="already under target",
            met_target=True,
        )

    if PIL_AVAILABLE:
        result = compress_source_image(
            source=source,
            target_bytes=target_bytes,
            output_format=output_format,
            min_quality=args.min_quality,
            max_quality=args.max_quality,
            min_side=args.min_side,
            keep_dimensions=keep_dimensions,
            keep_metadata=args.keep_metadata,
            background_color=background_color,
        )
    else:
        result = compress_source_image_with_sips(
            source=source,
            target_bytes=target_bytes,
            output_format=output_format,
            min_quality=args.min_quality,
            max_quality=args.max_quality,
            min_side=args.min_side,
            keep_dimensions=keep_dimensions,
        )

    if (
        args.format in {"auto", "keep"}
        and passthrough_allowed
        and result.size_bytes >= source_size
    ):
        write_original_to_output(input_path, output_path)

        status = "UNCHANGED" if source_size <= target_bytes else "BEST EFFORT"
        detail = (
            "recompressed version was larger, so the original was kept"
            if source_size <= target_bytes
            else "could not beat the original file size while staying within the tool limits"
        )
        return FileProcessingResult(
            input_path=input_path,
            output_path=output_path,
            source_size=source_size,
            output_size=source_size,
            width=source.width,
            height=source.height,
            output_format=source.detected_format,
            quality=None,
            status=status,
            detail=detail,
            met_target=source_size <= target_bytes,
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(result.data)
    detail = None
    if not result.met_target:
        detail = (
            f"Could not reach the requested max size of {human_size(target_bytes)} "
            + (
                "without resizing dimensions."
                if keep_dimensions
                else "without going below the minimum settings."
            )
        )

    return FileProcessingResult(
        input_path=input_path,
        output_path=output_path,
        source_size=source_size,
        output_size=result.size_bytes,
        width=result.width,
        height=result.height,
        output_format=result.output_format,
        quality=result.quality,
        status="OK" if result.met_target else "BEST EFFORT",
        detail=detail,
        met_target=result.met_target,
    )


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    try:
        validate_args(args)

        input_path = Path(args.input).expanduser().resolve()
        if not input_path.exists():
            raise ValueError(f"Input path does not exist: {input_path}")

        output_argument = (
            Path(args.output).expanduser().resolve() if args.output else None
        )

        if input_path.is_dir() and output_argument is not None and output_argument.suffix:
            raise ValueError(
                "When the input is a folder, the output must also be a folder."
            )

        files = collect_input_files([input_path])
        if not files:
            raise ValueError(
                "No supported images found. Supported types: "
                + ", ".join(sorted(SUPPORTED_INPUT_EXTENSIONS))
            )

        exit_code = 0
        for file_path in files:
            result = process_one_file(file_path, output_argument, args)
            for line in format_processing_result(result):
                print(line)
            if not result.met_target:
                exit_code = 1
        return exit_code

    except Exception as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
