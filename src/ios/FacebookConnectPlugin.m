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
- (void)initFbSdkWithOpts:(NSDictionary *)launchOptions;

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

    /* Bloco nativo bloqueado para Privacidade / ATT - Retirado na totalidade para evitar unused variables */
}

- (void) applicationDidFinishLaunching:(NSNotification *) notification {
    (void)notification; // Evita erro no MABS (Unused Parameter)
}

- (void) initFbSdkWithOpts:(NSDictionary *) launchOptions {
    NSDictionary *finalLaunchOptions;
    
    if (self.sdkInit) {
        return;
    }
    self.sdkInit = YES;

    if (launchOptions == nil) {
        finalLaunchOptions = [NSDictionary dictionary];
    } else {
        finalLaunchOptions = launchOptions;
    }

    if ([NSThread isMainThread]) {
        [[FBSDKApplicationDelegate sharedInstance] application:[UIApplication sharedApplication] didFinishLaunchingWithOptions:finalLaunchOptions];
        [FBSDKProfile enableUpdatesOnAccessTokenChange:YES];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [[FBSDKApplicationDelegate sharedInstance] application:[UIApplication sharedApplication] didFinishLaunchingWithOptions:finalLaunchOptions];
            [FBSDKProfile enableUpdatesOnAccessTokenChange:YES];
        });
    }
}

- (void) applicationDidBecomeActive:(NSNotification *) notification {
    (void)notification; // Evita erro no MABS (Unused Parameter)

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
    NSString *appId;
    if ([command.arguments count] == 0) {
        [self returnInvalidArgsError:command.callbackId];
        return;
    }
    appId = [command argumentAtIndex:0];
    [FBSDKSettings.sharedSettings setAppID:appId];
    [self returnGenericSuccess:command.callbackId];
}

- (void)getClientToken:(CDVInvokedUrlCommand *)command {
    NSString *clientToken = FBSDKSettings.sharedSettings.clientToken;
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:clientToken];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setClientToken:(CDVInvokedUrlCommand *)command {
    NSString *clientToken;
    if ([command.arguments count] == 0) {
        [self returnInvalidArgsError:command.callbackId];
        return;
    }
    clientToken = [command argumentAtIndex:0];
    [FBSDKSettings.sharedSettings setClientToken:clientToken];
    [self returnGenericSuccess:command.callbackId];
}

- (void)getApplicationName:(CDVInvokedUrlCommand *)command {
    NSString *displayName = FBSDKSettings.sharedSettings.displayName;
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:displayName];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setApplicationName:(CDVInvokedUrlCommand *)command {
    NSString *displayName;
    if ([command.arguments count] == 0) {
        [self returnInvalidArgsError:command.callbackId];
        return;
    }
    displayName = [command argumentAtIndex:0];
    [FBSDKSettings.sharedSettings setDisplayName:displayName];
    [self returnGenericSuccess:command.callbackId];
}

- (void)getLoginStatus:(CDVInvokedUrlCommand *)command {
    BOOL force;
    if (self.loginTracking == FBSDKLoginTrackingLimited) {
        [self returnLimitedLoginMethodError:command.callbackId];
        return;
    }
    
    force = [[command argumentAtIndex:0] boolValue];
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
    CDVPluginResult *pluginResult;
    if (self.loginTracking == FBSDKLoginTrackingLimited) {
        [self returnLimitedLoginMethodError:command.callbackId];
        return;
    }
    
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
    [self initFbSdkWithOpts:nil];
    [FBSDKSettings.sharedSettings setAutoLogAppEventsEnabled:enabled];
    [self returnGenericSuccess:command.callbackId];
}

- (void)setAdvertiserIDCollectionEnabled:(CDVInvokedUrlCommand *)command {
    BOOL enabled = [[command argumentAtIndex:0] boolValue];
    [self initFbSdkWithOpts:nil];
    [FBSDKSettings.sharedSettings setAdvertiserIDCollectionEnabled:enabled];
    [self returnGenericSuccess:command.callbackId];
}

- (void)setAdvertiserTrackingEnabled:(CDVInvokedUrlCommand *)command {
    BOOL enabled = [[command argumentAtIndex:0] boolValue];
    [self initFbSdkWithOpts:nil];
    [FBSDKSettings.sharedSettings setAdvertiserTrackingEnabled:enabled];
    [self returnGenericSuccess:command.callbackId];
}

