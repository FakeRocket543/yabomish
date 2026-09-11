#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""產生 YabomishIM/Resources/corpus_manifest.json（語料下載清單）。

發佈流程（release workflow）：
  1. 建置語料 zip（yabomish-corpus-lite-<版本>.zip）並計算其 SHA-256。
  2. 將 zip 上傳到 GitHub Release（tag 例如 v0.3.59）。
  3. 執行本腳本，把下載網址與 SHA-256 寫入 corpus_manifest.json：
       python3 tools/make_corpus_manifest.py --tag v0.3.59 --sha256 <64碼雜湊>
  4. 重新建置輸入法（yabomish.sh 會把清單複製進 app bundle 的 Resources）。

DataDownloader 於啟動時讀取此清單取得下載網址與預期雜湊，
之後更新語料不必再修改 Swift 原始碼。
"""
import argparse
import json
import os
import re
import sys
from urllib.parse import urlparse

DEFAULT_REPO = "FakeRocket543/yabomish"



def _atomic_write(path, text):
    """寫到 .tmp 再 os.replace()，避免中斷留下半個 manifest。"""
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, path)

def derive_version(tag: str) -> str:
    """tag 去掉前導 'v' 作為版本號，例如 v0.3.59 -> 0.3.59。"""
    return tag[1:] if tag.startswith("v") else tag


def main() -> int:
    ap = argparse.ArgumentParser(
        description="產生語料下載清單 corpus_manifest.json",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("--tag", required=True,
                    help="GitHub Release tag，例如 v0.3.59")
    ap.add_argument("--url", default=None,
                    help="語料 zip 下載網址；未指定時依 tag 推導（GitHub Releases 格式）")
    ap.add_argument("--sha256", required=True,
                    help="語料 zip 的 SHA-256（64 個十六進位字元）")
    ap.add_argument("--repo", default=DEFAULT_REPO,
                    help="GitHub 儲存庫（owner/repo），用於推導預設網址")
    ap.add_argument("--version", default=None,
                    help="manifest 的 version 欄位；預設由 tag 去掉前導 v 推導")
    ap.add_argument("--file-name", dest="file_name", default=None,
                    help="manifest 的 fileName 欄位；預設取網址的檔名部分")
    ap.add_argument("--full-url", default=None,
                    help="全量語料 zip（基礎語料＋專業詞典）下載網址；未指定時依 tag 推導 "
                         "(yabomish-corpus-full-<版本>.zip)")
    ap.add_argument("--full-sha256", default=None,
                    help="全量語料 zip 的 SHA-256；提供時 manifest 寫入 full 段，"
                         "安裝時選「完整」的使用者改下載全量語料")
    ap.add_argument("--output", default=os.path.join("YabomishIM", "Resources",
                                                     "corpus_manifest.json"),
                    help="輸出路徑")
    args = ap.parse_args()

    # 驗證 SHA-256：必須是 64 個十六進位字元
    sha = args.sha256.strip().lower()
    if not re.fullmatch(r"[0-9a-f]{64}", sha):
        ap.error("--sha256 必須是 64 個十六進位字元，收到：%r" % args.sha256)

    # 推導網址與版本
    version = args.version if args.version else derive_version(args.tag)
    if args.url:
        url = args.url
    else:
        url = ("https://github.com/%s/releases/download/%s/yabomish-corpus-lite-%s.zip"
               % (args.repo, args.tag, version))

    # 網址基本健檢：scheme 必須是 https，避免寫入壞清單或明文傳輸
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.netloc:
        ap.error("--url 必須是 https：%r" % url)

    file_name = args.file_name if args.file_name else os.path.basename(parsed.path)

    manifest = {
        "version": version,
        "url": url,
        "sha256": sha,
        "fileName": file_name,
    }

    if args.full_sha256:
        fsha = args.full_sha256.strip().lower()
        if not re.fullmatch(r"[0-9a-f]{64}", fsha):
            ap.error("--full-sha256 必須是 64 個十六進位字元：%r" % fsha)
        full_url = args.full_url if args.full_url else (
            "https://github.com/%s/releases/download/%s/yabomish-corpus-full-%s.zip"
            % (args.repo, args.tag, version))
        fparsed = urlparse(full_url)
        if fparsed.scheme != "https" or not fparsed.netloc:
            ap.error("--full-url 必須是 https：%r" % full_url)
        manifest["full"] = {
            "url": full_url,
            "sha256": fsha,
            "fileName": os.path.basename(fparsed.path),
        }

    out_dir = os.path.dirname(os.path.abspath(args.output))
    os.makedirs(out_dir, exist_ok=True)
    _atomic_write(args.output, json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")

    print("已寫入 %s" % args.output)
    print("  version : %s" % manifest["version"])
    print("  url     : %s" % manifest["url"])
    print("  sha256  : %s" % manifest["sha256"])
    print("  fileName: %s" % manifest["fileName"])
    if "full" in manifest:
        print("  full.url : %s" % manifest["full"]["url"])
        print("  full.sha256: %s" % manifest["full"]["sha256"])
    print("下一步：重新執行 yabomish.sh 建置，把清單帶進 app bundle。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
