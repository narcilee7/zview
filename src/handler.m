// zview Objective-C bridge handler.
// Owns ALL Cocoa/WebKit/NSWindow interactions. Exposes a tiny C ABI to Zig so
// the framework never has to @cImport Objective-C frameworks directly.

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

typedef void (*zview_on_msg_fn)(void *userdata,
                                const char *method,
                                const char *payload,
                                unsigned long long callback_id);

typedef void (*zview_on_loaded_fn)(void *userdata);

// Per-window state. Each call to zview_create produces one of these.
typedef struct {
    NSWindow    *window;
    WKWebView   *webview;
    WKUserContentController *user_controller;
    void *userdata;
    zview_on_msg_fn on_msg;
    zview_on_loaded_fn on_loaded;
} zview_window;

// NSObject subclass that bridges WKScriptMessageHandler + WKNavigationDelegate to C fns.
@interface ZviewHandler : NSObject <WKScriptMessageHandler, WKNavigationDelegate>
@property (nonatomic, assign) zview_window *win;
@end

@implementation ZviewHandler
- (void)userContentController:(WKUserContentController *)uc
     didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.body isKindOfClass:[NSString class]]) return;
    NSString *body = (NSString *)message.body;
    NSData *d = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:&err];
    if (![obj isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *dict = (NSDictionary *)obj;
    NSString *method = dict[@"method"];
    NSNumber *cid = dict[@"id"];
    if (![method isKindOfClass:[NSString class]] || ![cid isKindOfClass:[NSNumber class]]) return;
    id args = dict[@"args"] ?: @[];
    NSData *argsData = [NSJSONSerialization dataWithJSONObject:args options:0 error:nil];
    NSString *argsStr = argsData ? [[NSString alloc] initWithData:argsData encoding:NSUTF8StringEncoding] : @"[]";
    const char *argsC = [argsStr UTF8String];
    self.win->on_msg(self.win->userdata, [method UTF8String], argsC ? argsC : "[]", [cid unsignedLongLongValue]);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (self.win->on_loaded) self.win->on_loaded(self.win->userdata);
}
@end

extern zview_window *zview_create(
    void *userdata,
    zview_on_msg_fn on_msg,
    zview_on_loaded_fn on_loaded,
    const char *title,
    double width,
    double height,
    const char *html
) {
    zview_window *win = (zview_window *)calloc(1, sizeof(zview_window));
    if (!win) return NULL;
    win->userdata = userdata;
    win->on_msg = on_msg;
    win->on_loaded = on_loaded;

    // NSApp activation
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    // WKWebViewConfiguration
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    win->user_controller = [[WKUserContentController alloc] init];
    config.userContentController = win->user_controller;

    // Script message handler
    ZviewHandler *handler = [[ZviewHandler alloc] init];
    handler.win = win;
    [win->user_controller addScriptMessageHandler:handler name:@"zview"];

    // Bridge shim (injected before any page script runs)
    NSString *shimSrc = [NSString stringWithUTF8String:
        "window.__zview=(function(){"
        "  var nextId=1;"
        "  var pending=new Map();"
        "  function call(method,args){"
        "    var cid=nextId++;"
        "    return new Promise(function(resolve,reject){"
        "      pending.set(cid,{resolve:resolve,reject:reject});"
        "      window.webkit.messageHandlers.zview.postMessage(JSON.stringify({id:cid,method:method,args:args||[]}));"
        "    });"
        "  }"
        "  window.__zviewResolve=function(cid,ok,value){"
        "    var p=pending.get(cid);if(!p)return;pending.delete(cid);"
        "    if(ok)p.resolve(value);else p.reject(value);"
        "  };"
        "  return {call:call};"
        "})();"];
    WKUserScript *script = [[WKUserScript alloc] initWithSource:shimSrc
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                               forMainFrameOnly:YES];
    [win->user_controller addUserScript:script];

    // WKWebView
    NSRect frame = NSMakeRect(0, 0, width, height);
    win->webview = [[WKWebView alloc] initWithFrame:frame configuration:config];
    win->webview.navigationDelegate = handler;

    // NSWindow
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                              NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    win->window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    [win->window setTitle:[NSString stringWithUTF8String:title]];
    [win->window setContentView:win->webview];
    [win->window makeKeyAndOrderFront:nil];
    [win->window center];

    [NSApp activateIgnoringOtherApps:YES];

    // Load HTML
    NSData *htmlData = [NSData dataWithBytes:html length:strlen(html)];
    [win->webview loadData:htmlData
                  MIMEType:@"text/html"
      characterEncodingName:@"utf-8"
                    baseURL:nil];

    return win;
}

extern void zview_run_loop(void) {
    [NSApp run];
}

extern void zview_evaluate(zview_window *win, const char *js) {
    if (!win || !win->webview) return;
    NSString *src = [NSString stringWithUTF8String:js];
    [win->webview evaluateJavaScript:src completionHandler:nil];
}

extern void zview_destroy(zview_window *win) {
    if (!win) return;
    [win->window close];
    free(win);
}
