#!/usr/bin/env python3
"""Install/remove '加入自訂字庫' macOS Quick Action for Yabomish.

Generates a .workflow bundle that lets users select text anywhere,
right-click → Services → 加入自訂字庫, appending to user_phrases.txt.

Usage:
    python3 tools/install_quick_action.py          # install
    python3 tools/install_quick_action.py --remove  # uninstall
"""
import os, sys, plistlib, shutil
from pathlib import Path

WORKFLOW_NAME = "加入自訂字庫"
SERVICES_DIR = Path.home() / "Library" / "Services"
WORKFLOW_PATH = SERVICES_DIR / f"{WORKFLOW_NAME}.workflow"
PHRASES_PATH = "~/Library/Application Support/Yabomish/user_phrases.txt"

SHELL_SCRIPT = f"""#!/usr/bin/env python3
import sys, os

path = os.path.expanduser("{PHRASES_PATH}")
text = sys.stdin.read().strip()
if not text or len(text) < 2:
    os.system('osascript -e \\'display notification "需要至少 2 個字" with title "自訂字庫"\\'')
    sys.exit(0)

os.makedirs(os.path.dirname(path), exist_ok=True)
existing = set()
if os.path.exists(path):
    with open(path, "r", encoding="utf-8") as f:
        existing = {{l.strip() for l in f}}

if text in existing:
    os.system(f'osascript -e \\'display notification "已存在: {{text}}" with title "自訂字庫"\\'')
else:
    with open(path, "a", encoding="utf-8") as f:
        f.write(text + "\\n")
    os.system(f'osascript -e \\'display notification "已加入: {{text}}" with title "自訂字庫"\\'')
"""

INFO_PLIST = {
    "CFBundleDevelopmentRegion": "zh_TW",
    "CFBundleIdentifier": "com.yabomishim.service.addphrase",
    "CFBundleName": WORKFLOW_NAME,
    "CFBundleShortVersionString": "1.0",
    "NSServices": [{
        "NSMenuItem": {"default": WORKFLOW_NAME},
        "NSMessage": "runWorkflowAsService",
        "NSSendTypes": ["public.utf8-plain-text"],
    }],
}

DOCUMENT_PLIST = {
    "AMApplicationBuild": "523",
    "AMApplicationVersion": "2.10",
    "AMDocumentVersion": "2",
    "actions": [{"action": {
        "AMAccepts": {"Container": "List", "Optional": True, "Types": ["com.apple.cocoa.string"]},
        "AMActionVersion": "2.0.3",
        "AMApplication": ["Automator"],
        "AMBundleIdentifier": "com.apple.RunShellScript",
        "AMProvides": {"Container": "List", "Types": ["com.apple.cocoa.string"]},
        "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
        "ActionName": "Run Shell Script",
        "ActionParameters": {
            "COMMAND_STRING": SHELL_SCRIPT,
            "CheckedForUserDefaultShell": True,
            "inputMethod": 0,
            "shell": "/usr/bin/env",
            "source": "",
        },
        "BundleIdentifier": "com.apple.RunShellScript",
        "CFBundleVersion": "2.0.3",
        "CanShowSelectedItemsWhenRun": True,
        "CanShowWhenRun": False,
        "Class Name": "RunShellScriptAction",
        "InputUUID": "00000000-0000-0000-0000-000000000000",
        "OutputUUID": "00000000-0000-0000-0000-000000000001",
        "UUID": "00000000-0000-0000-0000-000000000002",
        "arguments": {
            "0": {"default value": "/bin/sh", "name": "shell", "required": "0", "type": "0", "uuid": "0"},
            "1": {"default value": "", "name": "COMMAND_STRING", "required": "0", "type": "0", "uuid": "1"},
            "2": {"default value": 0, "name": "inputMethod", "required": "0", "type": "0", "uuid": "2"},
            "3": {"default value": "", "name": "source", "required": "0", "type": "0", "uuid": "3"},
        },
        "isViewVisible": True,
        "location": "309.500000:253.000000",
        "nibPath": "/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib",
    }}],
    "connectors": {},
    "workflowMetaData": {
        "inputTypeIdentifier": "com.apple.Automator.text",
        "outputTypeIdentifier": "com.apple.Automator.nothing",
        "presentationMode": 15,
        "serviceInputTypeIdentifier": "com.apple.Automator.text",
        "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
        "workflowTypeIdentifier": "com.apple.Automator.servicesMenu",
    },
}


def install():
    if WORKFLOW_PATH.exists():
        shutil.rmtree(WORKFLOW_PATH)
    contents = WORKFLOW_PATH / "Contents"
    resources = contents / "Resources"
    resources.mkdir(parents=True)
    with open(contents / "Info.plist", "wb") as f:
        plistlib.dump(INFO_PLIST, f)
    with open(contents / "version.plist", "wb") as f:
        plistlib.dump({"BuildVersion": "1", "CFBundleVersion": "1",
                        "ProjectName": "Automator", "SourceVersion": "523"}, f)
    with open(resources / "document.wflow", "wb") as f:
        plistlib.dump(DOCUMENT_PLIST, f)
    print(f"✅ 已安裝: {WORKFLOW_PATH}")
    print(f"   字庫: {PHRASES_PATH}")
    print(f"   用法: 選取文字 → 右鍵 → Services → {WORKFLOW_NAME}")


def remove():
    if WORKFLOW_PATH.exists():
        shutil.rmtree(WORKFLOW_PATH)
        print(f"✅ 已移除: {WORKFLOW_PATH}")
    else:
        print("ℹ️  未安裝，無需移除。")


if __name__ == "__main__":
    remove() if "--remove" in sys.argv else install()
