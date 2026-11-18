#!/usr/bin/env python
"""
Azure DevOps Pull Request HTML Parser

Parses saved Azure DevOps pull request HTML pages and extracts:
- PR metadata (title, branches, etc.)
- Comments with file context, line numbers, author info, and status
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional
from urllib.parse import quote


def parse_azure_date(date_value: Any) -> Optional[str]:
    """
    Parse Azure DevOps date format to ISO format.
    Azure uses /Date(timestamp)/ format where timestamp is milliseconds since epoch.
    """
    if date_value is None:
        return None

    if isinstance(date_value, str):
        # Try to parse /Date(timestamp)/ format
        match = re.match(r"/Date\((\d+)\)/", date_value)
        if match:
            timestamp_ms = int(match.group(1))
            dt = datetime.fromtimestamp(timestamp_ms / 1000, tz=timezone.utc)
            return dt.isoformat()
        # Maybe it's already ISO format
        return date_value

    return str(date_value)


# Azure DevOps thread status codes
THREAD_STATUS_MAP = {
    1: "Active",
    2: "Fixed",  # Resolved
    3: "WontFix",
    4: "Closed",
    5: "ByDesign",
    6: "Pending",
    None: "Unknown",
}

# Azure DevOps comment type codes
COMMENT_TYPE_MAP = {
    1: "Text",  # Regular comment
    2: "CodeChange",  # System comment about code change
    3: "System",  # System-generated comment
}


def extract_json_data(html_content: str) -> Optional[dict]:
    """Extract the main JSON data blob from the HTML page."""
    # Azure DevOps embeds data in a script tag with type="application/json"
    pattern = r'type="application/json">(\{"data".*?)</script>'
    matches = re.findall(pattern, html_content, re.DOTALL)

    if not matches:
        return None

    try:
        return json.loads(matches[0])
    except json.JSONDecodeError as e:
        print(f"Error parsing JSON data: {e}", file=sys.stderr)
        return None


def get_pr_detail_data(data: dict) -> Optional[dict]:
    """Extract PR detail data provider from the main data structure."""
    try:
        return data["data"]["ms.vss-code-web.pr-detail-data-provider"]
    except KeyError:
        # Try alternative key names that might exist in different versions
        for key in data.get("data", {}).keys():
            if "pr-detail" in key.lower() or "pull-request" in key.lower():
                return data["data"][key]
        return None


def extract_metadata(pr_data: dict) -> dict:
    """Extract PR metadata."""
    pr = pr_data.get("pullRequest", {})
    repo = pr.get("repository", {})
    project = repo.get("project", {})
    created_by = pr.get("createdBy", {})

    # Clean branch names (remove refs/heads/ prefix)
    source_branch = pr.get("sourceRefName", "")
    target_branch = pr.get("targetRefName", "")

    if source_branch.startswith("refs/heads/"):
        source_branch = source_branch[len("refs/heads/"):]
    if target_branch.startswith("refs/heads/"):
        target_branch = target_branch[len("refs/heads/"):]

    # Map PR status codes
    pr_status_map = {
        1: "Active",
        2: "Abandoned",
        3: "Completed",
    }

    return {
        "pull_request_id": pr.get("pullRequestId"),
        "title": pr.get("title"),
        "description": pr.get("description"),
        "source_branch": source_branch,
        "target_branch": target_branch,
        "status": pr_status_map.get(pr.get("status"), "Unknown"),
        "is_draft": pr.get("isDraft", False),
        "created_by": {
            "display_name": created_by.get("displayName"),
            "email": created_by.get("uniqueName"),
        },
        "creation_date": parse_azure_date(pr.get("creationDate")),
        "repository": {
            "name": repo.get("name"),
            "project": project.get("name"),
            "web_url": repo.get("webUrl"),
        },
        "url": pr.get("url"),
    }


def build_comment_link(metadata: dict, thread_id: int, file_path: Optional[str] = None) -> str:
    """Build a direct link to a comment thread."""
    web_url = metadata.get("repository", {}).get("web_url", "")
    pr_id = metadata.get("pull_request_id", "")

    if not web_url or not pr_id:
        return ""

    base_url = f"{web_url}/pullrequest/{pr_id}"

    if file_path:
        # Link to file with discussion highlighted
        encoded_path = quote(file_path, safe="")
        return f"{base_url}?_a=files&path={encoded_path}&discussionId={thread_id}"
    else:
        # Link to overview with discussion
        return f"{base_url}?discussionId={thread_id}"


def _extract_line_range(start_obj: dict, end_obj: dict) -> dict:
    """Helper to extract line range from start/end objects."""
    if not start_obj:
        return {}

    start_line = start_obj.get("line")
    end_line = end_obj.get("line") if end_obj else start_line

    # Handle the max int value that Azure uses for "end of line"
    if end_line and end_line >= 2147483647:
        end_line = start_line

    return {
        "start_line": start_line,
        "end_line": end_line,
    }


def extract_line_info(thread_context: dict) -> dict:
    """Extract line number information from thread context (latest diff)."""
    line_info = {}

    # Right file = new/modified lines
    if "rightFileStart" in thread_context:
        start = thread_context["rightFileStart"]
        end = thread_context.get("rightFileEnd", start)
        line_info = _extract_line_range(start, end)
        line_info["side"] = "right"  # New/modified code

    # Left file = original/deleted lines (fallback if no right)
    elif "leftFileStart" in thread_context:
        start = thread_context["leftFileStart"]
        end = thread_context.get("leftFileEnd", start)
        line_info = _extract_line_range(start, end)
        line_info["side"] = "left"  # Original/deleted code

    return line_info


def extract_original_line_info(pr_thread_context: dict) -> Optional[dict]:
    """
    Extract original line number information from pullRequestThreadContext.
    This represents where the comment was made in the original diff (iteration when comment was created).
    """
    if not pr_thread_context:
        return None

    tracking = pr_thread_context.get("trackingCriteria", {})
    if not tracking:
        return None

    original_info = {}

    # Get the iteration when the comment was made
    iter_context = pr_thread_context.get("iterationContext", {})
    if iter_context:
        original_info["iteration"] = iter_context.get("firstComparingIteration")

    # Original file path (in case it was renamed)
    orig_file_path = tracking.get("origFilePath")
    if orig_file_path:
        original_info["file_path"] = orig_file_path

    # Right file = new/modified lines in original diff
    if "origRightFileStart" in tracking:
        start = tracking["origRightFileStart"]
        end = tracking.get("origRightFileEnd", start)
        line_range = _extract_line_range(start, end)
        original_info["start_line"] = line_range.get("start_line")
        original_info["end_line"] = line_range.get("end_line")
        original_info["side"] = "right"

    # Left file = deleted lines in original diff
    elif "origLeftFileStart" in tracking:
        start = tracking["origLeftFileStart"]
        end = tracking.get("origLeftFileEnd", start)
        line_range = _extract_line_range(start, end)
        original_info["start_line"] = line_range.get("start_line")
        original_info["end_line"] = line_range.get("end_line")
        original_info["side"] = "left"

    return original_info if original_info else None


def extract_comments(pr_data: dict, metadata: dict) -> list:
    """Extract all comment threads with their details."""
    threads = pr_data.get("discussionThreads", [])
    comments_list = []

    for thread in threads:
        thread_id = thread.get("id")
        thread_context = thread.get("threadContext", {})
        pr_thread_context = thread.get("pullRequestThreadContext", {})

        # Skip deleted threads
        if thread.get("isDeleted"):
            continue

        # Get file information
        file_path = thread_context.get("filePath") if thread_context else None
        file_name = os.path.basename(file_path) if file_path else None

        # Get line information (latest diff)
        line_info = extract_line_info(thread_context) if thread_context else {}

        # Get original line information (when comment was made)
        original_line_info = extract_original_line_info(pr_thread_context)

        # Get thread status
        status_code = thread.get("status")
        status = THREAD_STATUS_MAP.get(status_code, f"Unknown ({status_code})")

        # Build comment link
        comment_link = build_comment_link(metadata, thread_id, file_path)

        # Process each comment in the thread
        thread_comments = thread.get("comments", [])

        for i, comment in enumerate(thread_comments):
            # Skip system-generated comments unless they have content
            comment_type = comment.get("commentType", 1)
            content = comment.get("content", "").strip()

            if not content:
                continue

            author = comment.get("author", {})

            comment_entry = {
                "thread_id": thread_id,
                "comment_id": comment.get("id"),
                "is_reply": i > 0,  # First comment is the original, rest are replies
                "file_name": file_name,
                "file_path": file_path,
                "lines_modified": line_info if line_info else None,
                "original_lines": original_line_info,  # Line numbers when comment was made
                "author": {
                    "display_name": author.get("displayName"),
                    "email": author.get("uniqueName"),
                },
                "content": content,
                "comment_type": COMMENT_TYPE_MAP.get(comment_type, f"Unknown ({comment_type})"),
                "status": status,
                "link": comment_link,
                "published_date": parse_azure_date(comment.get("publishedDate")),
                "last_updated_date": parse_azure_date(comment.get("lastUpdatedDate")),
            }

            comments_list.append(comment_entry)

    return comments_list


def parse_azure_pr_html(html_file_path: str) -> dict:
    """
    Parse an Azure DevOps PR HTML file and extract structured data.

    Args:
        html_file_path: Path to the saved HTML file

    Returns:
        Dictionary with metadata and comments
    """
    # Read the HTML file
    file_path = Path(html_file_path)

    if not file_path.exists():
        raise FileNotFoundError(f"File not found: {html_file_path}")

    # Try different encodings
    html_content = None
    for encoding in ["utf-8", "utf-16", "latin-1", "cp1252"]:
        try:
            html_content = file_path.read_text(encoding=encoding)
            break
        except UnicodeDecodeError:
            continue

    if html_content is None:
        raise ValueError(f"Could not decode file with any supported encoding: {html_file_path}")

    # Extract JSON data
    json_data = extract_json_data(html_content)

    if not json_data:
        raise ValueError("Could not find JSON data in HTML file. Is this an Azure DevOps PR page?")

    # Get PR detail data
    pr_data = get_pr_detail_data(json_data)

    if not pr_data:
        raise ValueError("Could not find PR detail data in JSON. The page structure may have changed.")

    # Extract metadata
    metadata = extract_metadata(pr_data)

    # Extract comments
    comments = extract_comments(pr_data, metadata)

    # Group comments by file for easier analysis
    comments_by_file = {}
    general_comments = []

    for comment in comments:
        file_path = comment.get("file_path")
        if file_path:
            if file_path not in comments_by_file:
                comments_by_file[file_path] = []
            comments_by_file[file_path].append(comment)
        else:
            general_comments.append(comment)

    return {
        "metadata": metadata,
        "comments": comments,
        "comments_by_file": comments_by_file,
        "general_comments": general_comments,
        "summary": {
            "total_comments": len(comments),
            "total_threads": len(set(c["thread_id"] for c in comments)),
            "files_with_comments": len(comments_by_file),
            "status_breakdown": _count_by_status(comments),
        },
    }


def _count_by_status(comments: list) -> dict:
    """Count comments by status."""
    status_counts = {}
    # Count by thread to avoid counting replies multiple times
    seen_threads = {}

    for comment in comments:
        thread_id = comment["thread_id"]
        if thread_id not in seen_threads:
            seen_threads[thread_id] = comment["status"]

    for status in seen_threads.values():
        status_counts[status] = status_counts.get(status, 0) + 1

    return status_counts


def _rebuild_grouped_comments(comments: list) -> tuple:
    """Rebuild comments_by_file and general_comments from filtered comments list."""
    comments_by_file = {}
    general_comments = []

    for comment in comments:
        file_path = comment.get("file_path")
        if file_path:
            if file_path not in comments_by_file:
                comments_by_file[file_path] = []
            comments_by_file[file_path].append(comment)
        else:
            general_comments.append(comment)

    return comments_by_file, general_comments


def main():
    parser = argparse.ArgumentParser(
        description="Parse Azure DevOps PR HTML pages and extract comments/metadata",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s pr_page.html
  %(prog)s pr_page.html -o output.json
  %(prog)s pr_page.html --pretty
  %(prog)s pr_page.html --filter-status Active
  %(prog)s pr_page.html --exclude-system --pretty
        """,
    )

    parser.add_argument(
        "html_file",
        help="Path to the Azure DevOps PR HTML file",
    )

    parser.add_argument(
        "-o", "--output",
        help="Output file path (default: stdout)",
    )

    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Pretty print JSON output with indentation",
    )

    parser.add_argument(
        "--filter-status",
        choices=["Active", "Fixed", "WontFix", "Closed", "ByDesign", "Pending", "Unknown"],
        help="Only include comments with the specified status",
    )

    parser.add_argument(
        "--filter-file",
        help="Only include comments for files matching this pattern (substring match)",
    )

    parser.add_argument(
        "--exclude-system",
        action="store_true",
        help="Exclude system-generated comments (branch updates, votes, etc.)",
    )

    parser.add_argument(
        "--metadata-only",
        action="store_true",
        help="Only output PR metadata, no comments",
    )

    parser.add_argument(
        "--comments-only",
        action="store_true",
        help="Only output comments, no metadata",
    )

    args = parser.parse_args()

    try:
        result = parse_azure_pr_html(args.html_file)

        # Apply filters
        filters_applied = False

        if args.exclude_system:
            result["comments"] = [
                c for c in result["comments"]
                if c["comment_type"] != "System"
            ]
            filters_applied = True

        if args.filter_status:
            result["comments"] = [
                c for c in result["comments"]
                if c["status"] == args.filter_status
            ]
            filters_applied = True

        if args.filter_file:
            result["comments"] = [
                c for c in result["comments"]
                if c.get("file_path") and args.filter_file in c["file_path"]
            ]
            filters_applied = True

        # Rebuild grouped comments and summary if filters were applied
        if filters_applied:
            result["comments_by_file"], result["general_comments"] = _rebuild_grouped_comments(result["comments"])
            result["summary"] = {
                "total_comments": len(result["comments"]),
                "total_threads": len(set(c["thread_id"] for c in result["comments"])) if result["comments"] else 0,
                "files_with_comments": len(result["comments_by_file"]),
                "status_breakdown": _count_by_status(result["comments"]),
            }

        # Select output format
        if args.metadata_only:
            output = {"metadata": result["metadata"]}
        elif args.comments_only:
            output = {"comments": result["comments"]}
        else:
            output = result

        # Format output
        indent = 2 if args.pretty else None
        json_output = json.dumps(output, indent=indent, ensure_ascii=False, default=str)

        # Write output
        if args.output:
            Path(args.output).write_text(json_output, encoding="utf-8")
            print(f"Output written to: {args.output}", file=sys.stderr)
        else:
            print(json_output)

        return 0

    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 2
    except Exception as e:
        print(f"Unexpected error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        return 3


if __name__ == "__main__":
    sys.exit(main())
