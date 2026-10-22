#!/usr/bin/env python3
"""
Android Strings Translator
Translates Android string resources via the translator_internal API server.
Run from the project root directory.

Usage:
    python translate.py                          # Translate all strings files
    python translate.py --exclude strings_ids.xml,strings_prompt.xml
    python translate.py --langs vi,ja,ko          # Translate specific languages only
    python translate.py --threads 4               # Set parallel thread count
    python translate.py --dry-run                 # Show what would be translated without doing it
    python translate.py --api-url http://your-server:3101  # Custom API server
"""

import argparse
import os
import re
import shutil
import sys
import time
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from xml.dom.minidom import parseString
from xml.etree.ElementTree import Element, SubElement, parse, tostring

import json
import socket
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError

# ========================== CONFIGURATION ==========================

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)  # Parent of tool/ = project root (thư mục chứa pubspec.yaml)
LANG_THREADS = 6
FLUSH_BATCH_SIZE = 6

# Translator API (proxy server handles all AI/Google API keys internally)
API_URL = os.environ.get("ASC_TRANSLATE_API_URL", "http://139.59.225.32:3101")

# All supported languages (Android resource folder format)
ALL_LANGUAGES = [
    'vi',
    'ar', 'ja',
    'pt-rBR', 'zh-rTW', 'es-rUS',
    'am', 'af', 'az', 'be', 'bg', 'bn', 'cs', 'da', 'de', 'el',
    'es', 'fa', 'fi',
    'fil', 'fr', 'gu', 'hi', 'hr', 'hu', 'id', 'it',
    'km', 'kn', 'ko', 'ml', 'mn',
    'mr', 'ms', 'my', 'nb', 'ne', 'nl', 'pa', 'pl', 'pt', 'ro', 'ru',
    'sr', 'sv', 'sw', 'te', 'th', 'tr', 'uk', 'ur',
    'zh-rCN', 'zh-rHK',
    'es-rMX', 'fr-rCA', 'ta',
    'en-rGB',
    'en',
]

ENGLISH_COPY_LOCALES = ['en-rCA', 'en-rAU']


# ========================== HELPERS ==========================

class Translation:
    def __init__(self, key, value_en, context=""):
        self.key = key
        self.value_en = value_en
        self.context = context


# ========================== AUTO-SCAN ==========================

def detect_res_dirs(project_dir):
    """Auto-scan for all res directories containing values/strings*.xml.
    Returns a list of absolute paths to res directories.
    """
    res_dirs = []
    for root, dirs, files in os.walk(project_dir):
        dirs[:] = [d for d in dirs if not d.startswith('.')
                   and d not in ('build', 'Pods', 'DerivedData', '.git', '.gradle',
                                 '.translate_temp', 'node_modules', '.dart_tool')]
        if os.path.basename(root) == 'values':
            has_strings = any(f.endswith('.xml') and f.startswith('strings') for f in files)
            if has_strings:
                res_dir = os.path.dirname(root)  # parent of values/
                if res_dir not in res_dirs:
                    res_dirs.append(res_dir)
    return res_dirs


# ========================== XML UTILITIES ==========================

def fix_xml_after_write(file_path):
    """Fix XML declaration quotes and restore CDATA sections for strings containing HTML."""
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Fix XML declaration quotes (single -> double)
    content = re.sub(
        r"<\?xml version='1\.0' encoding='utf-8'\?>",
        '<?xml version="1.0" encoding="utf-8"?>',
        content,
    )

    # Restore CDATA only for strings that contain escaped HTML tags (e.g. &lt;font, &lt;b&gt;)
    # NOT for strings that just have &gt; or &lt; as math/text content
    def restore_cdata(match):
        name_attr = match.group(1)
        text = match.group(2)
        # Only restore CDATA if there are actual HTML tags (opening or self-closing)
        # e.g. &lt;font, &lt;b&gt;, &lt;br/&gt; — but NOT standalone &gt; or &lt;
        if not re.search(r'&lt;/?[a-zA-Z]', text):
            return match.group(0)
        raw = text.replace('&lt;', '<').replace('&gt;', '>').replace('&amp;', '&')
        return f'<string name="{name_attr}"><![CDATA[{raw}]]></string>'

    content = re.sub(
        r'<string name="([^"]+)">([^<]*(?:&lt;|&gt;)[^<]*)</string>',
        restore_cdata,
        content,
    )

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)


