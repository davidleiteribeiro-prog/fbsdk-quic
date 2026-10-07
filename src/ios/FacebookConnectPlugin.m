//
//  FacebookConnectPlugin.m
//  GapFacebookConnect
//
//  Created by Jesse MacFadyen on 11-04-22.
//  Updated by Mathijs de Bruin on 11-08-25.
//  Updated by Christine Abernathy on 13-01-22
//  Updated by Jeduan Cornejo on 15-07-04
//  Updated by Eds Keizer on 16-06-13
//  Copyright 2011 Nitobi, Mathijs de Bruin. All rights reserved.
//

#import "FacebookConnectPlugin.h"
#import <objc/runtime.h>

@interface FacebookConnectPlugin ()

@property (strong, nonatomic) NSString* dialogCallbackId;
@property (strong, nonatomic) FBSDKLoginManager *loginManager;
@property (nonatomic, assign) FBSDKLoginTracking loginTracking;
@property (strong, nonatomic) NSString* gameRequestDialogCallbackId;
@property (nonatomic, assign) BOOL applicationWasActivated;
@property (nonatomic, assign) BOOL sdkInit;

- (NSDictionary *)loginResponseObject;
- (NSDictionary *)limitedLoginResponseObject;
- (NSDictionary *)profileObject;
- (void)enableHybridAppEvents;
@end

@implementation FacebookConnectPlugin

- (void)pluginInitialize {
    NSLog(@"Starting Facebook Connect plugin");

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidFinishLaunching:)
                                                 name:UIApplicationDidFinishLaunchingNotification object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                         selector:@selector(handleOpenURLWithAppSourceAndAnnotation:)
                                             name:CDVPluginHandleOpenURLWithAppSourceAndAnnotationNotification object:nil];

    // 1. PRIVACIDADE: Comentado para impedir o arranque automático inicial
}

- (void) applicationDidFinishLaunching:(NSNotification *) notification {
    (void)notification; // Ignorado para não causar erro de unused parameter no MABS
    // 2. PRIVACIDADE: Comentado para impedir o arranque forçado
}

// =========================================================================================
// CORREÇÃO CRÍTICA ANTI-CRASH: Arranque Dinâmico e Seguro a meio da sessão
// =========================================================================================
- (void) initFbSdkWithOpts:(NSDictionary *) launchOptions {
    if (self.sdkInit) return;
    self.sdkInit = YES;

    dispatch_block_t initBlock = ^{
        @try {
            // Em vez de simular um "App Launch" a meio da sessão (que deita o iOS abaixo),
            // procura o método "initializeSDK" de forma dinâmica e segura.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            if ([[FBSDKApplicationDelegate sharedInstance] respondsToSelector:NSSelectorFromString(@"initializeSDK")]) {
                [[FBSDKApplicationDelegate sharedInstance] performSelector:NSSelectorFromString(@"initializeSDK")];
            } else {
                [[FBSDKApplicationDelegate sharedInstance] application:[UIApplication sharedApplication] didFinishLaunchingWithOptions:launchOptions ?: @{}];
            }
#pragma clang diagnostic pop
            [FBSDKProfile enableUpdatesOnAccessTokenChange:YES];
        } @catch (NSException *e) {
            NSLog(@"[Meta SDK] Falha silenciosa no arranque: %@", e.reason);
        }
    };

    if ([NSThread isMainThread]) {
        initBlock();
    } else {
        dispatch_sync(dispatch_get_main_queue(), initBlock);
    }
}

- (void) applicationDidBecomeActive:(NSNotification *) notification {
    (void)notification;
    if (FBSDKSettings.sharedSettings.isAutoLogAppEventsEnabled) {
        [self initFbSdkWithOpts:nil];
        @try { [FBSDKAppEvents.shared activateApp]; } @catch (...) {}
    }
    if (self.applicationWasActivated == NO) {
        self.applicationWasActivated = YES;
        [self enableHybridAppEvents];
    }
}

