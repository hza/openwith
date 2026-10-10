// Open With (openwith) — browse installed apps and the file types / URL schemes they claim.
#import "Controller.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;
        Controller *c = [Controller new];
        app.delegate = c;
        [app run];
    }
    return 0;
}