- (void)setDataProcessingOptions:(CDVInvokedUrlCommand *)command {
    NSArray *options;
    int32_t country;
    int32_t state;
    
    if ([command.arguments count] == 0) {
        [self returnInvalidArgsError:command.callbackId];
        return;
    }

    options = [command argumentAtIndex:0];
    if ([command.arguments count] == 1) {
        [FBSDKSettings.sharedSettings setDataProcessingOptions:options];
    } else {
        country = [[command.arguments objectAtIndex:1] intValue];
        state = [[command.arguments objectAtIndex:2] intValue];
        [FBSDKSettings.sharedSettings setDataProcessingOptions:options country:country state:state];
    }
    [self returnGenericSuccess:command.callbackId];
}

- (void)setUserData:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] == 0) {
        [self returnInvalidArgsError:command.callbackId];
        return;
    }

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

- (void)logEvent:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] == 0) {
        [self returnInvalidArgsError:command.callbackId];
        return;
    }

    [self initFbSdkWithOpts:nil];

    [self.commandDelegate runInBackground:^{
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
        [self returnGenericSuccess:command.callbackId];
    }];
}

- (void)logPurchase:(CDVInvokedUrlCommand *)command {
    if ([command.arguments count] < 2 || [command.arguments count] > 3 ) {
        [self returnInvalidArgsError:command.callbackId];
        return;
    }

    [self initFbSdkWithOpts:nil];

    [self.commandDelegate runInBackground:^{
        double value = [[command.arguments objectAtIndex:0] doubleValue];
        NSString *currency = [command.arguments objectAtIndex:1];
        NSDictionary *params;

        if (![[NSLocale ISOCurrencyCodes] containsObject:currency]) {
            CDVPluginResult *res = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                     messageAsString:[NSString stringWithFormat:@"Invalid currency code: %@", currency]];
            [self.commandDelegate sendPluginResult:res callbackId:command.callbackId];
            return;
        }

        if ([command.arguments count] == 2 ) {
            [FBSDKAppEvents.shared logPurchase:value currency:currency];
        } else if ([command.arguments count] >= 3) {
            params = [command.arguments objectAtIndex:2];
            [FBSDKAppEvents.shared logPurchase:value currency:currency parameters:params];
        }
        [self returnGenericSuccess:command.callbackId];
    }];
}

- (void)login:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult;
    NSArray *permissions = nil;
    FBSDKLoginManagerLoginResultBlock loginHandler;

    NSLog(@"Starting login");
    [self initFbSdkWithOpts:nil];

    if ([command.arguments count] > 0) {
        permissions = command.arguments;
    }

    [FBSDKAccessToken refreshCurrentAccessTokenWithCompletion:nil];

    loginHandler = ^void(FBSDKLoginManagerLoginResult *result, NSError *error) {
        CDVPluginResult *blockPluginResult;
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
            blockPluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsDictionary:[self loginResponseObject]];
            [self.commandDelegate sendPluginResult:blockPluginResult callbackId:command.callbackId];
        }
    };

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
        NSString *permissionsErrorMessage = @"No permissions specified at login";
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:permissionsErrorMessage];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    [self loginWithPermissions:permissions withHandler:loginHandler];
}

- (void)loginWithLimitedTracking:(CDVInvokedUrlCommand *)command {
    NSArray *permissions;
    NSArray *permissionsArray = @[];
    NSString *nonce;
    FBSDKLoginManagerLoginResultBlock loginHandler;
    FBSDKLoginConfiguration *configuration;
    CDVPluginResult *pluginResult;

    if ([command.arguments count] == 1) {
        NSString *nonceErrorMessage = @"No nonce specified";
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:nonceErrorMessage];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    permissions = [command argumentAtIndex:0];
    nonce = [command argumentAtIndex:1];

    if ([permissions count] > 0) {
        permissionsArray = permissions;
    }

    loginHandler = ^void(FBSDKLoginManagerLoginResult *result, NSError *error) {
        CDVPluginResult *blockPluginResult;
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
            blockPluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsDictionary:[self limitedLoginResponseObject]];
            [self.commandDelegate sendPluginResult:blockPluginResult callbackId:command.callbackId];
        }
    };

    if (self.loginManager == nil || self.loginTracking == FBSDKLoginTrackingEnabled) {
        self.loginManager = [FBSDKLoginManager new];
    }
    
    self.loginTracking = FBSDKLoginTrackingLimited;
    configuration = [[FBSDKLoginConfiguration alloc] initWithPermissions:permissionsArray tracking:FBSDKLoginTrackingLimited nonce:nonce];
    [self.loginManager logInFromViewController:[self topMostController] configuration:configuration completion:loginHandler];
}