- (void) handleOpenURLWithAppSourceAndAnnotation:(NSNotification *) notification {
    NSMutableDictionary * options = [notification object];
    NSURL* url = options[@"url"];
    [[FBSDKApplicationDelegate sharedInstance] application:[UIApplication sharedApplication] openURL:url options:options];
}

#pragma mark - Cordova commands

- (void)getApplicationId:(CDVInvokedUrlCommand *)command {
    NSString *appID = FBSDKSettings.sharedSettings.appID;
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:appID];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setApplicationId:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] == 0) { [self returnInvalidArgsError:command.callbackId]; return; }
    NSString *appId = [command argumentAtIndex:0];
    [FBSDKSettings.sharedSettings setAppID:appId];
    [self returnGenericSuccess:command.callbackId];
}

- (void)getClientToken:(CDVInvokedUrlCommand *)command {
    NSString *clientToken = FBSDKSettings.sharedSettings.clientToken;
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:clientToken];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setClientToken:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] == 0) { [self returnInvalidArgsError:command.callbackId]; return; }
    NSString *clientToken = [command argumentAtIndex:0];
    [FBSDKSettings.sharedSettings setClientToken:clientToken];
    [self returnGenericSuccess:command.callbackId];
}

- (void)getApplicationName:(CDVInvokedUrlCommand *)command {
    NSString *displayName = FBSDKSettings.sharedSettings.displayName;
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:displayName];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setApplicationName:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] == 0) { [self returnInvalidArgsError:command.callbackId]; return; }
    NSString *displayName = [command argumentAtIndex:0];
    [FBSDKSettings.sharedSettings setDisplayName:displayName];
    [self returnGenericSuccess:command.callbackId];
}

- (void)getLoginStatus:(CDVInvokedUrlCommand *)command {
    if (self.loginTracking == FBSDKLoginTrackingLimited) { [self returnLimitedLoginMethodError:command.callbackId]; return; }
    [self initFbSdkWithOpts:nil];

    BOOL force = [[command argumentAtIndex:0] boolValue];
    if (force) {
        [FBSDKAccessToken refreshCurrentAccessTokenWithCompletion:^(id<FBSDKGraphRequestConnecting>  _Nullable connection, id  _Nullable result, NSError * _Nullable error) {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[self loginResponseObject]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }];
    } else {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[self loginResponseObject]];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

- (void)getAccessToken:(CDVInvokedUrlCommand *)command {
    if (self.loginTracking == FBSDKLoginTrackingLimited) { [self returnLimitedLoginMethodError:command.callbackId]; return; }
    [self initFbSdkWithOpts:nil];

    CDVPluginResult *pluginResult;
    if ([FBSDKAccessToken currentAccessToken]) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:[FBSDKAccessToken currentAccessToken].tokenString];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not open."];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setAutoLogAppEventsEnabled:(CDVInvokedUrlCommand *)command {
    [self initFbSdkWithOpts:nil];
    BOOL enabled = [[command argumentAtIndex:0] boolValue];
    [FBSDKSettings.sharedSettings setAutoLogAppEventsEnabled:enabled];
    [self returnGenericSuccess:command.callbackId];
}

- (void)setAdvertiserIDCollectionEnabled:(CDVInvokedUrlCommand *)command {
    [self initFbSdkWithOpts:nil];
    BOOL enabled = [[command argumentAtIndex:0] boolValue];
    [FBSDKSettings.sharedSettings setAdvertiserIDCollectionEnabled:enabled];
    [self returnGenericSuccess:command.callbackId];
}

// =========================================================================================
// CORREÇÃO CRÍTICA ANTI-CRASH 2: Tratar o Tracking na Main Thread com Try/Catch
// =========================================================================================
- (void)setAdvertiserTrackingEnabled:(CDVInvokedUrlCommand *)command {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self initFbSdkWithOpts:nil];
        BOOL enabled = [[command argumentAtIndex:0] boolValue];
        
        @try {
            [FBSDKSettings.sharedSettings setAdvertiserTrackingEnabled:enabled];
        } @catch (NSException *e) {
            NSLog(@"[Meta SDK] Tracking ignorado de forma segura: %@", e.reason);
        }
        
        [self returnGenericSuccess:command.callbackId];
    });
}

