import os
import sys
import time
import threading
import shutil
import re
import glob
import subprocess

FLAVOR_NAME = 'Dev'
FLAVOR_BUILD = 'Release'

# Người nhận bản thử trên Firebase App Distribution — danh sách email cách nhau dấu phẩy; ghi đè bằng ASC_TESTER_EMAILS.
TESTER_EMAILS = os.environ.get("ASC_TESTER_EMAILS", "asctechsoft888@gmail.com")

FIREBASE_APP_ID = ""

PATH_APK = "build/app/outputs/flutter-apk"
SERVICE_ACCOUNT_JSON_PATH = ''

BUILD_VERSION = 0
BUILD_NUMBER = 0
VERSION_NAME = ""

GIT_USER = None


def _increment_build_version(version_code):
    """Read build_version.txt, increment version minor (reset if version_code changed).
    Returns version_minor after increment. Creates the file if it doesn't exist."""
    if not os.path.exists('build_version.txt'):
        with open('build_version.txt', 'w') as f:
            f.write(f'1({version_code})')
        print(f"✅ Created build_version.txt with: 1({version_code})")
        return 1

    with open('build_version.txt', 'r') as f:
        content = f.readline().strip()

    version_minor = 1
    file_version_code = None

    match = re.match(r'(\d+)\((\d+)\)', content)
    if match:
        version_minor = int(match.group(1))
        file_version_code = int(match.group(2))
    else:
        try:
            version_minor = int(content)
        except ValueError:
            version_minor = 1

    if str(file_version_code) != str(version_code):
        version_minor = 1
        print("⚠️  Version code mismatch or missing. Resetting version minor to 1")
    else:
        version_minor += 1
        print(f"✅ Incremented version minor: {version_minor - 1} -> {version_minor}")

    with open('build_version.txt', 'w') as f:
        f.write(f'{version_minor}({version_code})')
    print(f"✅ Updated build_version.txt: {version_minor}({version_code})")
    return version_minor


def func_up_version_name():
    global BUILD_VERSION, BUILD_NUMBER, VERSION_NAME
    version_minor = _increment_build_version(BUILD_NUMBER)
    VERSION_NAME = "1." + str(BUILD_NUMBER) + '.' + str(version_minor)


def func_get_build_version_and_number():
    global BUILD_VERSION, BUILD_NUMBER
    # Update the patch version (z) in version: x.y.z+a in pubspec.yaml, increment z by 1
    pubspec_path = 'pubspec.yaml'
    with open(pubspec_path, 'r') as f:
        lines = f.readlines()
    for i, line in enumerate(lines):
        if line.strip().startswith('version:'):
            import re
            match = re.match(r'(version:\s*)(\d+)\.(\d+)\.(\d+)\+(\d+)', line.strip())
            if match:
                major = match.group(2)
                minor = match.group(3)
                patch = int(match.group(4)) + 1
                build = match.group(5)
                BUILD_NUMBER = build
            break

    # Read or create build_version.txt
    if not os.path.exists('build_version.txt'):
        # Create new file with format: 1(versionCode)
        with open('build_version.txt', 'w') as f:
            f.write(f'0({BUILD_NUMBER})')
            f.close()
        print(f"✅ Created build_version.txt with: 1({BUILD_NUMBER})")
    else:
        with open('build_version.txt', 'r') as f:
            content = f.readline().strip()
            f.close()

    with open('build_version.txt', 'r') as f:
        BUILD_VERSION = '1.' + BUILD_NUMBER + '.' + f.readline()
        f.close()


