#!/usr/bin/env python3
"""
Split a text file containing SQL code fences into numbered migration files.

Example:
    python scripts/split_sql_migrations.py path/to/source.txt

This will create files like 001.sql, 002.sql, ... in the current working
directory (or another directory via --output-dir) containing the SQL for each
```sql ... ``` block found in the input file.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Iterable, List

SQL_BLOCK_PATTERN = re.compile(r"```sql\s*([\s\S]*?)```", re.IGNORECASE)


def extract_sql_blocks(source_text: str) -> List[str]:
    """Return the contents of each ```sql ... ``` block from the given text."""
    blocks: List[str] = []

    for match in SQL_BLOCK_PATTERN.finditer(source_text):
        content = match.group(1)

        # Trim a single leading newline (typical inside fenced blocks) while
        # preserving indentation and intentional leading spaces.
        if content.startswith("\n"):
            content = content[1:]

        # Drop trailing whitespace-only lines while ensuring a newline at EOF.
        content = content.rstrip()
        blocks.append(content + "\n")

    return blocks


def write_blocks(
    blocks: Iterable[str],
    output_dir: Path,
    prefix: str,
    digits: int,
    force: bool,
) -> List[Path]:
    """Write SQL blocks to sequentially numbered files."""
    written_paths: List[Path] = []
    output_dir.mkdir(parents=True, exist_ok=True)

    for index, block in enumerate(blocks, start=1):
        filename = f"{prefix}{index:0{digits}d}.sql"
        target_path = output_dir / filename

        if target_path.exists() and not force:
            raise FileExistsError(
                f"Refusing to overwrite existing file: {target_path}"
            )

        target_path.write_text(block, encoding="utf-8")
        written_paths.append(target_path)

    return written_paths


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Extract SQL code blocks (```sql ... ``` fences) from a text file "
            "and write each block to a sequentially numbered .sql file."
        )
    )
    parser.add_argument(
        "source",
        type=Path,
        help="Path to the text file that contains SQL code fences.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path.cwd(),
        help="Directory to store the generated .sql files (default: CWD).",
    )
    parser.add_argument(
        "--prefix",
        default="",
        help="Optional filename prefix applied before the number (default: '').",
    )
    parser.add_argument(
        "--padding",
        type=int,
        default=None,
        help=(
            "Number of digits to use for numbering (default: max(3, digits needed))."
        ),
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite existing files if they already exist.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if not args.source.is_file():
        print(f"Source file not found: {args.source}", file=sys.stderr)
        return 1

    source_text = args.source.read_text(encoding="utf-8")
    blocks = extract_sql_blocks(source_text)

    if not blocks:
        print(
            "No SQL code fences (```sql ... ```) found in the source file.",
            file=sys.stderr,
        )
        return 1

    digits = args.padding or max(3, len(str(len(blocks))))

    try:
        written_paths = write_blocks(
            blocks=blocks,
            output_dir=args.output_dir.resolve(),
            prefix=args.prefix,
            digits=digits,
            force=args.force,
        )
    except FileExistsError as exc:
        print(exc, file=sys.stderr)
        return 1

    for path in written_paths:
        print(path)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