- (void) checkHasCorrectPermissions:(CDVInvokedUrlCommand*)command
{
    NSArray *permissions = nil;
    NSSet *grantedPermissions;
    CDVPluginResult* pluginResult;

    if (self.loginTracking == FBSDKLoginTrackingLimited) {
        [self returnLimitedLoginMethodError:command.callbackId];
        return;
    }

    if ([command.arguments count] > 0) {
        permissions = command.arguments;
    }
    
    grantedPermissions = [FBSDKAccessToken currentAccessToken].permissions;

    for (NSString *value in permissions) {
        if (![grantedPermissions containsObject:value]) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                              messageAsString:@"A permission has been denied"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }
    }
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsString:@"All permissions have been accepted"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
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
    FBSDKLoginManagerLoginResultBlock reauthorizeHandler;

    if (self.loginTracking == FBSDKLoginTrackingLimited) {
        [self returnLimitedLoginMethodError:command.callbackId];
        return;
    }
    
    if (self.loginManager == nil) {
        self.loginManager = [[FBSDKLoginManager alloc] init];
    }
    self.loginTracking = FBSDKLoginTrackingEnabled;
    
    reauthorizeHandler = ^void(FBSDKLoginManagerLoginResult *result, NSError *error) {
        CDVPluginResult *pluginResult;
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
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsDictionary:[self loginResponseObject]];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    };
    
    [self.loginManager reauthorizeDataAccess:[self topMostController] handler:reauthorizeHandler];
}

- (void) logout:(CDVInvokedUrlCommand*)command
{
    if ([FBSDKAccessToken currentAccessToken]) {
        if (self.loginManager == nil) {
            self.loginManager = [[FBSDKLoginManager alloc] init];
        }
        [self.loginManager logOut];
    }
    [self returnGenericSuccess:command.callbackId];
}