// =========================================================================================
// CORREÇÃO CRÍTICA ANTI-CRASH 3: Activação da App forçada à Main Thread
// =========================================================================================
- (void) activateApp:(CDVInvokedUrlCommand *)command {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self initFbSdkWithOpts:nil];
        
        @try {
            [FBSDKAppEvents.shared activateApp];
        } @catch (NSException *e) {
            NSLog(@"[Meta SDK] activateApp ignorado de forma segura: %@", e.reason);
        }
        
        [self returnGenericSuccess:command.callbackId];
    });
}

// =========================================================================================
// CORREÇÃO CRÍTICA ANTI-CRASH 4: Proteção do LogEvent 
// =========================================================================================
- (void)logEvent:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] == 0) { [self returnInvalidArgsError:command.callbackId]; return; }

    // Pre-arranca o SDK obrigatoriamente na Main Thread
    if ([NSThread isMainThread]) {
        [self initFbSdkWithOpts:nil];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self initFbSdkWithOpts:nil];
        });
    }

    [self.commandDelegate runInBackground:^{
        @try {
            NSString *eventName = [command.arguments objectAtIndex:0];
            NSDictionary *params;
            double value;

            if ([command.arguments count] == 1) {
                [FBSDKAppEvents.shared logEvent:eventName];
            } else {
                params = [command.arguments objectAtIndex:1];
                if ([command.arguments count] == 2) {
                    [FBSDKAppEvents.shared logEvent:eventName parameters:params];
                }
                if ([command.arguments count] >= 3) {
                    value = [[command.arguments objectAtIndex:2] doubleValue];
                    [FBSDKAppEvents.shared logEvent:eventName valueToSum:value parameters:params];
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[Meta SDK] logEvent ignorado de forma segura: %@", e.reason);
        }
        
        [self returnGenericSuccess:command.callbackId];
    }];
}

- (void)logPurchase:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] < 2 || [command.arguments count] > 3 ) { [self returnInvalidArgsError:command.callbackId]; return; }

    if ([NSThread isMainThread]) {
        [self initFbSdkWithOpts:nil];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{ [self initFbSdkWithOpts:nil]; });
    }

    [self.commandDelegate runInBackground:^{
        @try {
            double value = [[command.arguments objectAtIndex:0] doubleValue];
            NSString *currency = [command.arguments objectAtIndex:1];

            if (![[NSLocale ISOCurrencyCodes] containsObject:currency]) {
                CDVPluginResult *res = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[NSString stringWithFormat:@"Invalid currency code: %@", currency]];
                [self.commandDelegate sendPluginResult:res callbackId:command.callbackId];
                return;
            }

            if ([command.arguments count] == 2 ) {
                [FBSDKAppEvents.shared logPurchase:value currency:currency];
            } else if ([command.arguments count] >= 3) {
                NSDictionary *params = [command.arguments objectAtIndex:2];
                [FBSDKAppEvents.shared logPurchase:value currency:currency parameters:params];
            }
        } @catch (NSException *e) {}
        
        [self returnGenericSuccess:command.callbackId];
    }];
}

- (void)setDataProcessingOptions:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] == 0) { [self returnInvalidArgsError:command.callbackId]; return; }
    [self initFbSdkWithOpts:nil];

    NSArray *options = [command argumentAtIndex:0];
    if ([command.arguments count] == 1) {
        [FBSDKSettings.sharedSettings setDataProcessingOptions:options];
    } else {
        int32_t country = [[command.arguments objectAtIndex:1] intValue];
        int32_t state = [[command.arguments objectAtIndex:2] intValue];
        [FBSDKSettings.sharedSettings setDataProcessingOptions:options country:country state:state];
    }
    [self returnGenericSuccess:command.callbackId];
}

