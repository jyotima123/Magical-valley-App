"""
Updates the "Latest Release" section in README.md
with the content of the most recent release_notes/*.md file.
"""
import os
import re
import glob

def main():
    project_dir = os.path.join(os.path.dirname(__file__), '..')
    release_dir = os.path.join(project_dir, 'release_notes')
    readme_path = os.path.join(project_dir, 'README.md')

    # Find latest version file, sorted by version tuple (so 1.10.0 > 1.9.0)
    files = glob.glob(os.path.join(release_dir, '*.md'))
    version_files = []
    for f in files:
        name = os.path.basename(f)
        if name == 'TODO.md':
            continue
        parts = name.replace('.md', '').split('.')
        try:
            version_tuple = tuple(int(p) for p in parts)
            version_files.append((version_tuple, f))
        except ValueError:
            continue

    version_files.sort()
    if not version_files:
        print('ERROR: No version files found in release_notes/')
        exit(1)

    latest_file = version_files[-1][1]
    print(f'Latest release: {os.path.basename(latest_file)}')

    with open(latest_file, 'r', encoding='utf-8') as f:
        raw = f.read()

    # Only include content before "# Detailed Changes"
    split = re.split(r'\n#\s+Detailed Changes\b', raw, maxsplit=1)
    notes = split[0].strip()

    with open(readme_path, 'r', encoding='utf-8') as f:
        readme = f.read()

    pattern = r'(<!-- LATEST_RELEASE_START -->).*?(<!-- LATEST_RELEASE_END -->)'
    replacement = r'\1\n' + notes + r'\n\2'
    new_readme = re.sub(pattern, replacement, readme, flags=re.DOTALL)

    with open(readme_path, 'w', encoding='utf-8') as f:
        f.write(new_readme)

    print('README.md release section updated successfully')

if __name__ == '__main__':
    main()
