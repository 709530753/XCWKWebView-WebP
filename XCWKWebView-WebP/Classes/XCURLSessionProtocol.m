
#import "XCURLSessionProtocol.h"
#import <SDWebImageWebPCoder/UIImage+WebP.h>
#import <WebKit/WebKit.h>

static NSString *URLProtocolHandledKey = @"URLHasHandle";

@interface XCURLSessionProtocol()<NSURLSessionDelegate,NSURLSessionDataDelegate>

@property (nonatomic,strong) NSURLSession *session;

@property (strong, nonatomic) NSMutableData *imageData;

@property (nonatomic) BOOL beginAppendData;

@end

@implementation XCURLSessionProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *scheme = [[request URL] scheme];
    if ( (([scheme caseInsensitiveCompare:@"http"] == NSOrderedSame ||
           [scheme caseInsensitiveCompare:@"https"] == NSOrderedSame)) &&
        ([[request.URL absoluteString] hasSuffix:@"webp"])) {
        if ([NSURLProtocol propertyForKey:URLProtocolHandledKey inRequest:request]) {
            return NO;
        }
        return YES;
    }
    return NO;
}

+ (NSURLRequest *) canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSMutableURLRequest *mutableReqeust = [[self request] mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:URLProtocolHandledKey inRequest:mutableReqeust];
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[NSOperationQueue currentQueue]];
    [[self.session dataTaskWithRequest:mutableReqeust] resume];
    
}

- (void)stopLoading {
    [self.session invalidateAndCancel];
}

#pragma mark - dataDelegate
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)newRequest
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    NSMutableURLRequest *    redirectRequest;
    
    redirectRequest = [newRequest mutableCopy];
    [[self class] removePropertyForKey:URLProtocolHandledKey inRequest:redirectRequest];
    
    [[self client] URLProtocol:self wasRedirectedToRequest:redirectRequest redirectResponse:response];
    
    [self.session invalidateAndCancel];
    [[self client] URLProtocol:self didFailWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]];
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    NSInteger expected = response.expectedContentLength > 0 ? (NSInteger)response.expectedContentLength : 0;
    self.imageData = [[NSMutableData alloc] initWithCapacity:expected];
    if (completionHandler) {
        completionHandler(NSURLSessionResponseAllow);
    }
    
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data{
    
    if ([dataTask.currentRequest.URL.absoluteString hasSuffix:@"webp"]) {
        self.beginAppendData = YES;
        [self.imageData appendData:data];
    }
    if (!_beginAppendData) {
        [self.client URLProtocol:self didLoadData:data];
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error {
    
    if (error) {
        [self.client URLProtocol:self didFailWithError:error];
    } else {
        if ([task.currentRequest.URL.absoluteString hasSuffix:@"webp"]) {
            UIImage *imgData = [self isWebP:self.imageData] ? [UIImage sd_imageWithWebPData:self.imageData] : [UIImage imageWithData:self.imageData];
            NSData *transData = UIImageJPEGRepresentation(imgData, 0.8f);
            self.beginAppendData = NO;
            self.imageData = nil;
            [self.client URLProtocol:self didLoadData:transData];
        }
        [self.client URLProtocolDidFinishLoading:self];
    }
    
}

- (BOOL)isWebP:(NSData *)data {
    uint8_t c;
    [data getBytes:&c length:1];
    switch (c) {
        case 0x52: {
            if (data.length < 12) {
                return NO;
            }
            NSString *identifierTypeStr = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, 12)] encoding:NSASCIIStringEncoding];
            if ([identifierTypeStr hasPrefix:@"RIFF"] && [identifierTypeStr hasSuffix:@"WEBP"]) {
                return YES;
            }
            return NO;
        }
        default:
            break;
    }
    return NO;
}

@end

/**
 * The functions below use some undocumented APIs, which may lead to rejection by Apple.
 */

FOUNDATION_STATIC_INLINE Class ContextControllerClass() {
    static Class cls;
    if (!cls) {
        cls = [[[WKWebView new] valueForKey:@"browsingContextController"] class];
    }
    return cls;
}

FOUNDATION_STATIC_INLINE SEL RegisterSchemeSelector() {
    return NSSelectorFromString(@"registerSchemeForCustomProtocol:");
}

FOUNDATION_STATIC_INLINE SEL UnregisterSchemeSelector() {
    return NSSelectorFromString(@"unregisterSchemeForCustomProtocol:");
}

@implementation NSURLProtocol (XCWebView)

/**
NSURLProtocol registerScheme

@param scheme 【http/https】
*/
+ (void)xc_web_registerScheme:(NSString *)scheme {
    Class cls = ContextControllerClass();
    SEL sel = RegisterSchemeSelector();
    if ([(id)cls respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [(id)cls performSelector:sel withObject:scheme];
#pragma clang diagnostic pop
    }
}

/**
NSURLProtocol webView销毁的时候注销Scheme

@param scheme 【http/https】
*/
+ (void)xc_web_unregisterScheme:(NSString *)scheme {
    Class cls = ContextControllerClass();
    SEL sel = UnregisterSchemeSelector();
    if ([(id)cls respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [(id)cls performSelector:sel withObject:scheme];
#pragma clang diagnostic pop
    }
}

+ (void)xcWebviewRegister {
    [self registerClass:XCURLSessionProtocol.class];
    [self xc_web_registerScheme:@"http"];
    [self xc_web_registerScheme:@"https"];
}

+ (void)xcWebviewUnregister {
    [self unregisterClass:XCURLSessionProtocol.class];
    [self xc_web_unregisterScheme:@"http"];
    [self xc_web_unregisterScheme:@"https"];
}

@end
