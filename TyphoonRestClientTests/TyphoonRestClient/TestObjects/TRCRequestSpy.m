//
// Created by Aleksey Garbarev on 20.09.14.
// Copyright (c) 2014 Apps Quickly. All rights reserved.
//

#import "TRCRequestSpy.h"
#import "TRCConverter.h"
#import "TRCUtils.h"
#import "TestUtils.h"

@implementation TRCRequestSpy

- (id)init
{
    self = [super init];
    if (self) {
        self.parseObjectImplemented = YES;
    }
    return self;
}

- (TRCRequestMethod)method
{
    return TRCRequestMethodPost;
}

- (NSString *)path
{
    return nil;
}

- (TRCSerialization)requestBodySerialization
{
    return TRCSerializationJson;
}

- (TRCSerialization)responseBodySerialization
{
    return TRCSerializationResponseImage;
}

- (NSString *)responseBodyValidationSchemaName
{
    return self.responseSchemeName;
}

- (NSString *)requestBodyValidationSchemaName
{
    return self.requestSchemeName;
}

- (BOOL)respondsToSelector:(SEL)aSelector
{
    if (aSelector == @selector(responseProcessedFromBody:headers:status:error:)) {
        return self.parseObjectImplemented;
    }
    return [super respondsToSelector:aSelector];
}

- (id)responseProcessedFromBody:(id)responseObject headers:(NSDictionary *)headers status:(TRCHttpStatusCode)status error:(NSError **)parseError
{
    self.parseResponseObjectCalled = YES;

    if (self.insideParseBlock) {
        self.insideParseBlock();
    }

    if (parseError && self.parseError) {
        *parseError = self.parseError;
    }

    return self.parseResult;
}

@end