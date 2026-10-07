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

    // Add notification listener for tracking app activity with FB Events
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidFinishLaunching:)
                                                 name:UIApplicationDidFinishLaunchingNotification object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                         selector:@selector(handleOpenURLWithAppSourceAndAnnotation:)
                                             name:CDVPluginHandleOpenURLWithAppSourceAndAnnotationNotification object:nil];

    // Last-resort fallback. The AppDelegate swizzle at the bottom of this file is the path that
    // actually initialises the SDK, with the real launchOptions; this only matters for a host whose
    // delegate class the `AppDelegate (FacebookConnectPlugin)` category never attaches to, where
    // otherwise the SDK would stay uninitialised for the whole session -- no app events, no
    // attribution, and `App ID not found` on the first SDK call.
    //
    // Deferred to the next main-queue turn rather than called inline because the SDK keeps whichever
    // launch options it is handed first and ignores every later call. Calling inline would beat both
    // the swizzle and a still-in-flight UIApplicationDidFinishLaunchingNotification, permanently
    // replacing their real options with an empty dictionary. Yielding lets either of those claim the
    // initialisation whenever they are coming; a duplicate call afterwards is a no-op, because
    // ApplicationDelegate.application(_:didFinishLaunchingWithOptions:) is guarded by
    // `!isAppLaunched, !hasInitializeBeenCalled`.
    __weak FacebookConnectPlugin *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        // 1. ALTERAÇÃO DE PRIVACIDADE: Comentado para impedir o arranque forçado via Cordova
        // [weakSelf initFbSdkWithOpts:nil];
    });
}

- (void) applicationDidFinishLaunching:(NSNotification *) notification {
    // 2. ALTERAÇÃO DE PRIVACIDADE: Comentado para impedir o arranque via Notificação de Sistema do iOS
    // [self initFbSdkWithOpts:notification.userInfo];
}

- (void) initFbSdkWithOpts:(NSDictionary *) launchOptions {
    if (self.sdkInit) {
        return;
    }
    self.sdkInit = YES;

    NSDictionary *finalLaunchOptions = launchOptions ?: [NSDictionary dictionary];

    // Bloco de inicialização que TEM de correr na Main Thread
    dispatch_block_t initBlock = ^{
        [[FBSDKApplicationDelegate sharedInstance] application:[UIApplication sharedApplication] didFinishLaunchingWithOptions:finalLaunchOptions];
        [FBSDKProfile enableUpdatesOnAccessTokenChange:YES];
    };

    // Verifica em que thread estamos e executa de forma segura
    if ([NSThread isMainThread]) {
        initBlock();
    } else {
        dispatch_sync(dispatch_get_main_queue(), initBlock);
    }
}

