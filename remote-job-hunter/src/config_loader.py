from pathlib import Path
from typing import Union


def load_markdown_files(data_dir: Union[str, Path] = "data") -> dict[str, str]:
    """Load every markdown file in the data directory."""
    directory = Path(data_dir)
    configs: dict[str, str] = {}

    for file_path in sorted(directory.glob("*.md")):
        configs[file_path.stem] = file_path.read_text(encoding="utf-8")

    return configs
