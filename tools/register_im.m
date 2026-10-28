// TISRegisterInputSource 覆蓋安裝後系統不會自動重掃 bundle；
// 顯式註冊讓新 Info.plist/mode 表立即生效（issue: 輸入法選單消失/輪替跳過）。
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>
int main(int argc, char **argv){
    const char *path = argc > 1 ? argv[1] : "/Library/Input Methods/YabomishIM.app";
    NSURL *u = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
    OSStatus e = TISRegisterInputSource((CFURLRef)u);
    NSLog(@"TISRegisterInputSource %s -> %d", path, (int)e);
    return (int)e;
}