- (void) showDialog:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult *pluginResult;
    NSMutableDictionary *options;
    NSString* method;
    NSDictionary *params;

    if ([command.arguments count] == 0) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:@"No method provided"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    options = [[command.arguments lastObject] mutableCopy];
    method = options[@"method"];
    
    if (!method) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:@"No method provided"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    [options removeObjectForKey:@"method"];
    params = [options copy];

    if ([method isEqualToString:@"send"]) {
        FBSDKShareLinkContent *content = [[FBSDKShareLinkContent alloc] init];
        content.contentURL = [NSURL URLWithString:[params objectForKey:@"link"]];

        self.dialogCallbackId = command.callbackId;
        [FBSDKMessageDialog showWithContent:content delegate:self];
        return;

    } else if ([method isEqualToString:@"share"] || [method isEqualToString:@"feed"]) {
        FBSDKShareDialog *dialog;
        
        self.dialogCallbackId = command.callbackId;
        dialog = [[FBSDKShareDialog alloc] initWithViewController:[self topMostController]
                                                                            content:nil
                                                                           delegate:self];
        if (params[@"photo_image"]) {
            NSString *photoImage = params[@"photo_image"];
            UIImage *image = nil;
            NSData *photoImageData;
            FBSDKSharePhoto *photo;
            FBSDKSharePhotoContent *content;

            if (![photoImage isKindOfClass:[NSString class]]) {
                NSLog(@"photo_image must be a string");
            } else {
                photoImageData = [[NSData alloc] initWithBase64EncodedString:photoImage options:NSDataBase64DecodingIgnoreUnknownCharacters];
                if (photoImageData) {
                    image = [UIImage imageWithData:photoImageData];
                }
            }
            if (!image) {
                self.dialogCallbackId = nil;
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                                  messageAsString:@"photo_image is not a valid base64 encoded image"];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                return;
            }
            photo = [[FBSDKSharePhoto alloc] initWithImage:image isUserGenerated:YES];
            content = [[FBSDKSharePhotoContent alloc] init];
            content.photos = @[photo];
            dialog.shareContent = content;
        } else {
            FBSDKShareLinkContent *content = [[FBSDKShareLinkContent alloc] init];
            content.contentURL = [NSURL URLWithString:params[@"href"]];
            content.hashtag = [[FBSDKHashtag alloc] initWithString:[params objectForKey:@"hashtag"]];
            content.quote = params[@"quote"];
            dialog.shareContent = content;
        }
        
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
        FBSDKGameRequestContent *content = [[FBSDKGameRequestContent alloc] init];
        NSString *actionType = params[@"actionType"];
        NSString *filters;
        FBSDKGameRequestDialog *dialog;

        if (!actionType) {
            NSLog(@"Discarding invalid argument actionType");
        } else if ([[actionType lowercaseString] isEqualToString:@"askfor"]) {
            content.actionType = FBSDKGameRequestActionTypeAskFor;
        } else if ([[actionType lowercaseString] isEqualToString:@"send"]) {
            content.actionType = FBSDKGameRequestActionTypeSend;
        } else if ([[actionType lowercaseString] isEqualToString:@"turn"]) {
            content.actionType = FBSDKGameRequestActionTypeTurn;
        }

        filters = params[@"filters"];
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

        dialog = [[FBSDKGameRequestDialog alloc] initWithContent:content delegate:self];
        if (![dialog canShow]) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                              messageAsString:@"Cannot show dialog"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }

        self.gameRequestDialogCallbackId = command.callbackId;
        [dialog show];
        return;
    }
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"method not supported"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)getCurrentProfile:(CDVInvokedUrlCommand *)command {
    [FBSDKProfile loadCurrentProfileWithCompletion:^(FBSDKProfile *profile, NSError *error) {
        CDVPluginResult *pluginResult;
        if (![FBSDKProfile currentProfile]) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                             messageAsString:@"No current profile."];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                         messageAsDictionary:[self profileObject]];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void) graphApi:(CDVInvokedUrlCommand *)command
{
    CDVPluginResult *pluginResult;
    NSString *graphPath;
    NSArray *permissionsNeeded;
    NSString *requestMethod = nil;
    NSSet *currentPermissions;
    NSMutableArray *requestPermissions;
    NSArray *permissions;
    FBSDKGraphRequest *request;

    if (self.loginTracking == FBSDKLoginTrackingLimited) {
        [self returnLimitedLoginMethodError:command.callbackId];
        return;
    }
    
    if (! [FBSDKAccessToken currentAccessToken]) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                         messageAsString:@"You are not logged in."];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    graphPath = [command argumentAtIndex:0];
    permissionsNeeded = [command argumentAtIndex:1];
    
    if ([command.arguments count] >= 3) {
        requestMethod = [command argumentAtIndex:2];
    }

    currentPermissions = [FBSDKAccessToken currentAccessToken].permissions;
    requestPermissions = [[NSMutableArray alloc] initWithArray:@[]];

    for (NSString *permission in permissionsNeeded){
        if (![currentPermissions containsObject:permission]) {
            [requestPermissions addObject:permission];
        }
    }
    permissions = [requestPermissions copy];

    NSLog(@"Graph Path = %@", graphPath);
    request = [[FBSDKGraphRequest alloc] initWithGraphPath:graphPath parameters:nil HTTPMethod:requestMethod];

    if ([permissions count] == 0){
        [request startWithCompletion:^(id<FBSDKGraphRequestConnecting>  _Nullable connection, id  _Nullable result, NSError * _Nullable error) {
            CDVPluginResult* blockResult;
            NSDictionary *response;
            if (error) {
                NSString *message = error.userInfo[FBSDKErrorLocalizedDescriptionKey] ?: @"There was an error making the graph call.";
                blockResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsString:message];
            } else {
                response = (NSDictionary *) result;
                blockResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:response];
            }
            [self.commandDelegate sendPluginResult:blockResult callbackId:command.callbackId];
        }];
        return;
    }

    [self loginWithPermissions:requestPermissions withHandler:^(FBSDKLoginManagerLoginResult *result, NSError *error) {
        NSString *deniedPermission = nil;
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

        for (NSString *permission in permissions) {
            if (![result.grantedPermissions containsObject:permission]) {
                deniedPermission = permission;
                break;
            }
        }

        if (deniedPermission != nil) {
            NSString *errorMessage = [NSString stringWithFormat:@"The user didnt allow necessary permission %@", deniedPermission];
            CDVPluginResult* blockResult2 = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                              messageAsString:errorMessage];
            [self.commandDelegate sendPluginResult:blockResult2 callbackId:command.callbackId];
            return;
        }

        [request startWithCompletion:^(id<FBSDKGraphRequestConnecting>  _Nullable connection, id  _Nullable result, NSError * _Nullable error) {
            CDVPluginResult* blockResult3;
            NSDictionary *response;
            if (error) {
                NSString *message = error.userInfo[FBSDKErrorLocalizedDescriptionKey] ?: @"There was an error making the graph call.";
                blockResult3 = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsString:message];
            } else {
                response = (NSDictionary *) result;
                blockResult3 = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:response];
            }
            [self.commandDelegate sendPluginResult:blockResult3 callbackId:command.callbackId];
        }];
    }];
}

