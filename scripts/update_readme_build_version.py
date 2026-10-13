"""
Updates the Android or iOS build version in README.md
Usage: python update_readme_build_version.py <android|ios>
Reads version from pubspec.yaml and stamps it into the matching placeholder.
"""
import sys
import os
import re

def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ('android', 'ios'):
        print(f'Usage: {sys.argv[0]} <android|ios>')
        sys.exit(1)

    platform = sys.argv[1]
    project_dir = os.path.join(os.path.dirname(__file__), '..')
    pubspec_path = os.path.join(project_dir, 'pubspec.yaml')
    readme_path = os.path.join(project_dir, 'README.md')

    # Read version from pubspec.yaml
    with open(pubspec_path, 'r', encoding='utf-8') as f:
        pubspec = f.read()

    match = re.search(r'^version:\s*(\S+)', pubspec, re.MULTILINE)
    if not match:
        print('ERROR: Could not find version in pubspec.yaml')
        sys.exit(1)

    # Extract just the version name (strip build number like +99)
    version = match.group(1).split('+')[0]
    print(f'{platform.capitalize()} build version: {version}')

    # Update the matching placeholder in README.md
    tag = 'ANDROID_VERSION' if platform == 'android' else 'IOS_VERSION'
    pattern = rf'(<!-- {tag}_START -->).*?(<!-- {tag}_END -->)'
    replacement = rf'\g<1>{version}\g<2>'

    with open(readme_path, 'r', encoding='utf-8') as f:
        readme = f.read()

    new_readme, count = re.subn(pattern, replacement, readme)
    if count == 0:
        print(f'ERROR: Could not find {tag} markers in README.md')
        sys.exit(1)

    with open(readme_path, 'w', encoding='utf-8') as f:
        f.write(new_readme)

    print(f'README.md updated: {platform} -> {version}')

if __name__ == '__main__':
    main()
