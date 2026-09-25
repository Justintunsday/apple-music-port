#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

void MPLogSetFileEnabled(BOOL enabled);
void MPLogSetLogPath(NSString *path);
void MPLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
NSString *MPLogFilePath(void);
void MPLogView(UIView *view, NSString *label);

#ifdef __cplusplus
}
#endif
