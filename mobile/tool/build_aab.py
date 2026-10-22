#!/usr/bin/env python3
import os
import shutil
import sys
import subprocess
import re

# Thư mục tool/ chứa build_helper.py; project root (có pubspec.yaml) là thư mục cha.
tool_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, tool_dir)
os.chdir(os.path.dirname(tool_dir))

# Import from build_helper
import build_helper

def open_aab_folder():
    """Open the AAB output folder"""
    aab_folder = os.path.join("build", "app", "outputs", "bundle", "productRelease")
    aab_path = os.path.realpath(aab_folder)
    
    if os.path.exists(aab_path):
        print(f"📂 Opening: {aab_path}")
        if sys.platform == 'win32':
            os.startfile(aab_path)
        else:
            os.system(f'open "{aab_path}"')
    else:
        print(f"⚠️  Folder not found: {aab_path}")

def build_aab():
    """Build Android App Bundle (AAB) for Production flavor"""
    # Get build version and number
    build_helper.func_get_build_version_and_number()
    
    # Extract clean version name (remove parentheses part like (19))
    # BUILD_VERSION format is like "1.19.7(19)", we want "1.19.7"
    build_version_clean = build_helper.BUILD_VERSION.split('(')[0].strip()
    
    # Build AAB with version info
    cmd = [
        shutil.which("flutter") or "flutter", "build", "appbundle",
        "--flavor", "product",
        "--release",
        "--build-name", build_version_clean,
        "--build-number", build_helper.BUILD_NUMBER
    ]
    
    # ex: flutter build appbundle --flavor Product --release --build-name 1.19.7 --build-number 19
    print(f"Building AAB cmd: {' '.join(cmd)} ...")
    print(f"Build Name: {build_version_clean}")
    print(f"Build Number: {build_helper.BUILD_NUMBER}")
    
    result = subprocess.run(cmd, capture_output=False, text=True)
    
    if result.returncode != 0:
        print(f"❌ Error building AAB")
        sys.exit(1)
    else:
        print(f"✅ AAB build completed successfully")
        open_aab_folder()

if __name__ == "__main__":
    build_aab()