- (void) getDeferredApplink:(CDVInvokedUrlCommand *) command
{
    [FBSDKAppLinkUtility fetchDeferredAppLink:^(NSURL *url, NSError *error) {
        CDVPluginResult* pluginResult;
        if (error) {
            NSString *errorMessage = error.userInfo[FBSDKErrorLocalizedDescriptionKey] ?: @"Received error while fetching deferred app link.";
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                              messageAsString:errorMessage];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }
        if (url) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:url.absoluteString];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } else {
            [self returnGenericSuccess:command.callbackId];
        }
    }];
}

- (void) activateApp:(CDVInvokedUrlCommand *)command
{
    [self initFbSdkWithOpts:nil];
    [FBSDKAppEvents.shared activateApp];
    [self returnGenericSuccess:command.callbackId];
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
    CDVPluginResult *pluginResult;
    
    response[@"errorCode"] = errorCode ?: @"-2";
    response[@"errorMessage"] = errorMessage ?: @"There was a problem logging you in.";
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                     messageAsDictionary:response];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

- (void) returnLimitedLoginMethodError:(NSString *)callbackId {
    NSString *methodErrorMessage = @"Method not available when using Limited Login";
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                     messageAsString:methodErrorMessage];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

- (void) loginWithPermissions:(NSArray *)permissions withHandler:(FBSDKLoginManagerLoginResultBlock) handler {
    if (self.loginManager == nil) {
        self.loginManager = [[FBSDKLoginManager alloc] init];
    }
    self.loginTracking = FBSDKLoginTrackingEnabled;
    [self.loginManager logInWithPermissions:permissions fromViewController:[self topMostController] handler:handler];
}

- (UIViewController*) topMostController {
    UIViewController *topController = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    return topController;
}

- (NSDictionary *)loginResponseObject {
    NSMutableDictionary *response;
    FBSDKAccessToken *token;
    NSTimeInterval dataAccessExpirationTimeInterval;
    NSString *dataAccessExpirationTime = @"0";
    NSTimeInterval expiresTimeInterval;
    NSString *expiresIn = @"0";

    if (![FBSDKAccessToken currentAccessToken]) {
        return @{@"status": @"unknown"};
    }
    
    response = [[NSMutableDictionary alloc] init];
    token = [FBSDKAccessToken currentAccessToken];
    dataAccessExpirationTimeInterval = token.dataAccessExpirationDate.timeIntervalSince1970;
    
    if (dataAccessExpirationTimeInterval > 0) {
        dataAccessExpirationTime = [NSString stringWithFormat:@"%0.0f", dataAccessExpirationTimeInterval];
    }
    
    expiresTimeInterval = token.expirationDate.timeIntervalSinceNow;
    
    if (expiresTimeInterval > 0) {
        expiresIn = [NSString stringWithFormat:@"%0.0f", expiresTimeInterval];
    }
    
    response[@"status"] = @"connected";
    response[@"authResponse"] = @{
                                  @"accessToken" : token.tokenString ? token.tokenString : @"",
                                  @"data_access_expiration_time" : dataAccessExpirationTime,
                                  @"expiresIn" : expiresIn,
                                  @"userID" : token.userID ? token.userID : @""
                                  };
    return [response copy];
}

