// 列出符合 ID 的 TIS 輸入來源狀態。用法: probe_im <substr>
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>
int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *target = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"com.yabomishim.inputmethod.YabomishIMDev";
        CFArrayRef list = TISCreateInputSourceList(NULL, true);
        for (CFIndex i = 0; i < CFArrayGetCount(list); i++) {
            TISInputSourceRef src = (TISInputSourceRef)CFArrayGetValueAtIndex(list, i);
            NSString *sid = (__bridge NSString *)TISGetInputSourceProperty(src, kTISPropertyInputSourceID);
            if (![sid containsString:target]) continue;
            NSString *type = (__bridge NSString *)TISGetInputSourceProperty(src, kTISPropertyInputSourceType);
            NSString *cat = (__bridge NSString *)TISGetInputSourceProperty(src, kTISPropertyInputSourceCategory);
            NSNumber *en = (__bridge NSNumber *)TISGetInputSourceProperty(src, kTISPropertyInputSourceIsEnabled);
            NSNumber *cap = (__bridge NSNumber *)TISGetInputSourceProperty(src, kTISPropertyInputSourceIsSelectCapable);
            NSNumber *sel = (__bridge NSNumber *)TISGetInputSourceProperty(src, kTISPropertyInputSourceIsSelected);
            NSLog(@"id=%@ type=%@ cat=%@ enabled=%@ capable=%@ selected=%@", sid, type, cat, en, cap, sel);
        }
    }
    return 0;
}
