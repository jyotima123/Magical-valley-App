"""
Bumps the app version and build number in pubspec.yaml, then scaffolds a
matching release_notes/<version>.md file with instructions for filling it in.

Usage: python bump_version.py [major|minor|patch]
  Defaults to 'patch'. The build number (the +N suffix) always increments by 1
  regardless of which part is bumped, matching Android's monotonic versionCode
  requirement.
"""
import os
import re
import sys

RELEASE_NOTES_TEMPLATE = '''# {version}

<!--
RELEASE NOTES FORMAT (for whoever/whatever fills this in, human or AI):

1. Top section (right below the H1, before "# Detailed Changes"): a flat
   bullet list of every user-facing change in this release, one bullet per
   change:
     - <Type>: <one-line description of the change and its user-visible effect>
   <Type> is one of: Feature, Fix, Feature (QA), Fix (QA). Use the "(QA)"
   suffix only for changes gated behind the QA/staging environment and not
   yet shown in production. Order roughly by user impact, most important
   first.

2. "# Detailed Changes" section: one "### <Area> (`path/to/file.ext`[, new])"
   subsection per significant file or module touched — append ", new" only
   if the file is new in this release. Under each heading, bullet points
   explain WHAT changed and WHY (the reasoning or tradeoff), not just a
   restatement of the diff.

3. Optional trailing "# Follow-ups / action required" section: bullets for
   any manual steps needed before/after shipping (env vars to fill in,
   migrations to run), known gaps deliberately left out of scope, or
   deferred work worth revisiting later. Omit the whole section if there
   is nothing to flag.

Base the content on `git log` / `git diff` against the previous release tag
or the last release_notes/*.md file (if any exist) — do not invent changes
that aren't actually in the diff. Delete this comment block once the
sections below are filled in with real content.
-->

-

# Detailed Changes

###
'''


def main():
    part = sys.argv[1] if len(sys.argv) > 1 else 'patch'
    if part not in ('major', 'minor', 'patch'):
        print(f'Usage: python {os.path.basename(__file__)} [major|minor|patch]')
        sys.exit(1)

    project_dir = os.path.join(os.path.dirname(__file__), '..')
    pubspec_path = os.path.join(project_dir, 'pubspec.yaml')
    release_dir = os.path.join(project_dir, 'release_notes')

    with open(pubspec_path, 'r', encoding='utf-8') as f:
        pubspec = f.read()

    match = re.search(
        r'^version:[ \t]*(\d+)\.(\d+)\.(\d+)\+(\d+)[ \t]*$', pubspec, re.MULTILINE
    )
    if not match:
        print('ERROR: Could not find a "version: X.Y.Z+B" line in pubspec.yaml')
        sys.exit(1)

    major, minor, patch, build = (int(g) for g in match.groups())
    old_version = f'{major}.{minor}.{patch}+{build}'

    if part == 'major':
        major, minor, patch = major + 1, 0, 0
    elif part == 'minor':
        minor, patch = minor + 1, 0
    else:
        patch += 1
    build += 1

    new_version = f'{major}.{minor}.{patch}'
    release_path = os.path.join(release_dir, f'{new_version}.md')
    if os.path.exists(release_path):
        print(f'ERROR: {release_path} already exists — not overwriting')
        sys.exit(1)

    new_pubspec = (
        pubspec[: match.start()]
        + f'version: {new_version}+{build}'
        + pubspec[match.end() :]
    )
    with open(pubspec_path, 'w', encoding='utf-8') as f:
        f.write(new_pubspec)
    print(f'pubspec.yaml: {old_version} -> {new_version}+{build}')

    os.makedirs(release_dir, exist_ok=True)
    with open(release_path, 'w', encoding='utf-8') as f:
        f.write(RELEASE_NOTES_TEMPLATE.format(version=new_version))
    print(f'Created {release_path}')


if __name__ == '__main__':
    main()