- (void)setUserData:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] == 0) { [self returnInvalidArgsError:command.callbackId]; return; }
    [self initFbSdkWithOpts:nil];

    [self.commandDelegate runInBackground:^{
        NSDictionary *params = [command.arguments objectAtIndex:0];
        if (![params isKindOfClass:[NSDictionary class]]) {
            CDVPluginResult *res = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"userData must be an object"];
            [self.commandDelegate sendPluginResult:res callbackId:command.callbackId];
            return;
        } else {
            [FBSDKAppEvents.shared setUserEmail:(NSString *)params[@"em"]
                            firstName:(NSString*)params[@"fn"] 
                            lastName:(NSString *)params[@"ln"] 
                            phone:(NSString *)params[@"ph"] 
                            dateOfBirth:(NSString *)params[@"db"] 
                            gender:(NSString *)params[@"ge"] 
                            city:(NSString *)params[@"ct"] 
                            state:(NSString *)params[@"st"] 
                            zip:(NSString *)params[@"zp"] 
                            country:(NSString *)params[@"cn"]];
        }
        [self returnGenericSuccess:command.callbackId];
    }];
}

- (void)clearUserData:(CDVInvokedUrlCommand *)command {
    [self initFbSdkWithOpts:nil];
    [FBSDKAppEvents.shared clearUserData];
    [self returnGenericSuccess:command.callbackId];
}

- (void)login:(CDVInvokedUrlCommand *)command {
    NSLog(@"Starting login");
    [self initFbSdkWithOpts:nil];
    
    CDVPluginResult *pluginResult;
    NSArray *permissions = nil;

    if ([command.arguments count] > 0) {
        permissions = command.arguments;
    }

    [FBSDKAccessToken refreshCurrentAccessTokenWithCompletion:nil];

    FBSDKLoginManagerLoginResultBlock loginHandler = ^void(FBSDKLoginManagerLoginResult *result, NSError *error) {
        if (error) {
            NSString *errorCode = @"-2";
            NSString *errorMessage = error.userInfo[FBSDKErrorLocalizedDescriptionKey];
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
            return;
        } else if (result.isCancelled) {
            NSString *errorCode = @"4201";
            NSString *errorMessage = @"User cancelled.";
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
        } else {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[self loginResponseObject]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    };

    if ([FBSDKAccessToken currentAccessToken] == nil) {
        if (permissions == nil) permissions = @[];
        if (self.loginManager == nil || self.loginTracking == FBSDKLoginTrackingLimited) {
            self.loginManager = [[FBSDKLoginManager alloc] init];
        }
        self.loginTracking = FBSDKLoginTrackingEnabled;
        [self.loginManager logInWithPermissions:permissions fromViewController:[self topMostController] handler:loginHandler];
        return;
    }

    if (permissions == nil) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No permissions specified at login"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }
    [self loginWithPermissions:permissions withHandler:loginHandler];
}

- (void)loginWithLimitedTracking:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] == 1) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No nonce specified"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    [self initFbSdkWithOpts:nil];

    NSArray *permissions = [command argumentAtIndex:0];
    NSArray *permissionsArray = @[];
    NSString *nonce = [command argumentAtIndex:1];

    if ([permissions count] > 0) {
        permissionsArray = permissions;
    }

    FBSDKLoginManagerLoginResultBlock loginHandler = ^void(FBSDKLoginManagerLoginResult *result, NSError *error) {
        if (error) {
            NSString *errorCode = @"-2";
            NSString *errorMessage = error.userInfo[FBSDKErrorLocalizedDescriptionKey];
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
            return;
        } else if (result.isCancelled) {
            NSString *errorCode = @"4201";
            NSString *errorMessage = @"User cancelled.";
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
        } else {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[self limitedLoginResponseObject]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    };

    if (self.loginManager == nil || self.loginTracking == FBSDKLoginTrackingEnabled) {
        self.loginManager = [FBSDKLoginManager new];
    }
    self.loginTracking = FBSDKLoginTrackingLimited;
    FBSDKLoginConfiguration *configuration = [[FBSDKLoginConfiguration alloc] initWithPermissions:permissionsArray tracking:FBSDKLoginTrackingLimited nonce:nonce];
    [self.loginManager logInFromViewController:[self topMostController] configuration:configuration completion:loginHandler];
}