- (void) applicationDidBecomeActive:(NSNotification *) notification {
    if (FBSDKSettings.sharedSettings.isAutoLogAppEventsEnabled) {
        [FBSDKAppEvents.shared activateApp];
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
    if ([command.arguments count] == 0) {
        // Not enough arguments
        [self returnInvalidArgsError:command.callbackId];
        return;
    }
    
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
    if ([command.arguments count] == 0) {
        // Not enough arguments
        [self returnInvalidArgsError:command.callbackId];
        return;
    }
    
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
    if ([command.arguments count] == 0) {
        // Not enough arguments
        [self returnInvalidArgsError:command.callbackId];
        return;
    }
    
    NSString *displayName = [command argumentAtIndex:0];
    [FBSDKSettings.sharedSettings setDisplayName:displayName];
    [self returnGenericSuccess:command.callbackId];
}

- (void)getLoginStatus:(CDVInvokedUrlCommand *)command {
    if (self.loginTracking == FBSDKLoginTrackingLimited) {
        [self returnLimitedLoginMethodError:command.callbackId];
        return;
    }
    
    BOOL force = [[command argumentAtIndex:0] boolValue];
    if (force) {
        [FBSDKAccessToken refreshCurrentAccessTokenWithCompletion:^(id<FBSDKGraphRequestConnecting>  _Nullable connection, id  _Nullable result, NSError * _Nullable error) {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsDictionary:[self loginResponseObject]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }];
    } else {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsDictionary:[self loginResponseObject]];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

- (void)getAccessToken:(CDVInvokedUrlCommand *)command {
    if (self.loginTracking == FBSDKLoginTrackingLimited) {
        [self returnLimitedLoginMethodError:command.callbackId];
        return;
    }
    
    // Return access token if available
    CDVPluginResult *pluginResult;
    // Check if the session is open or not
    if ([FBSDKAccessToken currentAccessToken]) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:
                        [FBSDKAccessToken currentAccessToken].tokenString];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:
                        @"Session not open."];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setAutoLogAppEventsEnabled:(CDVInvokedUrlCommand *)command {
    BOOL enabled = [[command argumentAtIndex:0] boolValue];
    [FBSDKSettings.sharedSettings setAutoLogAppEventsEnabled:enabled];
    [self returnGenericSuccess:command.callbackId];
}

- (void)setAdvertiserIDCollectionEnabled:(CDVInvokedUrlCommand *)command {
    BOOL enabled = [[command argumentAtIndex:0] boolValue];
    [FBSDKSettings.sharedSettings setAdvertiserIDCollectionEnabled:enabled];
    [self returnGenericSuccess:command.callbackId];
}

- (void)setAdvertiserTrackingEnabled:(CDVInvokedUrlCommand *)command {
    // ACORDAR O SDK ANTES DE EXECUTAR (Garante que as settings nativas existem na thread certa)
    [self initFbSdkWithOpts:nil];

    BOOL enabled = [[command argumentAtIndex:0] boolValue];
    [FBSDKSettings.sharedSettings setAdvertiserTrackingEnabled:enabled];
    [self returnGenericSuccess:command.callbackId];
}

- (void)setDataProcessingOptions:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] == 0) {
        // Not enough arguments
        [self returnInvalidArgsError:command.callbackId];
        return;
    }

    NSArray *options = [command argumentAtIndex:0];
    if ([command.arguments count] == 1) {
        [FBSDKSettings.sharedSettings setDataProcessingOptions:options];
    } else {
        // The SDK takes these as int32_t (e.g. country 1, state 1000 for California).
        // They were declared NSString *, so what reached the SDK was the pointer address
        // truncated to an int -- a different, meaningless region on every launch.
        int32_t country = [[command.arguments objectAtIndex:1] intValue];
        int32_t state = [[command.arguments objectAtIndex:2] intValue];
        [FBSDKSettings.sharedSettings setDataProcessingOptions:options country:country state:state];
    }
    [self returnGenericSuccess:command.callbackId];
}

- (void)setUserData:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] == 0) {
        // Not enough arguments
        [self returnInvalidArgsError:command.callbackId];
        return;
    }

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
    [FBSDKAppEvents.shared clearUserData];
    [self returnGenericSuccess:command.callbackId];
}

- (void)logEvent:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] == 0) {
        // Not enough arguments
        [self returnInvalidArgsError:command.callbackId];
        return;
    }

    // ACORDAR O SDK ANTES DE EXECUTAR (Garante a Thread Segura antes do background)
    [self initFbSdkWithOpts:nil];

    [self.commandDelegate runInBackground:^{
        // For more verbose output on logging uncomment the following:
        // [FBSettings setLoggingBehavior:[NSSet setWithObject:FBLoggingBehaviorAppEvents]];
        NSString *eventName = [command.arguments objectAtIndex:0];
        NSDictionary *params;
        double value;

        if ([command.arguments count] == 1) {
            [FBSDKAppEvents.shared logEvent:eventName];

        } else {
            // argument count is not 0 or 1, must be 2 or more
            params = [command.arguments objectAtIndex:1];
            if ([command.arguments count] == 2) {
                // If count is 2 we will just send params
                [FBSDKAppEvents.shared logEvent:eventName parameters:params];
            }

            if ([command.arguments count] >= 3) {
                // If count is 3 we will send params and a value to sum
                value = [[command.arguments objectAtIndex:2] doubleValue];
                [FBSDKAppEvents.shared logEvent:eventName valueToSum:value parameters:params];
            }
        }
        [self returnGenericSuccess:command.callbackId];
    }];
}