def _get_git_uncommitted_summary():
    """Gather git uncommitted changes stats and return a formatted summary with emojis."""
    lines = []

    try:
        result = subprocess.run(
            ['git', 'diff', '--stat', '--ignore-submodules', 'HEAD'],
            capture_output=True, text=True, check=False
        )
        diff_stat = result.stdout.strip()

        files_changed = 0
        insertions = 0
        deletions = 0
        if diff_stat:
            summary_line = diff_stat.splitlines()[-1]
            m_files = re.search(r'(\d+) files? changed', summary_line)
            m_ins = re.search(r'(\d+) insertions?\(\+\)', summary_line)
            m_del = re.search(r'(\d+) deletions?\(-\)', summary_line)
            if m_files:
                files_changed = int(m_files.group(1))
            if m_ins:
                insertions = int(m_ins.group(1))
            if m_del:
                deletions = int(m_del.group(1))

        result = subprocess.run(
            ['git', 'diff', '--name-only', '--ignore-submodules', 'HEAD'],
            capture_output=True, text=True, check=False
        )
        changed_files = [f for f in result.stdout.strip().splitlines() if f.strip()]

        result = subprocess.run(
            ['git', 'ls-files', '--others', '--exclude-standard'],
            capture_output=True, text=True, check=False
        )
        untracked_files = [f for f in result.stdout.strip().splitlines() if f.strip()]

        result = subprocess.run(
            ['git', 'rev-parse', '--abbrev-ref', 'HEAD'],
            capture_output=True, text=True, check=False
        )
        branch = result.stdout.strip() if result.returncode == 0 else 'unknown'

        result = subprocess.run(
            ['git', 'rev-parse', '--short', 'HEAD'],
            capture_output=True, text=True, check=False
        )
        commit_hash = result.stdout.strip() if result.returncode == 0 else 'unknown'

        total_lines = insertions + deletions
        lines.append(f"🔀 Branch: {branch} ({commit_hash})")
        lines.append(f"📁 Files changed: {files_changed}")
        if untracked_files:
            lines.append(f"✨ New files: {len(untracked_files)}")
        lines.append(f"📊 Lines changed: {total_lines}")
        lines.append(f"  ➕ Insertions: +{insertions}")
        lines.append(f"  ➖ Deletions: -{deletions}")

        ext_count = {}
        for f in changed_files + untracked_files:
            ext = os.path.splitext(f)[1] if os.path.splitext(f)[1] else '(no ext)'
            ext_count[ext] = ext_count.get(ext, 0) + 1
        if ext_count:
            top_exts = sorted(ext_count.items(), key=lambda x: x[1], reverse=True)[:5]
            ext_str = ', '.join(f"{ext}({cnt})" for ext, cnt in top_exts)
            lines.append(f"🗂 File types: {ext_str}")

        if changed_files:
            lines.append(f"📌 Top changes:")
            for f in changed_files[:3]:
                lines.append(f"  • {f}")

    except Exception as e:
        lines.append(f"⚠️ Could not read git info: {e}")

    return '\n'.join(lines)


def func_release_note():
    # Ensure .gitignore entries
    if os.path.exists('.gitignore'):
        with open('.gitignore', 'r') as f:
            gitignore_lines = f.readlines()

        entries_to_add = []
        for entry in ['build_release_notes.txt', 'build_version.txt']:
            if entry not in gitignore_lines and entry + '\n' not in gitignore_lines:
                entries_to_add.append(entry)
        if entries_to_add:
            with open('.gitignore', 'a') as f:
                for entry in entries_to_add:
                    f.write('\n' + entry)

    # Build header line
    header = '[' + FLAVOR_NAME + '_' + FLAVOR_BUILD + '_' + time.strftime('%H:%M')
    if GIT_USER:
        header += ' by ' + GIT_USER
    header += ']'

    # Get git uncommitted summary
    git_summary = _get_git_uncommitted_summary()

    # Overwrite release notes file
    with open('build_release_notes.txt', 'w', encoding='utf-8') as f:
        f.write(header + '\n')
        f.write(git_summary + '\n')


def distribute_apks():
    global GIT_USER, TESTER_EMAILS, FIREBASE_APP_ID, SERVICE_ACCOUNT_JSON_PATH
    # apk_file_prefix = "app-arm64-v8a-"
    apk_file_prefix = "app-"
    apk_path = os.path.join(PATH_APK, apk_file_prefix + FLAVOR_NAME.lower() + "-" + FLAVOR_BUILD.lower() + ".apk")
    if not os.path.exists(apk_path):
        print(f"APK not found: {apk_path}")
        return
    # Point Firebase CLI at the release notes file directly (--release-notes-file)
    # instead of reading it into a string and passing it inline via
    # --release-notes. On Windows, "firebase" resolves to firebase.CMD, and
    # subprocess.run() has to hand cmd.exe a single command-line string — a
    # multi-line value (release notes always have line breaks: branch, files
    # changed, etc.) gets cut at the first newline, silently dropping every
    # flag after --release-notes. That's why --testers never reached the CLI
    # ("no testers or groups specified, skipping") even though TESTER_EMAILS
    # was correct — the release notes text ate it.
    release_notes_file = "build_release_notes.txt"
    if not os.path.exists(release_notes_file):
        with open(release_notes_file, "w", encoding='utf-8') as f:
            f.write("No release note")
    print(f"Distributing {apk_path}...")
    cmd = [
        "firebase", "appdistribution:distribute", apk_path,
        "--app", FIREBASE_APP_ID,
        "--release-notes-file", release_notes_file,
        "--testers", TESTER_EMAILS
    ]

    # Set up environment with service account credentials
    env = os.environ.copy()
    if SERVICE_ACCOUNT_JSON_PATH and os.path.exists(SERVICE_ACCOUNT_JSON_PATH):
        env["GOOGLE_APPLICATION_CREDENTIALS"] = SERVICE_ACCOUNT_JSON_PATH
        print(f"Using service account: {SERVICE_ACCOUNT_JSON_PATH}")
    else:
        print("⚠️  Warning: SERVICE_ACCOUNT_JSON_PATH not set or file not found. Using default Firebase authentication.")

    print("Distributing APKs cmd: " + ' '.join(cmd) + " ...")
    firebase_exe = shutil.which("firebase") or "firebase"
    run_cmd = [firebase_exe] + cmd[1:]
    result = subprocess.run(
        run_cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=env,
    )
    print(result.stdout)
    if result.returncode != 0:
        print(f"Error distributing {apk_path}: {result.stderr}")