- (void) checkHasCorrectPermissions:(CDVInvokedUrlCommand*)command {
    if (self.loginTracking == FBSDKLoginTrackingLimited) { [self returnLimitedLoginMethodError:command.callbackId]; return; }
    [self initFbSdkWithOpts:nil];

    NSArray *permissions = nil;
    if ([command.arguments count] > 0) permissions = command.arguments;
    
    NSSet *grantedPermissions = [FBSDKAccessToken currentAccessToken].permissions;

    for (NSString *value in permissions) {
        if (![grantedPermissions containsObject:value]) {
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"A permission has been denied"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }
    }
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"All permissions have been accepted"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) isDataAccessExpired:(CDVInvokedUrlCommand *)command {
    [self initFbSdkWithOpts:nil];
    CDVPluginResult *pluginResult;
    if ([FBSDKAccessToken currentAccessToken]) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:[FBSDKAccessToken currentAccessToken].dataAccessExpired ? @"true" : @"false"];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Session not open."];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) reauthorizeDataAccess:(CDVInvokedUrlCommand *)command {
    if (self.loginTracking == FBSDKLoginTrackingLimited) { [self returnLimitedLoginMethodError:command.callbackId]; return; }
    [self initFbSdkWithOpts:nil];
    
    if (self.loginManager == nil) { self.loginManager = [[FBSDKLoginManager alloc] init]; }
    self.loginTracking = FBSDKLoginTrackingEnabled;
    
    FBSDKLoginManagerLoginResultBlock reauthorizeHandler = ^void(FBSDKLoginManagerLoginResult *result, NSError *error) {
        if (error) {
            NSString *errorCode = @"-2";
            NSString *errorMessage = error.userInfo[FBSDKErrorLocalizedDescriptionKey];
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
            return;
        } else if (result.isCancelled) {
            NSString *errorCode = @"4201";
            NSString *errorMessage = @"User cancelled.";
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
        } else {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[self loginResponseObject]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    };
    [self.loginManager reauthorizeDataAccess:[self topMostController] handler:reauthorizeHandler];
}

- (void) logout:(CDVInvokedUrlCommand*)command {
    [self initFbSdkWithOpts:nil];
    if ([FBSDKAccessToken currentAccessToken]) {
        if (self.loginManager == nil) { self.loginManager = [[FBSDKLoginManager alloc] init]; }
        [self.loginManager logOut];
    }
    [self returnGenericSuccess:command.callbackId];
}

