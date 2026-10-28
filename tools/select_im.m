// 依 InputSourceID enable＋select 輸入來源：dev e2e 免開系統設定。
// 帶 input modes 的 IM：container（ModeEnabled）要 enable，
// 實際 select 要選它的 mode（TISTypeKeyboardInputMode）。
// 用法: select_im <inputSourceID> [modeID]
//   e.g. select_im com.yabomishim.inputmethod.YabomishIMDev
//        select_im com.yabomishim.inputmethod.YabomishIMDev com.yabomishim.inputmethod.YabomishIMDev.English
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) {
            NSLog(@"usage: select_im <inputSourceID> [modeID]");
            return 2;
        }
        NSString *target = [NSString stringWithUTF8String:argv[1]];
        NSString *modeTarget = argc > 2 ? [NSString stringWithUTF8String:argv[2]] : target;

        // includeAllInstalled=true 才看得到「已註冊但尚未啟用」的來源
        CFArrayRef list = TISCreateInputSourceList(NULL, true);
        TISInputSourceRef container = NULL, mode = NULL, plain = NULL;
        for (CFIndex i = 0; i < CFArrayGetCount(list); i++) {
            TISInputSourceRef src = (TISInputSourceRef)CFArrayGetValueAtIndex(list, i);
            CFStringRef sid = (CFStringRef)TISGetInputSourceProperty(src, kTISPropertyInputSourceID);
            CFStringRef type = (CFStringRef)TISGetInputSourceProperty(src, kTISPropertyInputSourceType);
            if (!sid) continue;
            if (CFStringCompare(sid, (CFStringRef)target, 0) == kCFCompareEqualTo) {
                if (type && CFStringCompare(type, kTISTypeKeyboardInputMethodModeEnabled, 0) == kCFCompareEqualTo) {
                    if (!container) container = src;
                } else if (type && CFStringCompare(type, kTISTypeKeyboardInputMode, 0) == kCFCompareEqualTo) {
                    if (CFStringCompare(sid, (CFStringRef)modeTarget, 0) == kCFCompareEqualTo && !mode) mode = src;
                } else {
                    if (!plain) plain = src;
                }
            }
            // mode 的 ID 可能與 container 不同（.English 等）：獨立再比一次 modeTarget
            if (type && CFStringCompare(type, kTISTypeKeyboardInputMode, 0) == kCFCompareEqualTo
                && CFStringCompare(sid, (CFStringRef)modeTarget, 0) == kCFCompareEqualTo && !mode) {
                mode = src;
            }
        }
        TISInputSourceRef sel = mode ? mode : (plain ? plain : container);
        if (!sel) {
            NSLog(@"input source not found: %@", target);
            return 1;
        }
        OSStatus e1 = 0, em = 0, e2 = 0;
        if (container) e1 = TISEnableInputSource(container);
        if (mode) em = TISEnableInputSource(mode);
        e2 = TISSelectInputSource(sel);
        NSLog(@"container enable -> %d, mode enable -> %d, select %@ -> %d", (int)e1, (int)em,
              (__bridge NSString *)TISGetInputSourceProperty(sel, kTISPropertyInputSourceID), (int)e2);
        return (int)(e1 != 0 ? e1 : (em != 0 ? em : e2));
    }
}
