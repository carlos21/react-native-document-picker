#import "RNDocumentPicker.h"

#import <MobileCoreServices/MobileCoreServices.h>

#if __has_include(<React/RCTConvert.h>)
#import <React/RCTConvert.h>
#import <React/RCTBridge.h>
#else // back compatibility for RN version < 0.40
#import "RCTConvert.h"
#import "RCTBridge.h"
#endif

static NSString *const E_DOCUMENT_PICKER_CANCELED = @"DOCUMENT_PICKER_CANCELED";
static NSString *const E_INVALID_DATA_RETURNED = @"INVALID_DATA_RETURNED";

static NSString *const OPTION_TYPE = @"type";
static NSString *const OPTION_MULIPLE = @"multiple";

static NSString *const FIELD_URI = @"uri";
static NSString *const FIELD_NAME = @"name";
static NSString *const FIELD_TYPE = @"type";
static NSString *const FIELD_SIZE = @"size";

@interface RNDocumentPicker () <UIDocumentPickerDelegate>
@end

@implementation RNDocumentPicker {
    NSMutableArray *composeViews;
    NSMutableArray *composeResolvers;
    NSMutableArray *composeRejecters;
}

@synthesize bridge = _bridge;

- (instancetype)init
{
    if ((self = [super init])) {
        composeResolvers = [[NSMutableArray alloc] init];
        composeRejecters = [[NSMutableArray alloc] init];
        composeViews = [[NSMutableArray alloc] init];
    }
    return self;
}

+ (BOOL)requiresMainQueueSetup {
    return NO;
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE()

RCT_EXPORT_METHOD(pick:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSArray *allowedUTIs = [RCTConvert NSArray:options[OPTION_TYPE]];
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:(NSArray *)allowedUTIs inMode:UIDocumentPickerModeImport];
    
    [composeResolvers addObject:resolve];
    [composeRejecters addObject:reject];
    
    documentPicker.delegate = self;
    documentPicker.modalPresentationStyle = UIModalPresentationFullScreen;
    
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
    if (@available(iOS 11, *)) {
        documentPicker.allowsMultipleSelection = [RCTConvert BOOL:options[OPTION_MULIPLE]];
    }
#endif
    
    UIViewController *rootViewController = [[[[UIApplication sharedApplication]delegate] window] rootViewController];
    while (rootViewController.presentedViewController) {
        rootViewController = rootViewController.presentedViewController;
    }
    
    [rootViewController presentViewController:documentPicker animated:YES completion:nil];
}

- (NSMutableDictionary *)getMetadataForUrl:(NSURL *)url error:(NSError **)error
{
    NSMutableDictionary* result = [NSMutableDictionary dictionary];
    [result setValue:[url lastPathComponent] forKey:FIELD_NAME];
    [result setValue:@"123" forKey:FIELD_SIZE];
    [result setValue:@"" forKey:FIELD_TYPE];
    
    NSURL *tempURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    NSURL *newURL = [tempURL URLByAppendingPathComponent:url.lastPathComponent];
    NSError *saveError = nil;
    
    if ([NSFileManager.defaultManager fileExistsAtPath:newURL.path]) {
        [NSFileManager.defaultManager removeItemAtURL:newURL error:&saveError];
    }
    
    [NSFileManager.defaultManager moveItemAtURL:url toURL:newURL error:&saveError];
    [result setValue:newURL.path forKey:FIELD_URI];
    
    return result;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url
{
    if (controller.documentPickerMode == UIDocumentPickerModeImport) {
        RCTPromiseResolveBlock resolve = [composeResolvers lastObject];
        RCTPromiseRejectBlock reject = [composeRejecters lastObject];
        [composeResolvers removeLastObject];
        [composeRejecters removeLastObject];
        
        NSError *error;
        NSMutableDictionary* result = [self getMetadataForUrl:url error:&error];
        if (result) {
            NSArray *results = @[result];
            resolve(results);
        } else {
            reject(E_INVALID_DATA_RETURNED, error.localizedDescription, error);
        }
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    if (controller.documentPickerMode == UIDocumentPickerModeImport) {
        RCTPromiseResolveBlock resolve = [composeResolvers lastObject];
        RCTPromiseRejectBlock reject = [composeRejecters lastObject];
        [composeResolvers removeLastObject];
        [composeRejecters removeLastObject];
        
        NSMutableArray *results = [NSMutableArray array];
        for (id url in urls) {
            NSError *error;
            NSMutableDictionary* result = [self getMetadataForUrl:url error:&error];
            if (result) {
                [results addObject:result];
            } else {
                reject(E_INVALID_DATA_RETURNED, error.localizedDescription, error);
                return;
            }
        }
        
        resolve(results);
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
    if (controller.documentPickerMode == UIDocumentPickerModeImport) {
        RCTPromiseRejectBlock reject = [composeRejecters lastObject];
        [composeResolvers removeLastObject];
        [composeRejecters removeLastObject];
        
        reject(E_DOCUMENT_PICKER_CANCELED, @"User canceled document picker", nil);
    }
}

@end