def func_flutter_build_apk():
    # Resolve executable so Windows finds flutter.bat when not using shell
    flutter_exe = shutil.which("flutter")
    if not flutter_exe:
        print("Error: 'flutter' not found in PATH. Install Flutter SDK and add it to PATH.")
        sys.exit(1)
    cmd = [flutter_exe, "build", "apk",
           "--flavor", FLAVOR_NAME.lower(), "--" + FLAVOR_BUILD.lower(),
           "--build-name", VERSION_NAME,
           "--build-number", BUILD_NUMBER,
           "--target-platform", "android-arm64",
           # "--split-per-abi"
           ]
    print("Building APKs cmd: " + ' '.join(cmd) + " ...")
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    print(result.stdout)
    if result.returncode != 0:
        print(f"Error building APKs: {result.stderr}")
        sys.exit(1)


def func_get_app_name():
    """App name: tên file .code-workspace nếu có, không thì `name:` trong pubspec.yaml."""
    try:
        for file in os.listdir('.'):
            if file.endswith('.code-workspace'):
                return file.replace('.code-workspace', '')
        with open('pubspec.yaml', 'r', encoding='utf-8') as f:
            for line in f:
                m = re.match(r'name:\s*(\S+)', line)
                if m:
                    return m.group(1)
        return "Unknown App"
    except Exception as e:
        print(f"❌ Error getting app name: {e}")
        return "Unknown App"


# Telegram: token/chat id đọc từ biến môi trường — KHÔNG hardcode vào repo. Thiếu thì bỏ qua thông báo Telegram.
_TELEGRAM_BOT_TOKEN = os.environ.get("ASC_TELEGRAM_BOT_TOKEN", "")
_TELEGRAM_CHAT_ID  = os.environ.get("ASC_TELEGRAM_CHAT_ID", "")

# Email config — set via main_build() params
_EMAIL_TO       = ""
_EMAIL_FROM     = ""
_EMAIL_PASSWORD = ""  # Gmail App Password (Settings → Security → App Passwords)


def func_send_notification(message):
    """Send build notification to Telegram (AscTech Bot)."""
    if not _TELEGRAM_BOT_TOKEN or not _TELEGRAM_CHAT_ID:
        print("⚠️  Telegram skipped — set ASC_TELEGRAM_BOT_TOKEN / ASC_TELEGRAM_CHAT_ID")
        return
    try:
        import urllib.request
        import urllib.parse

        api_url = f"https://api.telegram.org/bot{_TELEGRAM_BOT_TOKEN}/sendMessage"
        data = urllib.parse.urlencode({
            'chat_id': _TELEGRAM_CHAT_ID,
            'text': message
        }).encode('utf-8')

        req = urllib.request.Request(api_url, data=data)
        with urllib.request.urlopen(req, timeout=10) as response:
            if response.getcode() == 200:
                print("✅ Telegram notification sent")
            else:
                print(f"❌ Telegram failed: {response.getcode()}")
    except Exception as e:
        print(f"❌ Telegram error: {e}")


def func_send_email(subject, body):
    """Send build notification email via Gmail SMTP."""
    if not _EMAIL_PASSWORD or not _EMAIL_FROM or not _EMAIL_TO:
        print("⚠️  Email skipped — EMAIL_FROM / EMAIL_PASSWORD not configured")
        return
    try:
        import smtplib
        from email.mime.text import MIMEText
        from email.mime.multipart import MIMEMultipart

        msg = MIMEMultipart()
        msg['From']    = _EMAIL_FROM
        msg['To']      = _EMAIL_TO
        msg['Subject'] = subject
        msg.attach(MIMEText(body, 'plain', 'utf-8'))

        with smtplib.SMTP('smtp.gmail.com', 587) as server:
            server.ehlo()
            server.starttls()
            server.login(_EMAIL_FROM, _EMAIL_PASSWORD)
            server.sendmail(_EMAIL_FROM, _EMAIL_TO, msg.as_string())
        print(f"✅ Email sent → {_EMAIL_TO}")
    except Exception as e:
        print(f"❌ Email error: {e}")


