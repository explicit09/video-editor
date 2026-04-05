"""B-Roll Library Manager — run from VideoEditor/Tools/ directory.

Usage:
    python3 broll_library.py seed --drive /Volumes/MyDrive --count 2000
    python3 broll_library.py search --drive /Volumes/MyDrive --query "cityscape"
    python3 broll_library.py stats --drive /Volumes/MyDrive
"""
from broll_library.cli import main

if __name__ == "__main__":
    main()
