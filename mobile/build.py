"""Build tự động STRIDE: APK → Firebase App Distribution, báo kết quả qua Telegram/email.

Chạy từ thư mục `mobile/`:
    python build.py                 # hiện menu chọn flavor + kiểu build
    python build.py dev release     # không menu (flavor: alpha | dev | product | claude; kiểu: debug | release)
    python build.py translate       # chạy tool dịch chuỗi XML
    python tool/build_aab.py        # AAB bản Product để lên store

Không có secret trong file này — mọi khóa/mật khẩu lấy từ biến môi trường hoặc file đã gitignore:
    build_auth.json (hoặc GOOGLE_APPLICATION_CREDENTIALS)  service account Firebase App Distribution
    ASC_TESTER_EMAILS                                       email tester, cách nhau dấu phẩy
    ASC_TELEGRAM_BOT_TOKEN, ASC_TELEGRAM_CHAT_ID            thông báo Telegram (tùy chọn)
    ASC_BUILD_EMAIL_FROM / _TO / _PASSWORD                  thông báo email Gmail App Password (tùy chọn)
Xem docs/build.md.
"""

import json
import os
import sys

PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(PROJECT_DIR)
sys.path.insert(0, os.path.join(PROJECT_DIR, "tool"))

from build_helper import main_build  # noqa: E402


def firebase_app_id() -> str:
    """App ID Firebase (1:<số>:android:<hash>) đọc từ google-services.json — không hardcode vào script."""
    path = os.path.join(PROJECT_DIR, "android", "app", "google-services.json")
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)["client"][0]["client_info"]["mobilesdk_app_id"]
    except (OSError, KeyError, IndexError, ValueError) as e:
        raise SystemExit(f"Không đọc được Firebase App ID từ {path}: {e}")


if __name__ == "__main__":
    app_id = firebase_app_id()
    main_build(
        sys=sys,
        firebase_app_id_prod=app_id,
        firebase_app_id_dev=app_id,  # cùng một app Firebase cho mọi flavor (cùng applicationId)
    )