- (NSDictionary *)limitedLoginResponseObject {
    NSMutableDictionary *response;
    FBSDKAuthenticationToken *token;
    NSString *userID;

    if (![FBSDKAuthenticationToken currentAuthenticationToken]) {
        return @{@"status": @"unknown"};
    }
    
    response = [[NSMutableDictionary alloc] init];
    token = [FBSDKAuthenticationToken currentAuthenticationToken];
    
    if ([FBSDKProfile currentProfile]) {
        userID = [FBSDKProfile currentProfile].userID;
    }
    
    response[@"status"] = @"connected";
    response[@"authResponse"] = @{
                                  @"authenticationToken" : token.tokenString ? token.tokenString : @"",
                                  @"nonce" : token.nonce ? token.nonce : @"",
                                  @"userID" : userID ? userID : @""
                                  };
    return [response copy];
}

- (NSDictionary *)profileObject {
    NSMutableDictionary *response;
    FBSDKProfile *profile;
    NSString *userID;
    NSString *name;
    NSString *email;
    NSString *firstName;
    NSString *lastName;

    if ([FBSDKProfile currentProfile] == nil) {
        return @{};
    }
    
    response = [[NSMutableDictionary alloc] init];
    profile = [FBSDKProfile currentProfile];
    userID = profile.userID;
    response[@"userID"] = userID ? userID : @"";
    
    if (self.loginTracking == FBSDKLoginTrackingLimited) {
        name = profile.name;
        email = profile.email;
        if (name) response[@"name"] = name;
        if (email) response[@"email"] = email;
    } else {
        firstName = profile.firstName;
        lastName = profile.lastName;
        response[@"firstName"] = firstName ? firstName : @"";
        response[@"lastName"] = lastName ? lastName : @"";
    }
    return [response copy];
}

- (void)enableHybridAppEvents {
    NSString *is_enabled;
    if ([self.webView isMemberOfClass:[WKWebView class]]){
        is_enabled = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"FacebookHybridAppEvents"];
        if([is_enabled isEqualToString:@"true"]){
            [FBSDKAppEvents.shared augmentHybridWebView:(WKWebView*)self.webView];
            NSLog(@"FB Hybrid app events are enabled");
        } else {
            NSLog(@"FB Hybrid app events are not enabled");
        }
    } else {
        NSLog(@"FB Hybrid app events cannot be enabled, this feature requires WKWebView");
    }
}

# pragma mark - FBSDKSharingDelegate

- (void)sharer:(id<FBSDKSharing>)sharer didCompleteWithResults:(NSDictionary *)results {
    CDVPluginResult *pluginResult;
    (void)sharer; 
    
    if (!self.dialogCallbackId) return;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                 messageAsDictionary:results];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.dialogCallbackId];
    self.dialogCallbackId = nil;
}

- (void)sharer:(id<FBSDKSharing>)sharer didFailWithError:(NSError *)error {
    CDVPluginResult *pluginResult;
    (void)sharer; 
    
    if (!self.dialogCallbackId) return;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                     messageAsString:[NSString stringWithFormat:@"Error: %@", error.description]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.dialogCallbackId];
    self.dialogCallbackId = nil;
}

- (void)sharerDidCancel:(id<FBSDKSharing>)sharer {
    CDVPluginResult *pluginResult;
    (void)sharer; 
    
    if (!self.dialogCallbackId) return;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                      messageAsString:@"User cancelled."];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.dialogCallbackId];
    self.dialogCallbackId = nil;
}

#pragma mark - FBSDKGameRequestDialogDelegate

- (void)gameRequestDialog:(FBSDKGameRequestDialog *)gameRequestDialog didCompleteWithResults:(NSDictionary *)results
{
    CDVPluginResult *pluginResult;
    (void)gameRequestDialog; 
    
    if (!self.gameRequestDialogCallbackId) return;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:results];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.gameRequestDialogCallbackId];
    self.gameRequestDialogCallbackId = nil;
}

- (void)gameRequestDialogDidCancel:(FBSDKGameRequestDialog *)gameRequestDialog
{
    CDVPluginResult *pluginResult;
    (void)gameRequestDialog; 
    
    if (!self.gameRequestDialogCallbackId) return;

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"User cancelled dialog"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.gameRequestDialogCallbackId];
    self.gameRequestDialogCallbackId = nil;
}

- (void)gameRequestDialog:(FBSDKGameRequestDialog *)gameRequestDialog didFailWithError:(NSError *)error
{
    NSString *message;
    CDVPluginResult *pluginResult;
    (void)gameRequestDialog; 
    
    if (!self.gameRequestDialogCallbackId)