- (void)logPurchase:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] < 2 || [command.arguments count] > 3 ) {
        [self returnInvalidArgsError:command.callbackId];
        return;
    }

    [self.commandDelegate runInBackground:^{
        double value = [[command.arguments objectAtIndex:0] doubleValue];
        NSString *currency = [command.arguments objectAtIndex:1];

        // Android rejects anything outside ISO 4217 -- Currency.getInstance throws --
        // while iOS handed the raw string to the SDK and always reported success, so a
        // typo produced an unattributable purchase event and no way to notice. Validate
        // here so both platforms fail the same call. Case-sensitive, as on Android.
        if (![[NSLocale ISOCurrencyCodes] containsObject:currency]) {
            CDVPluginResult *res = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                     messageAsString:[NSString stringWithFormat:@"Invalid currency code: %@", currency]];
            [self.commandDelegate sendPluginResult:res callbackId:command.callbackId];
            return;
        }

        if ([command.arguments count] == 2 ) {
            [FBSDKAppEvents.shared logPurchase:value currency:currency];
        } else if ([command.arguments count] >= 3) {
            NSDictionary *params = [command.arguments objectAtIndex:2];
            [FBSDKAppEvents.shared logPurchase:value currency:currency parameters:params];
        }

        [self returnGenericSuccess:command.callbackId];
    }];
}

- (void)login:(CDVInvokedUrlCommand *)command {
    NSLog(@"Starting login");
    
    // ACORDAR O SDK ANTES DE EXECUTAR
    [self initFbSdkWithOpts:nil];
    
    CDVPluginResult *pluginResult;
    NSArray *permissions = nil;

    if ([command.arguments count] > 0) {
        permissions = command.arguments;
    }

    // this will prevent from being unable to login after updating plugin or changing permissions
    // without refreshing there will be a cache problem. This simple call should fix the problems
    [FBSDKAccessToken refreshCurrentAccessTokenWithCompletion:nil];

    FBSDKLoginManagerLoginResultBlock loginHandler = ^void(FBSDKLoginManagerLoginResult *result, NSError *error) {
        if (error) {
            // If the SDK has a message for the user, surface it.
            NSString *errorCode = @"-2";
            NSString *errorMessage = error.userInfo[FBSDKErrorLocalizedDescriptionKey];
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
            return;
        } else if (result.isCancelled) {
            NSString *errorCode = @"4201";
            NSString *errorMessage = @"User cancelled.";
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
        } else {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsDictionary:[self loginResponseObject]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    };

    // Check if the session is open or not
    if ([FBSDKAccessToken currentAccessToken] == nil) {
        if (permissions == nil) {
            permissions = @[];
        }

        if (self.loginManager == nil || self.loginTracking == FBSDKLoginTrackingLimited) {
            self.loginManager = [[FBSDKLoginManager alloc] init];
        }
        self.loginTracking = FBSDKLoginTrackingEnabled;
        [self.loginManager logInWithPermissions:permissions fromViewController:[self topMostController] handler:loginHandler];
        return;
    }


    if (permissions == nil) {
        // We need permissions
        NSString *permissionsErrorMessage = @"No permissions specified at login";
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:permissionsErrorMessage];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    [self loginWithPermissions:permissions withHandler:loginHandler];

}

- (void)loginWithLimitedTracking:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] == 1) {
        NSString *nonceErrorMessage = @"No nonce specified";
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:nonceErrorMessage];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    NSArray *permissions = [command argumentAtIndex:0];
    NSArray *permissionsArray = @[];
    NSString *nonce = [command argumentAtIndex:1];

    if ([permissions count] > 0) {
        permissionsArray = permissions;
    }

    FBSDKLoginManagerLoginResultBlock loginHandler = ^void(FBSDKLoginManagerLoginResult *result, NSError *error) {
        if (error) {
            // If the SDK has a message for the user, surface it.
            NSString *errorCode = @"-2";
            NSString *errorMessage = error.userInfo[FBSDKErrorLocalizedDescriptionKey];
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
            return;
        } else if (result.isCancelled) {
            NSString *errorCode = @"4201";
            NSString *errorMessage = @"User cancelled.";
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
        } else {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsDictionary:[self limitedLoginResponseObject]];
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

- (void) checkHasCorrectPermissions:(CDVInvokedUrlCommand*)command
{
    if (self.loginTracking == FBSDKLoginTrackingLimited) {
        [self returnLimitedLoginMethodError:command.callbackId];
        return;
    }

    NSArray *permissions = nil;

    if ([command.arguments count] > 0) {
        permissions = command.arguments;
    }
    
    NSSet *grantedPermissions = [FBSDKAccessToken currentAccessToken].permissions;

    for (NSString *value in permissions) {
        NSLog(@"Checking permission %@.", value);
        if (![grantedPermissions containsObject:value]) { //checks if permissions does not exists
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                              messageAsString:@"A permission has been denied"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }
    }
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsString:@"All permissions have been accepted"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    return;
}

- (void) isDataAccessExpired:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult;
    if ([FBSDKAccessToken currentAccessToken]) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:
                        [FBSDKAccessToken currentAccessToken].dataAccessExpired ? @"true" : @"false"];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:
                        @"Session not open."];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) reauthorizeDataAccess:(CDVInvokedUrlCommand *)command {
    if (self.loginTracking == FBSDKLoginTrackingLimited) {
        [self returnLimitedLoginMethodError:command.callbackId];
        return;
    }
    
    if (self.loginManager == nil) {
        self.loginManager = [[FBSDKLoginManager alloc] init];
    }
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
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsDictionary:[self loginResponseObject]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    };
    
    [self.loginManager reauthorizeDataAccess:[self topMostController] handler:reauthorizeHandler];
}

