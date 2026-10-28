// 對每個符合 ID 的 TIS 物件逐一 TISDisableInputSource，報數。
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>
int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *target = [NSString stringWithUTF8String:argv[1]];
        CFArrayRef list = TISCreateInputSourceList(NULL, true);
        int n = 0;
        for (CFIndex i = 0; i < CFArrayGetCount(list); i++) {
            TISInputSourceRef src = (TISInputSourceRef)CFArrayGetValueAtIndex(list, i);
            NSString *sid = (__bridge NSString *)TISGetInputSourceProperty(src, kTISPropertyInputSourceID);
            if (![sid hasPrefix:target]) continue;
            NSString *type = (__bridge NSString *)TISGetInputSourceProperty(src, kTISPropertyInputSourceType);
            OSStatus e = TISDisableInputSource(src);
            NSLog(@"disable %@ %@ -> %d", type, sid, (int)e);
            n++;
        }
        NSLog(@"total %d objects", n);
    }
    return 0;
}