def timed_input(timeout_seconds: int) -> str:
    """Get user input with timeout. Uses threading for Windows compatibility (select doesn't support stdin on Windows)."""
    result = [None]  # mutable container so the thread can store the value

    def read_input():
        try:
            result[0] = input().strip()
        except (EOFError, OSError):
            result[0] = ""

    prompt_base = "Enter number"
    print(f"{prompt_base} (auto-exit in {timeout_seconds}s): ", end="", flush=True)
    thread = threading.Thread(target=read_input, daemon=True)
    thread.start()
    thread.join(timeout=timeout_seconds)
    if thread.is_alive():
        print("\nNo input. Exiting.")
        sys.exit(0)
    print("")
    return result[0] if result[0] is not None else ""


def show_build_config_menu():
    """Show menu for selecting flavor and build type combination"""
    MENU_OPTIONS = [
        ("🚫 NoAds Debug    🐛", "Alpha",   "Debug"),
        ("🚫 NoAds Release  ✅", "Alpha",   "Release"),
        ("🛠️  Dev Debug      🐛", "Dev",     "Debug"),
        ("🛠️  Dev Release    ✅", "Dev",     "Release"),
        ("🚀 Product Debug   🐛", "Product", "Debug"),
        ("🚀 Product Release ✅", "Product", "Release"),
    ]
    menu_choice_translate = len(MENU_OPTIONS) + 1

    print("\n=== Select Build Configuration ===\n")
    for idx, (label, _, _) in enumerate(MENU_OPTIONS, start=1):
        print(f"{idx:>2}. {label}")
    print(f"{menu_choice_translate:>2}. 🌐 Translate")
    print(f"{0:>2}. 🔴 Exit")
    print("")

    try:
        user_input = timed_input(15)
        choice = int(user_input)
    except Exception:
        print("Invalid input")
        sys.exit(1)

    if choice == 0:
        sys.exit(0)

    if choice == menu_choice_translate:
        return None, None  # Signal to run translate

    if choice < 1 or choice > len(MENU_OPTIONS):
        print("Invalid choice")
        sys.exit(1)

    _, flavor, build_type = MENU_OPTIONS[choice - 1]
    return flavor, build_type


def _run_translate():
    """Run the translation script."""
    # Remove 'translate' from argv so argparse in translate.main() doesn't choke
    original_argv = sys.argv
    sys.argv = [sys.argv[0]] + sys.argv[2:]  # skip 'translate' arg
    try:
        from translate import main as translate_main
        translate_main()
    finally:
        sys.argv = original_argv


def _check_translations():
    """Check for untranslated strings and print summary."""
    try:
        from translate import print_untranslated_check
        print_untranslated_check()
    except Exception as e:
        print(f"⚠️  Translation check skipped: {e}")