- (void) logout:(CDVInvokedUrlCommand*)command
{
    if ([FBSDKAccessToken currentAccessToken]) {
        // Close the session and clear the cache
        if (self.loginManager == nil) {
            self.loginManager = [[FBSDKLoginManager alloc] init];
        }

        [self.loginManager logOut];
    }

    // Else just return OK we are already logged out
    [self returnGenericSuccess:command.callbackId];
}

- (void) showDialog:(CDVInvokedUrlCommand*)command
{
    if ([command.arguments count] == 0) {
        CDVPluginResult *pluginResult;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:@"No method provided"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    NSMutableDictionary *options = [[command.arguments lastObject] mutableCopy];
    NSString* method = options[@"method"];
    if (!method) {
        CDVPluginResult *pluginResult;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:@"No method provided"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    [options removeObjectForKey:@"method"];
    NSDictionary *params = [options copy];

    // Check method
    if ([method isEqualToString:@"send"]) {
        // Send private message dialog
        // Create native params
        FBSDKShareLinkContent *content = [[FBSDKShareLinkContent alloc] init];
        content.contentURL = [NSURL URLWithString:[params objectForKey:@"link"]];

        self.dialogCallbackId = command.callbackId;
        [FBSDKMessageDialog showWithContent:content delegate:self];
        return;

    } else if ([method isEqualToString:@"share"] || [method isEqualToString:@"feed"]) {
        // Create native params
        self.dialogCallbackId = command.callbackId;
        // FBSDKShareDialog is a Swift class. Allocating it without running an initialiser leaves its
        // stored properties uninitialised, and its deinit walks one of them (temporaryFiles), so the
        // app crashes with EXC_BAD_ACCESS once the SDK releases the dialog.
        FBSDKShareDialog *dialog = [[FBSDKShareDialog alloc] initWithViewController:[self topMostController]
                                                                            content:nil
                                                                           delegate:self];
        if (params[@"photo_image"]) {
            // FBSDKSharePhoto is a Swift class that exposes no plain -init, so the image has to be
            // decoded before the photo is created. Sharing a photo with no image never succeeded
            // anyway, it just left the callback hanging, so a bad image is reported as an error.
            NSString *photoImage = params[@"photo_image"];
            UIImage *image = nil;
            if (![photoImage isKindOfClass:[NSString class]]) {
                NSLog(@"photo_image must be a string");
            } else {
                NSData *photoImageData = [[NSData alloc] initWithBase64EncodedString:photoImage options:NSDataBase64DecodingIgnoreUnknownCharacters];
                if (!photoImageData) {
                    NSLog(@"photo_image cannot be decoded");
                } else {
                    image = [UIImage imageWithData:photoImageData];
                }
            }
            if (!image) {
                self.dialogCallbackId = nil;
                CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                                  messageAsString:@"photo_image is not a valid base64 encoded image"];
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
        // Adopt native share sheets with the following line
        if (params[@"share_sheet"]) {
        	dialog.mode = FBSDKShareDialogModeShareSheet;
        } else if (params[@"share_feedBrowser"]) {
        	dialog.mode = FBSDKShareDialogModeFeedBrowser;
        } else if (params[@"share_native"]) {
        	dialog.mode = FBSDKShareDialogModeNative;
        } else if (params[@"share_feedWeb"]) {
        	dialog.mode = FBSDKShareDialogModeFeedWeb;
        }

        [dialog show];
        return;
    }
    else if ([method isEqualToString:@"apprequests"]) {
        // FBSDKGameRequestContent and FBSDKGameRequestDialog are Swift classes, so they have to be
        // initialised rather than merely allocated. The dialog's only initialiser takes the content,
        // which is why the content is built first.
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
        } else {
            NSLog(@"Discarding invalid argument actionType");
        }

        NSString *filters = params[@"filters"];
        if (!filters) {
            content.filters = FBSDKGameRequestFilterNone;
        } else if ([filters isEqualToString:@"app_users"]) {
            content.filters = FBSDKGameRequestFilterAppUsers;
        } else if ([filters isEqualToString:@"app_non_users"]) {
            content.filters = FBSDKGameRequestFilterAppNonUsers;
        }

        content.data = params[@"data"];
        content.message = params[@"message"];
        content.objectID = params[@"objectID"];
        content.recipients = params[@"to"];
        content.title = params[@"title"];

        FBSDKGameRequestDialog *dialog = [[FBSDKGameRequestDialog alloc] initWithContent:content delegate:self];
        if (![dialog canShow]) {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                              messageAsString:@"Cannot show dialog"];
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
    [FBSDKProfile loadCurrentProfileWithCompletion:^(FBSDKProfile *profile, NSError *error) {
        CDVPluginResult *pluginResult;
        if (![FBSDKProfile currentProfile]) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                             messageAsString:@"No current profile."];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                         messageAsDictionary:[self profileObject]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    }];
}

- (void) graphApi:(CDVInvokedUrlCommand *)command
{
    if (self.loginTracking == FBSDKLoginTrackingLimited) {
        [self returnLimitedLoginMethodError:command.callbackId];
        return;
    }
    
    CDVPluginResult *pluginResult;
    if (! [FBSDKAccessToken currentAccessToken]) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:@"You are not logged in."];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }

    NSString *graphPath = [command argumentAtIndex:0];
    NSArray *permissionsNeeded = [command argumentAtIndex:1];
    NSString *requestMethod = nil;
    if ([command.arguments count] >= 3) {
        requestMethod = [command argumentAtIndex:2];
    }

    NSSet *currentPermissions = [FBSDKAccessToken currentAccessToken].permissions;

    // We will store here the missing permissions that we will have to request
    NSMutableArray *requestPermissions = [[NSMutableArray alloc] initWithArray:@[]];
    NSArray *permissions;

    // Check if all the permissions we need are present in the user's current permissions
    // If they are not present add them to the permissions to be requested
    for (NSString *permission in permissionsNeeded){
        if (![currentPermissions containsObject:permission]) {
            [requestPermissions addObject:permission];
        }
    }
    permissions = [requestPermissions copy];

    // Defines block that handles the Graph API response
    FBSDKGraphRequestBlock graphHandler = ^(FBSDKGraphRequestConnection *connection, id result, NSError *error) {
        CDVPluginResult* pluginResult;
        if (error) {
            NSString *message = error.userInfo[FBSDKErrorLocalizedDescriptionKey] ?: @"There was an error making the graph call.";
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                             messageAsString:message];
        } else {
            NSDictionary *response = (NSDictionary *) result;
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:response];
        }
        NSLog(@"Finished GraphAPI request");

        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    };

    NSLog(@"Graph Path = %@", graphPath);
    FBSDKGraphRequest *request = [[FBSDKGraphRequest alloc] initWithGraphPath:graphPath parameters:nil HTTPMethod:requestMethod];

    // If we have permissions to request
    if ([permissions count] == 0){
        [request startWithCompletion:^(id<FBSDKGraphRequestConnecting>  _Nullable connection, id  _Nullable result, NSError * _Nullable error) {
            CDVPluginResult* pluginResult;
            if (error) {
                NSString *message = error.userInfo[FBSDKErrorLocalizedDescriptionKey] ?: @"There was an error making the graph call.";
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsString:message];
            } else {
                NSDictionary *response = (NSDictionary *) result;
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:response];
            }
            NSLog(@"Finished GraphAPI request");

            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }];
        return;
    }

    [self loginWithPermissions:requestPermissions withHandler:^(FBSDKLoginManagerLoginResult *result, NSError *error) {
        if (error) {
            // If the SDK has a message for the user, surface it.
            NSString *errorCode = @"-2";
            NSString *errorMessage = error.userInfo[FBSDKErrorLocalizedDescriptionKey];
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
            return;
        } else if (result.isCancelled) {
            NSString *errorCode = @"4201";
            NSString *errorMessage = @"User cancelled.";
            [self returnLoginError:command.callbackId:errorCode:errorMessage];