- (void) showDialog:(CDVInvokedUrlCommand*)command {
    if ([command.arguments count] == 0) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No method provided"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    NSMutableDictionary *options = [[command.arguments lastObject] mutableCopy];
    NSString* method = options[@"method"];
    if (!method) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No method provided"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    [options removeObjectForKey:@"method"];
    NSDictionary *params = [options copy];

    [self initFbSdkWithOpts:nil];

    if ([method isEqualToString:@"send"]) {
        FBSDKShareLinkContent *content = [[FBSDKShareLinkContent alloc] init];
        content.contentURL = [NSURL URLWithString:[params objectForKey:@"link"]];
        self.dialogCallbackId = command.callbackId;
        [FBSDKMessageDialog showWithContent:content delegate:self];
        return;

    } else if ([method isEqualToString:@"share"] || [method isEqualToString:@"feed"]) {
        self.dialogCallbackId = command.callbackId;
        FBSDKShareDialog *dialog = [[FBSDKShareDialog alloc] initWithViewController:[self topMostController] content:nil delegate:self];
        if (params[@"photo_image"]) {
            NSString *photoImage = params[@"photo_image"];
            UIImage *image = nil;
            if (![photoImage isKindOfClass:[NSString class]]) {
                NSLog(@"photo_image must be a string");
            } else {
                NSData *photoImageData = [[NSData alloc] initWithBase64EncodedString:photoImage options:NSDataBase64DecodingIgnoreUnknownCharacters];
                if (photoImageData) { image = [UIImage imageWithData:photoImageData]; }
            }
            if (!image) {
                self.dialogCallbackId = nil;
                CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"photo_image is not a valid base64 encoded image"];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                return;
            }
            FBSDKSharePhoto *photo = [[FBSDKSharePhoto alloc] initWithImage:image isUserGenerated:YES];
            FBSDKSharePhotoContent *content = [[FBSDKSharePhotoContent alloc] init];
            content.photos = @[photo];
            dialog.shareContent = content;
        } else {
            FBSDKShareLinkContent *content = [[FBSDKShareLinkContent alloc] init];
            content.contentURL = [NSURL URLWithString:params[@"href"]];
            content.hashtag = [[FBSDKHashtag alloc] initWithString:[params objectForKey:@"hashtag"]];
            content.quote = params[@"quote"];
            dialog.shareContent = content;
        }

        if (params[@"share_sheet"]) { dialog.mode = FBSDKShareDialogModeShareSheet; } 
        else if (params[@"share_feedBrowser"]) { dialog.mode = FBSDKShareDialogModeFeedBrowser; } 
        else if (params[@"share_native"]) { dialog.mode = FBSDKShareDialogModeNative; } 
        else if (params[@"share_feedWeb"]) { dialog.mode = FBSDKShareDialogModeFeedWeb; }

        [dialog show];
        return;
    }
    else if ([method isEqualToString:@"apprequests"]) {
        FBSDKGameRequestContent *content = [[FBSDKGameRequestContent alloc] init];
        NSString *actionType = params[@"actionType"];
        if (!actionType) {
            NSLog(@"Discarding invalid argument actionType");
        } else if ([[actionType lowercaseString] isEqualToString:@"askfor"]) {
            content.actionType = FBSDKGameRequestActionTypeAskFor;
        } else if ([[actionType lowercaseString] isEqualToString:@"send"]) {
            content.actionType = FBSDKGameRequestActionTypeSend;
        } else if ([[actionType lowercaseString] isEqualToString:@"turn"]) {
            content.actionType = FBSDKGameRequestActionTypeTurn;
        }

        NSString *filters = params[@"filters"];
        if (!filters) { content.filters = FBSDKGameRequestFilterNone; } 
        else if ([filters isEqualToString:@"app_users"]) { content.filters = FBSDKGameRequestFilterAppUsers; } 
        else if ([filters isEqualToString:@"app_non_users"]) { content.filters = FBSDKGameRequestFilterAppNonUsers; }

        content.data = params[@"data"];
        content.message = params[@"message"];
        content.objectID = params[@"objectID"];
        content.recipients = params[@"to"];
        content.title = params[@"title"];

        FBSDKGameRequestDialog *dialog = [[FBSDKGameRequestDialog alloc] initWithContent:content delegate:self];
        if (![dialog canShow]) {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Cannot show dialog"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }

        self.gameRequestDialogCallbackId = command.callbackId;
        [dialog show];
        return;
    }
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"method not supported"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)getCurrentProfile:(CDVInvokedUrlCommand *)command {
    [self initFbSdkWithOpts:nil];
    [FBSDKProfile loadCurrentProfileWithCompletion:^(FBSDKProfile *profile, NSError *error) {
        CDVPluginResult *pluginResult;
        if (![FBSDKProfile currentProfile]) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No current profile."];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[self profileObject]];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void) graphApi:(CDVInvokedUrlCommand *)command {
    if (self.loginTracking == FBSDKLoginTrackingLimited) { [self returnLimitedLoginMethodError:command.callbackId]; return; }
    [self initFbSdkWithOpts:nil];

    if (! [FBSDKAccessToken currentAccessToken]) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"You are not logged in."];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    NSString *graphPath = [command argumentAtIndex:0];
    NSArray *permissionsNeeded = [command argumentAtIndex:1];
    NSString *requestMethod = nil;
    if ([command.arguments count] >= 3) { requestMethod = [command argumentAtIndex:2]; }

    NSSet *currentPermissions = [FBSDKAccessToken currentAccessToken].permissions;
    NSMutableArray *requestPermissions = [[NSMutableArray alloc] initWithArray:@[]];

    for (NSString *permission in permissionsNeeded){
        if (![currentPermissions containsObject:permission]) {
            [requestPermissions addObject:permission];
        }
    }
    NSArray *permissions = [requestPermissions copy];

    FBSDKGraphRequest *request = [[FBSDKGraphRequest alloc] initWithGraphPath:graphPath parameters:nil HTTPMethod:requestMethod];

    if ([permissions count] == 0){
        [request startWithCompletion:^(id<FBSDKGraphRequestConnecting>  _Nullable connection, id  _Nullable result, NSError * _Nullable error) {
            CDVPluginResult* pluginResult;
            if (error) {
                NSString *message = error.userInfo[FBSDKErrorLocalizedDescriptionKey] ?: @"There was an error making the graph call.";
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:message];
            } else {
                NSDictionary *response = (NSDictionary *) result;
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:response];
            }
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }];
        return;
    }

    [self loginWithPermissions:requestPermissions withHandler:^(FBSDKLoginManagerLoginResult *result, NSError *error) {
        if (error) {
            NSString *errorCode = @"-2";
            NSString *errorMessage = error.userInfo[FBSDKErrorLocalizedDescriptionKey];
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
            return;
        } else if (result.isCancelled) {
            NSString *errorCode = @"4201";
            NSString *errorMessage = @"User cancelled.";
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
            return;
        }

        NSString *deniedPermission = nil;
        for (NSString *permission in permissions) {
            if (![result.grantedPermissions containsObject:permission]) {
                deniedPermission = permission;
                break;
            }
        }

        if (deniedPermission != nil) {
            NSString *errorMessage = [NSString stringWithFormat:@"The user didnt allow necessary permission %@", deniedPermission];
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorMessage];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }

        [request startWithCompletion:^(id<FBSDKGraphRequestConnecting>  _Nullable connection, id  _Nullable result, NSError * _Nullable error) {
            CDVPluginResult* pluginResult;
            if (error) {
                NSString *message = error.userInfo[FBSDKErrorLocalizedDescriptionKey] ?: @"There was an error making the graph call.";
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:message];
            } else {
                NSDictionary *response = (NSDictionary *) result;
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:response];
            }
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }];
    }];
}