def main_build(
        sys,
        firebase_app_id_prod,
        firebase_app_id_dev,
        tester_emails = None,
        # Service account của Firebase App Distribution: file build_auth.json ở thư mục project (đã gitignore),
        # hoặc đường dẫn trong GOOGLE_APPLICATION_CREDENTIALS.
        service_account_json_path = os.environ.get(
            'GOOGLE_APPLICATION_CREDENTIALS',
            os.path.join(os.getcwd(), 'build_auth.json'),
        ),
        # Email báo build xong (Gmail App Password) — chỉ từ biến môi trường, không ghi vào file nào trong repo.
        email_to       = os.environ.get("ASC_BUILD_EMAIL_TO", ""),
        email_from     = os.environ.get("ASC_BUILD_EMAIL_FROM", ""),
        email_password = os.environ.get("ASC_BUILD_EMAIL_PASSWORD", ""),
    ):
    global FLAVOR_NAME, FLAVOR_BUILD, PATH_APK, TESTER_EMAILS, FIREBASE_APP_ID, GIT_USER, SERVICE_ACCOUNT_JSON_PATH
    global _EMAIL_TO, _EMAIL_FROM, _EMAIL_PASSWORD
    _EMAIL_TO       = email_to
    _EMAIL_FROM     = email_from
    _EMAIL_PASSWORD = email_password
    if service_account_json_path is not None:
        SERVICE_ACCOUNT_JSON_PATH = service_account_json_path
    if firebase_app_id_prod == "" or firebase_app_id_prod is None:
        raise Exception("Firebase App ID must be provided.")

    # Store both IDs; the correct one will be selected after flavor is determined
    _firebase_app_id_prod = firebase_app_id_prod
    _firebase_app_id_dev = firebase_app_id_dev

    if tester_emails is not None:
        TESTER_EMAILS = tester_emails

    if len(sys.argv) > 1:
        # Handle "translate" command directly from CLI
        if sys.argv[1].lower() == "translate":
            _run_translate()
            return

        FLAVOR_NAME = "" + sys.argv[1]
    else:
        # Show menu to select flavor and build type combination
        FLAVOR_NAME, FLAVOR_BUILD = show_build_config_menu()

    # Handle Translate option (from menu)
    if FLAVOR_NAME is None and FLAVOR_BUILD is None:
        _run_translate()
        return

    if len(sys.argv) > 2:
        FLAVOR_BUILD = "" + sys.argv[2]

    # cap first letter of FLAVOR_NAME
    if len(FLAVOR_NAME) > 0:
        FLAVOR_NAME = FLAVOR_NAME[0].upper() + (FLAVOR_NAME[1:] if len(FLAVOR_NAME) > 1 else "")
    if len(FLAVOR_BUILD) > 0:
        FLAVOR_BUILD = FLAVOR_BUILD[0].upper() + (FLAVOR_BUILD[1:] if len(FLAVOR_BUILD) > 1 else "")

    # Select Firebase App ID based on flavor
    if FLAVOR_NAME.lower() == "product" or FLAVOR_NAME.lower() == "prod":
        FIREBASE_APP_ID = _firebase_app_id_prod
    elif _firebase_app_id_dev:
        FIREBASE_APP_ID = _firebase_app_id_dev
    else:
        FIREBASE_APP_ID = _firebase_app_id_prod

    # Check untranslated strings before build
    _check_translations()

    try:
        for file in os.listdir(PATH_APK):
            if file.endswith(".apk") or file.endswith(".sha1"):
                os.remove(os.path.join(PATH_APK, file))
                print('DELETE ' + os.path.join(PATH_APK, file))
    except:
        print('FOUND NO APK FILE TO DELETE')

    # Get git user email or name
    try:
        # Try to get email first
        result = subprocess.run(['git', 'config', 'user.email'],
                                capture_output=True, text=True, check=False)
        if result.returncode == 0 and result.stdout.strip():
            GIT_USER = result.stdout.strip()
        else:
            # Fallback to name if email not found
            result = subprocess.run(['git', 'config', 'user.name'],
                                    capture_output=True, text=True, check=False)
            if result.returncode == 0 and result.stdout.strip():
                GIT_USER = result.stdout.strip()
    except Exception:
        # If git command fails, continue without user info
        pass

    func_get_build_version_and_number()
    func_up_version_name()
    func_release_note()
    git_summary = _get_git_uncommitted_summary()
    func_flutter_build_apk()
    distribute_apks()
    # func_open_folder()

    # Check if APK files exist in the path (build succeeded)
    apk_files_exist = False
    apk_size_mb = 0
    try:
        for file in os.listdir(PATH_APK):
            if file.endswith(".apk"):
                apk_files_exist = True
                apk_path = os.path.join(PATH_APK, file)
                apk_size_bytes = os.path.getsize(apk_path)
                apk_size_mb = round(apk_size_bytes / (1024 * 1024), 2)
                break
    except:
        apk_files_exist = False

    # Check untranslated strings after build
    _check_translations()

    app_name = func_get_app_name()
    message = f"🏃 {app_name} v{VERSION_NAME} — Build xong rồi! 🎉"
    message  += f"\n🏷 [{FLAVOR_NAME}_{FLAVOR_BUILD}] by {GIT_USER}"
    message  += f"\n📦 APK Size: {apk_size_mb} MB"
    message  += f"\n\n{git_summary}"

    if apk_files_exist:
        print(message)
        func_send_notification(message)
        func_send_email(f"✅ {app_name} Build Completed [{FLAVOR_NAME}_{FLAVOR_BUILD}]", message)
    else:
        fail_msg = f"💥 {app_name} — Build thất bại!\nNo APK generated by {GIT_USER}"
        print(fail_msg)
        func_send_notification(fail_msg)
        func_send_email(f"❌ {app_name} Build Failed [{FLAVOR_NAME}_{FLAVOR_BUILD}]", fail_msg)