def read_strings_xml(file_path):
    """Read Android strings.xml and return list of Translation objects."""
    tree = parse(file_path)
    root = tree.getroot()
    strings = []
    for string in root.findall("string"):
        context = string.attrib.get("context", "")
        key = string.attrib["name"]
        value = string.text or ""
        strings.append(Translation(key, value, context))
    return strings


def create_strings_xml(language_code, strings_dict, output_dir, output_file):
    """Create a new strings.xml file."""
    folder_name = f"values-{language_code}"
    output_path = os.path.join(output_dir, folder_name)
    os.makedirs(output_path, exist_ok=True)

    resources = Element("resources")
    for key, value in strings_dict.items():
        string_element = SubElement(resources, "string", name=key)
        string_element.text = value

    xml_string = tostring(resources, encoding="unicode")
    pretty_xml = parseString(xml_string).toprettyxml(indent="    ")

    with open(os.path.join(output_path, output_file), "w", encoding="utf-8") as file:
        file.write(pretty_xml)
    print(f"CREATED FILE: {output_path}/{output_file}")


def check_file_valid_xml(file_path):
    """Validate XML file."""
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()
        if "</resources>" not in content:
            print(f"🚨🚨🚨ERROR translated file {file_path}")
    try:
        ET.parse(file_path)
    except ET.ParseError as e:
        print(f"🚨🚨🚨Invalid XML in {file_path}: {e}")
        raise Exception(f"Invalid XML in {file_path}: {e}")


def correct_translated_text(text):
    """Fix common translation artifacts in XML text."""
    text = text.replace("'", "\\'").replace("\\\\\\'", "\\'")
    text = re.sub(r"&amp;amp;", "&amp;", text, flags=re.IGNORECASE)
    text = text.replace("&Amp;", "&").replace("&amp;", "&")
    return text


def delete_string_by_key_xml(file_path, keys):
    """Remove string elements with specified keys from XML file."""
    if not keys:
        return
    if not os.path.exists(file_path):
        return

    tree = ET.parse(file_path)
    root = tree.getroot()

    for key in keys:
        for string_element in root.findall(f"string[@name='{key}']"):
            root.remove(string_element)

    time.sleep(0.1)
    ET.indent(tree, space="    ")
    tree.write(file_path, encoding='utf-8', xml_declaration=True)
    fix_xml_after_write(file_path)
    print(f"Removed {len(keys)} keys from {file_path}")


def sort_strings_by_reference(reference_file, target_file):
    """Sort target XML strings to match reference file order."""
    reference_tree = ET.parse(reference_file)
    reference_root = reference_tree.getroot()

    target_tree = ET.parse(target_file)
    target_root = target_tree.getroot()

    target_strings = {elem.attrib['name']: elem for elem in target_root.findall('string')}
    target_root.clear()

    for ref_elem in reference_root.findall('string'):
        name = ref_elem.attrib['name']
        if name in target_strings:
            target_root.append(target_strings[name])

    ET.indent(target_tree, space="    ")
    target_tree.write(target_file, encoding='utf-8', xml_declaration=True)
    fix_xml_after_write(target_file)


# ========================== TRANSLATION VIA API ==========================