- (void) getDeferredApplink:(CDVInvokedUrlCommand *) command {
    [self initFbSdkWithOpts:nil];
    [FBSDKAppLinkUtility fetchDeferredAppLink:^(NSURL *url, NSError *error) {
        if (error) {
            NSString *errorMessage = error.userInfo[FBSDKErrorLocalizedDescriptionKey] ?: @"Received error while fetching deferred app link.";
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorMessage];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }
        if (url) {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:url.absoluteString];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } else {
            [self returnGenericSuccess:command.callbackId];
        }
    }];
}

#pragma mark - Utility methods

- (void) returnGenericSuccess:(NSString *)callbackId {
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

- (void) returnInvalidArgsError:(NSString *)callbackId {
    CDVPluginResult *res = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Invalid arguments"];
    [self.commandDelegate sendPluginResult:res callbackId:callbackId];
}

- (void) returnLoginError:(NSString *)callbackId:(NSString *)errorCode:(NSString *)errorMessage {
    NSMutableDictionary *response = [[NSMutableDictionary alloc] init];
    response[@"errorCode"] = errorCode ?: @"-2";
    response[@"errorMessage"] = errorMessage ?: @"There was a problem logging you in.";
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:response];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

- (void) returnLimitedLoginMethodError:(NSString *)callbackId {
    NSString *methodErrorMessage = @"Method not available when using Limited Login";
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:methodErrorMessage];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

- (void) loginWithPermissions:(NSArray *)permissions withHandler:(FBSDKLoginManagerLoginResultBlock) handler {
    if (self.loginManager == nil) { self.loginManager = [[FBSDKLoginManager alloc] init]; }
    self.loginTracking = FBSDKLoginTrackingEnabled;
    [self.loginManager logInWithPermissions:permissions fromViewController:[self topMostController] handler:handler];
}

- (UIViewController*) topMostController {
    UIViewController *topController = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (topController.presentedViewController) { topController = topController.presentedViewController; }
    return topController;
}

- (NSDictionary *)loginResponseObject {
    if (![FBSDKAccessToken currentAccessToken]) { return @{@"status": @"unknown"}; }
    NSMutableDictionary *response = [[NSMutableDictionary alloc] init];
    FBSDKAccessToken *token = [FBSDKAccessToken currentAccessToken];
    
    NSTimeInterval dataAccessExpirationTimeInterval = token.dataAccessExpirationDate.timeIntervalSince1970;
    NSString *dataAccessExpirationTime = @"0";
    if (dataAccessExpirationTimeInterval > 0) { dataAccessExpirationTime = [NSString stringWithFormat:@"%0.0f", dataAccessExpirationTimeInterval]; }
    
    NSTimeInterval expiresTimeInterval = token.expirationDate.timeIntervalSinceNow;
    NSString *expiresIn = @"0";
    if (expiresTimeInterval > 0) { expiresIn = [NSString stringWithFormat:@"%0.0f", expiresTimeInterval]; }
    
    response[@"status"] = @"connected";
    response[@"authResponse"] = @{ @"accessToken" : token.tokenString ?: @"", @"data_access_expiration_time" : dataAccessExpirationTime, @"expiresIn" : expiresIn, @"userID" : token.userID ?: @"" };
    return [response copy];
}

- (NSDictionary *)limitedLoginResponseObject {
    if (![FBSDKAuthenticationToken currentAuthenticationToken]) { return @{@"status": @"unknown"}; }
    NSMutableDictionary *response = [[NSMutableDictionary alloc] init];
    FBSDKAuthenticationToken *token = [FBSDKAuthenticationToken currentAuthenticationToken];
    NSString *userID = [FBSDKProfile currentProfile] ? [FBSDKProfile currentProfile].userID : @"";
    
    response[@"status"] = @"connected";
    response[@"authResponse"] = @{ @"authenticationToken" : token.tokenString ?: @"", @"nonce" : token.nonce ?: @"", @"userID" : userID ?: @"" };
    return [response copy];
}

- (NSDictionary *)profileObject {
    if ([FBSDKProfile currentProfile] == nil) { return @{}; }
    NSMutableDictionary *response = [[NSMutableDictionary alloc] init];
    FBSDKProfile *profile = [FBSDKProfile currentProfile];
    response[@"userID"] = profile.userID ?: @"";
    
    if (self.loginTracking == FBSDKLoginTrackingLimited) {
        if (profile.name) response[@"name"] = profile.name;
        if (profile.email) response[@"email"] = profile.email;
    } else {
        response[@"firstName"] = profile.firstName ?: @"";
        response[@"lastName"] = profile.lastName ?: @"";
    }
    return [response copy];
}

- (void)enableHybridAppEvents {
    if ([self.webView isMemberOfClass:[WKWebView class]]){
        NSString *is_enabled = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"FacebookHybridAppEvents"];
        if([is_enabled isEqualToString:@"true"]){
            @try { [FBSDKAppEvents.shared augmentHybridWebView:(WKWebView*)self.webView]; } @catch (...) {}
        }
    }
}

# pragma mark - FBSDKSharingDelegate

- (void)sharer:(id<FBSDKSharing>)sharer didCompleteWithResults:(NSDictionary *)results {
    (void)sharer; 
    if (!self.dialogCallbackId) return;
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:results];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.dialogCallbackId];
    self.dialogCallbackId = nil;
}

- (void)sharer:(id<FBSDKSharing>)sharer didFailWithError:(NSError *)error {
    (void)sharer; 
    if (!self.
