/*
 * <b>Copyright (c) 2016, Imagination Technologies Limited and/or its affiliated group companies
 *  and/or licensors. </b>
 *
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without modification, are permitted
 *  provided that the following conditions are met:
 *
 *  1. Redistributions of source code must retain the above copyright notice, this list of conditions
 *      and the following disclaimer.
 *
 *  2. Redistributions in binary form must reproduce the above copyright notice, this list of
 *      conditions and the following disclaimer in the documentation and/or other materials provided
 *      with the distribution.
 *
 *  3. Neither the name of the copyright holder nor the names of its contributors may be used to
 *      endorse or promote products derived from this software without specific prior written
 *      permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
 *  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
 *  FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
 *  CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 *  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 *  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 *  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
 *  WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */

#import "DataApi.h"
#import "AccountsServerApi.h"
#import "DeviceServerApi.h"
#import "AccessKeys.h"
#import "SecureDataStore.h"
#import "OauthManager.h"

@interface DataApi ()
@property(nonatomic, strong, nonnull) AccountsServerApi *accountApi;
@property(nonatomic, strong, nonnull) DeviceServerApi *deviceServerApi;
@property(nonatomic, strong, nonnull) NSOperationQueue *networkQueue;
@end

@implementation DataApi

- (AccountsServerApi *)accountApi {
    if (_accountApi == nil) {
        _accountApi = [AccountsServerApi new];
    }
    return _accountApi;
}

- (DeviceServerApi *)deviceServerApi {
    if (_deviceServerApi == nil) {
        _deviceServerApi = [DeviceServerApi new];
    }
    return _deviceServerApi;
}

- (NSOperationQueue *)networkQueue {
    if (_networkQueue == nil) {
        _networkQueue = [NSOperationQueue new];
        _networkQueue.name = @"DatApi network queue";
        _networkQueue.maxConcurrentOperationCount = 3;
    }
    return _networkQueue;
}

- (void)loginWithUsername:(nonnull NSString *)username
                 password:(nonnull NSString *)password
                  success:(SuccessBlock)success
                  failure:(FailureBlock)failure
{
    [self.networkQueue addOperation:[NSBlockOperation blockOperationWithBlock:^{
        NSError *error = nil;
        AccessKeys *accessKeys = [self.accountApi loginWithUsername:username
                                                           password:password
                                                              error:&error];
        if (error) {
            if (failure) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    failure(error);
                }];
            }
            return;
        }
        
        if (accessKeys != nil) {
            [[SecureDataStore class] storeUsername:username password:password];
        }
        
        if (accessKeys.items.count == 0) {
            if (failure) {
                NSError *err = [NSError errorWithDomain:@"com.imgtec.example.PowerSwitch.app" code:0 userInfo:@{@"description": @"No access keys."}];
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    failure(err);
                }];
            }
            return;
        }
        
        if (accessKeys.items.count > 1) {
            NSLog(@"Warning: More than one access key.");
        }
        
        AccessKey *accessKey = accessKeys.items.firstObject;
        [[SecureDataStore class] storeDeviceServerAccessKey:accessKey.key secret:accessKey.secret];
        
        [self.deviceServerApi loginWithKey:accessKey.key
                                    secret:accessKey.secret
                                     error:&error];
        if (error) {
            if (failure) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    failure(error);
                }];
            }
            return;
        }
        
        if (success) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                success();
            }];
        }
    }]];
}

- (BOOL)isSilentLoginStartPossible {
    return [[SecureDataStore class] readDeviceServerAccessKey] != nil && [[SecureDataStore class] readDeviceServerSecret] != nil;
}

