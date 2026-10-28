// CGEvent 鍵盤注入 — live e2e 用。每個 arg 是一個事件:
//   "k57"       keycode 57 down+up(caps lock → flagsChanged)
//   "d56"/"u56" 只 down / 只 up(shift 按住/放開)
//   "k0:shift"  keycode 0 down+up 並帶 shift flag
//   "--notify"  廣播 com.yabomish.prefsChanged(通知 IM 重讀 pref)
//   "--sleep N" 睡 N 秒
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <notify.h>

static CGEventFlags parseFlags(NSString *s) {
    CGEventFlags f = 0;
    for (NSString *t in [s componentsSeparatedByString:@","]) {
        if ([t isEqual:@"shift"]) f |= kCGEventFlagMaskShift;
        else if ([t isEqual:@"caps"]) f |= kCGEventFlagMaskAlphaShift;
        else if ([t isEqual:@"cmd"]) f |= kCGEventFlagMaskCommand;
        else if ([t isEqual:@"ctrl"]) f |= kCGEventFlagMaskControl;
        else if ([t isEqual:@"opt"]) f |= kCGEventFlagMaskAlternate;
    }
    return f;
}

static void post(CGKeyCode code, BOOL down, CGEventFlags flags) {
    CGEventRef ev = CGEventCreateKeyboardEvent(NULL, code, down);
    CGEventSetFlags(ev, flags);
    CGEventPost(kCGHIDEventTap, ev);
    CFRelease(ev);
    usleep(30000); // 30ms 讓 IM/系統消化
}

int main(int argc, char **argv) {
    @autoreleasepool {
        for (int i = 1; i < argc; i++) {
            NSString *a = [NSString stringWithUTF8String:argv[i]];
            if ([a isEqual:@"--notify"]) {
                notify_post("com.yabomish.prefsChanged");
                continue;
            }
            if ([a isEqual:@"--notify-tis"]) {
                notify_post("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged");
                continue;
            }
            if ([a hasPrefix:@"--sleep"]) {
                usleep((useconds_t)([[a substringFromIndex:7] doubleValue] * 1e6));
                continue;
            }
            NSArray *parts = [a componentsSeparatedByString:@":"];
            NSString *op = parts[0];
            CGEventFlags fl = parts.count > 1 ? parseFlags(parts[1]) : 0;
            unichar o = [op characterAtIndex:0];
            CGKeyCode code = (CGKeyCode)[[op substringFromIndex:1] intValue];
            if (o == 'd') post(code, YES, fl);
            else if (o == 'u') post(code, NO, fl);
            else { post(code, YES, fl); post(code, NO, fl); }
        }
    }
    return 0;
}
