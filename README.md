# LumaShrink

LumaShrink is a native macOS media optimizer plus a three-file web trial. It compresses images and videos toward a target size while preserving as much visual quality as the target allows.

Important note: compressing a `12 MB` image to `150 KB` with *exactly the same* quality is not always possible. What this tool does is aim for the best visual quality it can while staying under the target size. It reduces compression quality first, and only shrinks image dimensions if that is necessary.

## Features

- Targets a max file size such as `150kb`
- Prefers `WebP` by default because it usually keeps better quality at small sizes
- Works on a single image or an entire folder
- Includes a local drag-and-drop desktop app
- Tries to preserve the original dimensions before resizing
- Can keep the original format if you want
- Skips recompression when the original file is already under the target size
- Can save with the same original filename in another folder
- Can overwrite the original file if you explicitly choose that mode

## Setup

On macOS, the script can already run with the built-in `sips` backend for JPEG and PNG output.

Install Pillow if you want the better `WebP` path:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Launch the app

Double-click [launch_app.command](</Users/nour/Downloads/Compressing Image/launch_app.command>) on macOS, or run:

```bash
cd "/Users/nour/Downloads/Compressing Image"
./launch_app.command
```

The app stays local on your machine. It does not upload your images anywhere.
The first launch may take a little longer because it creates a local `.venv` and installs the GUI dependencies.

## Launch the website and free trial

```bash
./launch_web.command
```

Before a paid launch, configure the checkout and signed desktop download URLs shown in `.env.example`. The website uses `/buy` and `/download` as stable handoff routes, so providers can be changed without editing landing-page links.

```bash
cp .env.example .env
# Replace every example value in .env, then:
./launch_web.command
```

The web trial accepts up to three files per session. Files are processed by the server running the trial and removed within two hours. The native Mac app processes files locally.

Run the launch smoke test before each deployment:

```bash
./scripts/verify_launch.sh
./scripts/verify_release_media.sh
```

## Build a release archive

```bash
./.venv/bin/python -m pip install -r requirements-build.txt
./create_desktop_launcher.sh
```

This creates `dist/LumaShrink-macOS.zip`. The development script uses ad-hoc signing; public distribution still requires Developer ID signing and Apple notarization. See `LAUNCH_CHECKLIST.md`.

After configuring the real URLs, Developer ID identity, notarization profile, DNS, and support mailbox in `.env`, build the public artifact with:

```bash
./scripts/build_public_release.sh
```

That command fails before building if any public-launch prerequisite is missing, then signs, notarizes, staples, verifies, and checksums the release.

If the Desktop launcher ever fails, check:

```text
~/Library/Logs/Image Compressor.log
```

## Usage

### Desktop app

1. Open `launch_app.command`
2. Drag images or folders into the app
3. Pick a max size like `150kb`
4. Choose how to save:
   - `suffix`: creates `photo-compressed.jpg`
   - `same-name`: keeps the original filename in a different output folder
   - `overwrite`: replaces the original file in place
5. Click `Compress`

### CLI

Compress one image to `150 KB`:

```bash
python3 compress_image.py /path/to/image.jpg -s 150kb
```

Write the result to a specific file:

```bash
python3 compress_image.py /path/to/image.jpg /path/to/output.webp -s 150kb --format webp
```

Compress every image inside a folder:

```bash
python3 compress_image.py /path/to/folder /path/to/output-folder -s 150kb
```

Keep the same format instead of converting to WebP:

```bash
python3 compress_image.py /path/to/image.png -s 150kb --format keep
```

Force JPEG output:

```bash
python3 compress_image.py /path/to/image.png -s 150kb --format jpeg
```

Keep the same original filename in a different folder:

```bash
python3 compress_image.py /path/to/image.png /path/to/output-folder -s 150kb --name-mode same-name --format keep
```

Overwrite the original file in place:

```bash
python3 compress_image.py /path/to/image.png -s 150kb --name-mode overwrite --format keep
```

## Useful options

- `--format auto|keep|jpeg|png|webp`
- `--name-mode suffix|same-name|overwrite`
- `--suffix -compressed`
- `--min-quality 35`
- `--max-quality 95`
- `--min-side 320`
- `--keep-metadata`
- `--background FFFFFF`

## How it works

1. The tool loads the image and fixes EXIF orientation.
2. It tries to hit the size limit by lowering compression quality.
3. If quality alone is not enough, it gradually reduces the dimensions.
4. It avoids rewriting files when the original is already small enough.
5. It supports suffix, same-name, or overwrite save modes.
6. It saves the best result that meets the size limit, or the closest possible result if the limit cannot be reached.

## Example

```bash
python3 compress_image.py ./photo.jpg -s 150kb --format auto
```

Example output:

```text
[OK] photo.jpg -> photo-compressed.webp | 12.00 MB -> 147.84 KB | 2400x1600 | WEBP | quality=81
```