- (void)silentLoginWithSuccess:(nullable SuccessBlock)success
                       failure:(nullable FailureBlock)failure
{
    [self.networkQueue addOperation:[NSBlockOperation blockOperationWithBlock:^{
        NSString *accessKey = [[SecureDataStore class] readDeviceServerAccessKey];
        NSString *secret = [[SecureDataStore class] readDeviceServerSecret];
        
        if (accessKey && secret) {
            NSError *error = nil;
            [self.deviceServerApi loginWithKey:accessKey
                                        secret:secret
                                         error:&error];
            if (error) {
                if (failure) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        failure(error);
                    }];
                }
                return;
            }
            
            if (success) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    success();
                }];
                return;
            }
        }
        
        if (failure) {
            NSError *error = [NSError errorWithDomain:@"com.imgtec.example.PowerSwitch.app" code:0 userInfo:@{@"description": @"Access key / secret is not present. Slient login not performed."}];
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                failure(error);
            }];
        }
    }]];
}

- (void)logout {
    [[SecureDataStore class] cleanUsernamePassword];
    [[SecureDataStore class] cleanDeviceServerAccessKeySecret];
}

- (void)requestGatewaysWithSuccess:(nullable RequestGatewaysSuccessBlock)success
                           failure:(nullable FailureBlock)failure
{
    [self.networkQueue addOperation:[NSBlockOperation blockOperationWithBlock:^{
        NSError *error = nil;
        Clients *clients = [self.deviceServerApi clientsWithError:&error];
        if (error || clients == nil) {
            if (failure) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    failure(error);
                }];
            }
            return;
        }
        
        NSMutableArray<Client *> *newItems = [NSMutableArray new];
        for (Client *client in clients.items) {
            if ([client.name hasPrefix:@"RelayDevice"]) {
                [newItems addObject:client];
            }
        }
        
        if (clients.items.count != newItems.count) {
            clients.items = [newItems copy];
            clients.pageInfo = nil;
        }
        
        if (success) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                success(clients);
            }];
        }
    }]];
}

- (void)requestRelayDevicesForClient:(nonnull Client *)client
                             success:(nullable RelayDevicesSuccessBlock)success
                             failure:(nullable FailureBlock)failure
{
    [self.networkQueue addOperation:[NSBlockOperation blockOperationWithBlock:^{
        NSError *error = nil;
        ObjectTypes *objectTypes = [self.deviceServerApi objectTypesForClient:client error:&error];
        if (error || objectTypes == nil) {
            if (failure) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    failure(error);
                }];
            }
            return;
        }
        
        NSMutableArray<RelayDevice *> *relayDevices = [NSMutableArray new];
        NSUInteger instanceId = 0;
        for (ObjectType *objectType in objectTypes.items) {
            NSString *IPSODigitalOutputObjectID = [[RelayDevice class] IPSOObjectID];
            if ([objectType.objectTypeID isEqualToString:IPSODigitalOutputObjectID]) {
                Instances *instances = [self.deviceServerApi objectInstancesForObjectType:objectType error:&error];
                if (error || instances == nil) {
                    if (failure) {
                        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                            failure(error);
                        }];
                    }
                    return;
                }
                
                for (IPSOInstance *instance in instances.items) {
                    IPSODigitalOutputInstance *digitalOutputInstance = [[IPSODigitalOutputInstance alloc] initWithJson:instance.json];
                    RelayDevice *relayDevice = [[RelayDevice alloc] initWithObjectType:objectType instanceId:@(instanceId) resources:digitalOutputInstance];
                    [relayDevices addObject:relayDevice];
                }
            }
        }
        
        if (success) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                success([relayDevices copy]);
            }];
        }
    }]];
}

- (void)setRelayDeviceState:(nonnull RelayDevice *)relayDevice
                   newValue:(BOOL)on
                    success:(nullable SuccessBlock)success
                    failure:(nullable FailureBlock)failure
{
    [self.networkQueue addOperation:[NSBlockOperation blockOperationWithBlock:^{
        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"DigitalOutputState": @(on)} options:0 error:&error];
        if (error) {
            return;
        }
        
        [self.deviceServerApi putInstanceData:data forObject:relayDevice.objectType instanceId:relayDevice.instanceId error:&error];
        if (error) {
            if (failure) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    failure(error);
                }];
            }
        } else {
            if (success) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    success();
                }];
            }
        }
        
    }]];
}

@end