def translate_text(input_text, output_language, input_language="en",
                   translate_context="", retries=0):
    """Translate text by calling the translator_internal API server."""
    if retries > 5:
        raise Exception(f"❌ TOO MANY RETRIES for: {input_text}")

    print(f"📝 \"{input_text}\" ➡️ {output_language}")

    try:
        payload = json.dumps({
            "text": input_text,
            "input_language": input_language,
            "output_language": output_language,
            "context": translate_context,
        }).encode("utf-8")

        req = Request(
            f"{API_URL}/api/translate",
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        with urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if data.get("success"):
                translated = data["translated_text"]
                print(f"✅ \"{input_text}\" ➡️ \"{translated}\"")
                return translated
            else:
                raise Exception(data.get("error", "Unknown API error"))

    except URLError as e:
        if isinstance(e, HTTPError):
            if e.code == 401:
                raise Exception("Invalid API key")
            raise Exception(f"API error {e.code}: {e.read().decode('utf-8')}")
        if isinstance(e.reason, ConnectionRefusedError):
            print(f"🚨 Cannot connect to API server at {API_URL}")
            print(f"   Make sure the translator_internal server is running on {API_URL}")
            sys.exit(1)
        print(f"Translation failed: {e} (attempt {retries + 1})")
        time.sleep(pow(2, retries + 1))
        return translate_text(input_text, output_language, input_language,
                              translate_context, retries + 1)
    except socket.timeout:
        print(f"API timeout (attempt {retries + 1})")
        time.sleep(pow(2, retries + 1))
        return translate_text(input_text, output_language, input_language,
                              translate_context, retries + 1)
    except Exception as e:
        print(f"Translation failed: {e} (attempt {retries + 1})")
        time.sleep(pow(2, retries + 1))
        return translate_text(input_text, output_language, input_language,
                              translate_context, retries + 1)


def _flush_strings_to_xml(output_file, batch, reference_file=None):
    """Append a batch of {key: value} to an XML file in-place."""
    if not batch:
        return
    tree = ET.parse(output_file)
    root = tree.getroot()
    # Update existing or append new
    existing = {elem.attrib['name']: elem for elem in root.findall('string')}
    for key, value in batch.items():
        if key in existing:
            existing[key].text = value
        else:
            new_item = ET.Element("string")
            new_item.attrib["name"] = key
            new_item.text = value
            root.append(new_item)
    ET.indent(tree, space="    ")
    tree.write(output_file, encoding='utf-8', xml_declaration=True)
    fix_xml_after_write(output_file)


def update_strings_xml(output_file, strings, lang, dry_run=False):
    """Translate and write strings to XML file, flushing every FLUSH_BATCH_SIZE."""
    if not strings:
        return

    print(f"Update File ✏️: {output_file}  ({len(strings)} strings)")

    is_english = lang in ["en", "en-US", "en-AU", "en-CA"]
    batch = {}

    for translation in strings:
        if dry_run:
            print(f"  [DRY-RUN] Would translate: {translation.key} = {translation.value_en}")
            continue

        if is_english:
            batch[translation.key] = translation.value_en
        else:
            try:
                translated_text = translate_text(
                    input_text=translation.value_en,
                    input_language="en",
                    output_language=lang,
                    translate_context=translation.context,
                )
            except Exception as e:
                print(f"🚨 Translate error for key {translation.key}: {str(e)}")
                translated_text = ""

            if not translated_text:
                print(f"🚨 Empty translation for key {translation.key}")
                continue

            batch[translation.key] = correct_translated_text(translated_text)

        if len(batch) >= FLUSH_BATCH_SIZE:
            _flush_strings_to_xml(output_file, batch)
            print(f"💾 [{lang}] Flushed {len(batch)} strings to file")
            batch = {}

    if not dry_run and batch:
        _flush_strings_to_xml(output_file, batch)
        print(f"💾 [{lang}] Flushed {len(batch)} strings to file")


# ========================== CAPITALIZATION ==========================

def detect_capitalization_pattern(text):
    """Detect capitalization pattern: all_caps, title_case, sentence_case, lowercase, or unknown."""
    if "%1$d" in text or "%1$s" in text or "%s" in text:
        return "unknown"
    if text.lower() == "ok":
        return "unknown"
    if not text or not text.strip():
        return 'unknown'

    # Check for scripts without case distinctions (CJK, Arabic, Devanagari, Thai, etc.)
    for char in text:
        cp = ord(char)
        if (0x4E00 <= cp <= 0x9FFF or 0x3040 <= cp <= 0x309F or
            0x30A0 <= cp <= 0x30FF or 0x3000 <= cp <= 0x303F or
            0xAC00 <= cp <= 0xD7AF or 0x0600 <= cp <= 0x06FF or
            0x0590 <= cp <= 0x05FF or 0x0900 <= cp <= 0x097F or
            0x0980 <= cp <= 0x09FF or 0x0A00 <= cp <= 0x0A7F or
            0x0A80 <= cp <= 0x0AFF or 0x0B00 <= cp <= 0x0B7F or
            0x0B80 <= cp <= 0x0BFF or 0x0C00 <= cp <= 0x0C7F or
            0x0C80 <= cp <= 0x0CFF or 0x0D00 <= cp <= 0x0D7F or
            0x0E00 <= cp <= 0x0E7F or 0x0E80 <= cp <= 0x0EFF or
            0x1000 <= cp <= 0x109F or 0x10A0 <= cp <= 0x10FF or
            0x1200 <= cp <= 0x137F or 0x1780 <= cp <= 0x17FF or
            0x0530 <= cp <= 0x058F):
            return 'unknown'

    alpha_chars = [c for c in text if c.isalpha()]
    if not alpha_chars:
        return 'unknown'

    if all(c.isupper() for c in alpha_chars):
        return 'all_caps'
    if all(c.islower() for c in alpha_chars):
        return 'lowercase'

    first_alpha_idx = next((i for i, c in enumerate(text) if c.isalpha()), None)
    if first_alpha_idx is not None:
        if text[first_alpha_idx].isupper() and all(c.islower() for c in alpha_chars[1:]):
            return 'sentence_case'

    words = text.split()
    title_case_words = 0
    for word in words:
        alpha_in_word = [c for c in word if c.isalpha()]
        if alpha_in_word:
            first_alpha_idx = next(i for i, c in enumerate(word) if c.isalpha())
            if word[first_alpha_idx].isupper() and all(c.islower() for c in alpha_in_word[1:]):
                title_case_words += 1

    alpha_words = [w for w in words if any(c.isalpha() for c in w)]
    if title_case_words > 0 and title_case_words == len(alpha_words):
        return 'title_case'

    return 'unknown'


# ========================== MAIN TRANSLATION PIPELINE ==========================

def find_translatable_files(res_dir, excluded):
    """Find all strings XML files that need translation."""
    values_dir = os.path.join(res_dir, "values")
    if not os.path.exists(values_dir):
        print(f"🚨 values directory not found: {values_dir}")
        return []

    files = []
    for f in sorted(os.listdir(values_dir)):
        if not f.endswith(".xml"):
            continue
        if f in excluded:
            continue
        filepath = os.path.join(values_dir, f)
        with open(filepath, encoding="utf-8") as fh:
            content = fh.read()
            if "</string>" not in content:
                continue
            if 'translatable="false"' in content:
                continue
            if "</resources>" not in content:
                raise Exception(f"Invalid strings.xml: {f}")
        try:
            ET.parse(filepath)
        except ET.ParseError as e:
            raise Exception(f"Invalid XML in {f}: {e}")
        files.append(f)

    return files



def process_file_for_language(file_name, target_lang, res_dir, dry_run=False):
    """Process a single file for a single language, editing in-place."""
    source_file = os.path.join(res_dir, "values", file_name)
    strings_origin = read_strings_xml(source_file)

    # Read compare baseline (en-rCA or fallback to values)
    compare_file = os.path.join(res_dir, "values-en-rCA", file_name)
    if os.path.exists(compare_file) and os.path.getsize(compare_file) > 0:
        try:
            strings_compare = read_strings_xml(compare_file)
        except Exception:
            strings_compare = read_strings_xml(source_file)
    else:
        strings_compare = read_strings_xml(source_file)

    # Extract API language code
    api_lang = target_lang.replace("-r", "-")

    lang_dir = os.path.join(res_dir, f"values-{target_lang}")
    lang_file = os.path.join(lang_dir, file_name)
    if not os.path.exists(lang_file):
        os.makedirs(lang_dir, exist_ok=True)
        create_strings_xml(target_lang, {}, res_dir, file_name)

    strings_locale = read_strings_xml(lang_file)
    origin_keys = {t.key for t in strings_origin}
    locale_keys = {t.key for t in strings_locale}

    # 1. Remove keys not in origin
    keys_to_remove = [k for k in locale_keys if k not in origin_keys]
    delete_string_by_key_xml(lang_file, keys_to_remove)

    # 2. Find new (untranslated) keys
    new_strings = []
    added_keys = set()
    for t in strings_origin:
        if t.key in locale_keys:
            continue
        if t.key in added_keys:
            raise Exception(f"Duplicate key: {t.key}")
        added_keys.add(t.key)
        new_strings.append(t)
        print(f"🌐 NEW --> {t.key}: {t.value_en}")

    update_strings_xml(lang_file, new_strings, api_lang, dry_run=dry_run)

    # 3. Find changed English values
    compare_dict = {t.key: t.value_en for t in strings_compare}
    changed_strings = []
    for t in strings_origin:
        if t in new_strings:
            continue
        if t.key in compare_dict and t.value_en != compare_dict[t.key]:
            changed_strings.append(t)
            print(f"CHANGED 🌐 --> {t.key}: {compare_dict[t.key]} -> {t.value_en}")

    update_strings_xml(lang_file, changed_strings, api_lang, dry_run=dry_run)

    # 4. Fix capitalization pattern mismatches
    def count_alpha_words(text):
        if not text or not text.strip():
            return 0
        return len([w for w in text.split() if w.strip() and w.strip()[0].isalpha()])

    locale_dict = {t.key: t.value_en for t in strings_locale}
    cap_changed = []
    for t in strings_origin:
        if t in new_strings or t in changed_strings:
            continue
        cap_en = detect_capitalization_pattern(t.value_en)
        if cap_en not in ["all_caps", "lowercase", "title_case", "sentence_case"]:
            continue
        if t.key not in locale_dict:
            continue
        cap_locale = detect_capitalization_pattern(locale_dict[t.key])
        if cap_locale == "unknown":
            continue
        if cap_en in ["title_case", "sentence_case"] or cap_locale in ["title_case", "sentence_case"]:
            if count_alpha_words(t.value_en) < 2 or count_alpha_words(locale_dict[t.key]) < 2:
                continue
        if cap_en != cap_locale:
            cap_changed.append(t)
            print(f"CAP CHANGED 🌐 --> {t.key}: {cap_locale} -> {cap_en}")

    update_strings_xml(lang_file, cap_changed, api_lang, dry_run=dry_run)

    # 5. Sort by reference order
    if not dry_run:
        sort_strings_by_reference(source_file, lang_file)


def process_language(lang, files, res_dir, dry_run=False):
    """Process all files for a single language, editing in-place."""
    try:
        for f in files:
            process_file_for_language(f, lang, res_dir, dry_run=dry_run)
        print(f"✅ Completed language: {lang}")
    except Exception as e:
        print(f"❌ Error processing {lang}: {str(e)}")
        raise


def check_api_server():
    """Check if the translator API server is reachable."""
    try:
        urlopen(f"{API_URL}/", timeout=5)
        return True
    except (URLError, socket.timeout):
        return False


def _translate_res_dir(res_dir, excluded, languages, threads, dry_run):
    """Translate a single res directory, editing files in-place."""
    print(f"\n📂 Translating: {res_dir}")
    print("-" * 60)

    if not os.path.exists(os.path.join(res_dir, "values")):
        print(f"⚠️  Skipping {res_dir}/values (not found)")
        return

    files = find_translatable_files(res_dir, excluded)
    if not files:
        print("No translatable files found.")
        return

    print(f"📄 Files to translate: {files}")

    start_time = datetime.now()
    print(f"⏱️  Start: {start_time}")
    print()

    # Process languages in parallel, editing real files in-place
    with ThreadPoolExecutor(max_workers=threads) as executor:
        futures = [
            executor.submit(process_language, lang, files, res_dir, dry_run)
            for lang in languages
        ]
        for future in futures:
            future.result()

    # Update en-rCA compare baseline (copy English values as snapshot)
    if not dry_run:
        for f in files:
            src = os.path.join(res_dir, "values", f)
            for locale in ['en-rCA', 'en-rAU']:
                dst_dir = os.path.join(res_dir, f"values-{locale}")
                os.makedirs(dst_dir, exist_ok=True)
                shutil.copy2(src, os.path.join(dst_dir, f))
            print(f"📋 Updated en-rCA/en-rAU baselines for {f}")

    elapsed = datetime.now() - start_time
    print(f"\n✅ Done {res_dir}! Time: {elapsed}")


def main():
    global API_URL

    parser = argparse.ArgumentParser(description="Translate Android/Flutter string resources")
    parser.add_argument(
        "--exclude", default="strings_ids.xml",
        help="Comma-separated XML filenames to exclude (default: strings_ids.xml)",
    )
    parser.add_argument(
        "--langs", default=None,
        help="Comma-separated language codes to translate (default: all)",
    )
    parser.add_argument(
        "--threads", type=int, default=LANG_THREADS,
        help=f"Number of parallel language threads (default: {LANG_THREADS})",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Show what would be translated without actually translating",
    )
    parser.add_argument(
        "--api-url", default=API_URL,
        help=f"Translator API server URL (default: {API_URL})",
    )
    args = parser.parse_args()

    API_URL = args.api_url
    excluded = [x.strip() for x in args.exclude.split(",") if x.strip()] if args.exclude else []
    languages = ALL_LANGUAGES
    if args.langs:
        languages = [x.strip() for x in args.langs.split(",") if x.strip()]

    # Auto-scan for res directories
    dirs = detect_res_dirs(PROJECT_DIR)
    if not dirs:
        print(f"🚨 No res directories with strings XML found in: {PROJECT_DIR}")
        sys.exit(1)

    print(f"🌐 API server: {API_URL}")
    print(f"🚫 Excluded: {excluded}")
    print(f"🌍 Languages: {len(languages)}")
    print(f"🧵 Threads: {args.threads}")
    print(f"📂 Found {len(dirs)} res directory(ies):")
    for d in dirs:
        print(f"   - {os.path.relpath(d, PROJECT_DIR)}")
    if args.dry_run:
        print("🔍 DRY RUN MODE - no changes will be made")
    print()

    # Check API server connectivity (skip for dry-run)
    if not args.dry_run:
        if not check_api_server():
            print(f"🚨 Cannot connect to API server at {API_URL}")
            print(f"   Start the server first:")
            print(f"   cd /Users/admin/WorkSub/translator_internal && python app.py")
            sys.exit(1)
        print(f"✅ API server connected")

    total_start = datetime.now()

    for res_dir in dirs:
        _translate_res_dir(res_dir, excluded, languages, args.threads, args.dry_run)

    total_elapsed = datetime.now() - total_start
    print(f"\n✅ All done! Total time: {total_elapsed}")


def check_untranslated_strings():
    """Check for string IDs that need translation. Returns list of (res_dir, file, lang, key) tuples."""
    dirs = detect_res_dirs(PROJECT_DIR)
    excluded = ["strings_ids.xml"]

    # Check a representative subset of languages for missing keys
    check_languages = ['vi', 'ja', 'ko', 'zh-rCN', 'zh-rTW', 'fr', 'de', 'es', 'pt', 'ar', 'ru', 'it', 'tr', 'id', 'fa']

    missing = []
    for res_dir in dirs:
        files = find_translatable_files(res_dir, excluded)
        if not files:
            continue

        for f in files:
            source_file = os.path.join(res_dir, "values", f)
            if not os.path.exists(source_file):
                continue
            source_keys = {t.key for t in read_strings_xml(source_file)}

            for lang in check_languages:
                lang_file = os.path.join(res_dir, f"values-{lang}", f)
                if not os.path.exists(lang_file):
                    for key in source_keys:
                        missing.append((res_dir, f, lang, key))
                    continue
                lang_keys = {t.key for t in read_strings_xml(lang_file)}
                for key in source_keys:
                    if key not in lang_keys:
                        missing.append((res_dir, f, lang, key))

    return missing


def print_untranslated_check():
    """Print untranslated string IDs summary."""
    missing = check_untranslated_strings()
    if not missing:
        print("🌐 Translation check: All strings are translated.")
        return

    # Group by file and key (count how many languages missing)
    from collections import defaultdict
    by_file_key = defaultdict(set)
    for res_dir, f, lang, key in missing:
        by_file_key[(res_dir, f, key)].add(lang)

    print(f"\n🌐 Translation check: {len(by_file_key)} string(s) need translation")
    print("=" * 60)
    for (res_dir, f, key), langs in sorted(by_file_key.items()):
        dir_name = os.path.basename(os.path.dirname(os.path.dirname(os.path.dirname(res_dir))))
        print(f"  [{dir_name}] {f} -> \"{key}\" (missing in {len(langs)} lang(s))")
    print("=" * 60)
    print(f"Run 'python3 build.py translate' to translate.\n")


if __name__ == "__main__":
    main()
