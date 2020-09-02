
#import <Foundation/Foundation.h>

@interface XCURLSessionProtocol : NSURLProtocol

@end


@interface NSURLProtocol (XCWebView)

/// 注册
+ (void)xcWebviewRegister;

/// 注销
+ (void)xcWebviewUnregister;

@end
