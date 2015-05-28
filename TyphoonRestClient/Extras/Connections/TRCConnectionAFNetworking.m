////////////////////////////////////////////////////////////////////////////////
//
//  TYPHOON REST CLIENT
//  Copyright 2015, Typhoon Rest Client Contributors
//  All Rights Reserved.
//
//  NOTICE: The authors permit you to use, modify, and distribute this file
//  in accordance with the terms of the license agreement accompanying it.
//
////////////////////////////////////////////////////////////////////////////////

#import "TRCConnectionAFNetworking.h"
#import "AFURLRequestSerialization.h"
#import "AFURLResponseSerialization.h"
#import "AFHTTPRequestOperationManager.h"
#import "TRCInfrastructure.h"
#import "TRCUtils.h"
#import "TyphoonRestClientErrors.h"

NSError *NSErrorWithDictionaryUnion(NSError *error, NSDictionary *dictionary);
BOOL IsBodyAllowedInHttpMethod(TRCRequestMethod method);

//=============================================================================================================================

@interface AFTRCResponseSerializer : AFHTTPResponseSerializer
@property (nonatomic, strong) id<TRCResponseSerializer> serializer;
@end

@implementation AFTRCResponseSerializer

- (id)responseObjectForResponse:(NSURLResponse *)response data:(NSData *)data error:(NSError *__autoreleasing *)errorOut
{
    NSError *statusCodeError = nil;
    NSError *serializerError = nil;
    NSError *contentTypeError = nil;
    id result = nil;

    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *urlResponse = (NSHTTPURLResponse *)response;
        if (self.acceptableStatusCodes && ![self.acceptableStatusCodes containsIndex:(NSUInteger)urlResponse.statusCode] && [response URL]) {
            NSMutableDictionary *mutableUserInfo = [@{
                    NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedStringFromTable(@"Request failed: %@ (%ld)", @"AFNetworking", nil), [NSHTTPURLResponse localizedStringForStatusCode:urlResponse.statusCode], (long)urlResponse.statusCode],
                    NSURLErrorFailingURLErrorKey : [response URL],
                    TyphoonRestClientErrorKeyResponse : response,
            } mutableCopy];
            if (data) {
                mutableUserInfo[TyphoonRestClientErrorKeyResponseData] = data;
            }
            statusCodeError = [[NSError alloc] initWithDomain:TyphoonRestClientErrors code:TyphoonRestClientErrorCodeBadResponseCode userInfo:mutableUserInfo];
        }
    }

    BOOL correctContentType = YES;

    if ([self.serializer respondsToSelector:@selector(isCorrectContentType:)]) {
        correctContentType = [self.serializer isCorrectContentType:[response MIMEType]];
    }

    if (correctContentType) {
        result = [self.serializer objectFromResponseData:data error:&serializerError];
    } else {
        contentTypeError = TRCErrorWithFormat(TyphoonRestClientErrorCodeBadResponseMime, @"Unacceptable content-type: %@", [response MIMEType]);
    }

    if (errorOut) {
        if (statusCodeError) {
            *errorOut = statusCodeError;
        } else if (contentTypeError) {
            *errorOut = contentTypeError;
        } else if (serializerError) {
            *errorOut = serializerError;
        }
    }

    return result;
}

@end

@interface AFTRCRequestSerializer : AFHTTPRequestSerializer
@property (nonatomic, strong) id<TRCRequestSerializer> serializer;
@end

@implementation AFTRCRequestSerializer

- (NSURLRequest *)requestBySerializingRequest:(NSURLRequest *)request
                               withParameters:(id)parameters
                                        error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(request);

    if ([self.HTTPMethodsEncodingParametersInURI containsObject:[[request HTTPMethod] uppercaseString]]) {
        return request;
    } else {
        NSMutableURLRequest *mutableRequest = [request mutableCopy];

        [self.HTTPRequestHeaders enumerateKeysAndObjectsUsingBlock:^(id field, id value, BOOL * __unused stop) {
            if (![request valueForHTTPHeaderField:field]) {
                [mutableRequest setValue:value forHTTPHeaderField:field];
            }
        }];

        if (parameters) {
            if (![mutableRequest valueForHTTPHeaderField:@"Content-Type"]
                    && [self.serializer respondsToSelector:@selector(contentType)] && [self.serializer contentType]) {
                [mutableRequest setValue:[self.serializer contentType] forHTTPHeaderField:@"Content-Type"];
            }

            if ([self.serializer respondsToSelector:@selector(dataFromRequestObject:error:)]) {
                NSData *data = [self.serializer dataFromRequestObject:parameters error:error];
                if (data) {
                    [mutableRequest setHTTPBody:data];
                }
            } else if ([self.serializer respondsToSelector:@selector(dataStreamFromRequestObject:error:)]) {
                NSInputStream *stream = [self.serializer dataStreamFromRequestObject:parameters error:error];
                if (stream) {
                    [mutableRequest setHTTPBodyStream:stream];
                }
            }
        }

        return mutableRequest;
    }
}

@end

//=============================================================================================================================

@interface TRCAFNetworkingConnectionProgressHandler : NSObject <TRCProgressHandler>

@property (nonatomic, weak) AFHTTPRequestOperation *operation;

@property (atomic, strong) TRCUploadProgressBlock uploadProgressBlock;
@property (atomic, strong) TRCDownloadProgressBlock downloadProgressBlock;

@end

@implementation TRCAFNetworkingConnectionProgressHandler
- (void)setOperation:(AFHTTPRequestOperation *)operation
{
    [_operation setUploadProgressBlock:nil];
    [_operation setDownloadProgressBlock:nil];

    _operation = operation;

    [_operation setUploadProgressBlock:^(NSUInteger bytesWritten, long long int totalBytesWritten, long long int totalBytesExpectedToWrite) {
        if (self.uploadProgressBlock) {
            self.uploadProgressBlock(bytesWritten, totalBytesWritten, totalBytesExpectedToWrite);
        }
    }];

    [_operation setDownloadProgressBlock:^(NSUInteger bytesWritten, long long int totalBytesWritten, long long int totalBytesExpectedToWrite) {
        if (self.downloadProgressBlock) {
            self.downloadProgressBlock(bytesWritten, totalBytesWritten, totalBytesExpectedToWrite);
        }
    }];
}
- (void)pause
{
    [_operation pause];
}
- (void)resume
{
    [_operation resume];
}
- (void)cancel
{
    [_operation cancel];
}
@end

@interface TRCAFNetworkingConnectionResponseInfo : NSObject <TRCResponseInfo>
@property (nonatomic, strong) NSHTTPURLResponse *response;
@property (nonatomic, strong) NSData *responseData;
+ (instancetype)infoWithOperation:(AFHTTPRequestOperation *)operation;
@end
@implementation TRCAFNetworkingConnectionResponseInfo
+ (instancetype)infoWithOperation:(AFHTTPRequestOperation *)operation
{
    TRCAFNetworkingConnectionResponseInfo *object = [TRCAFNetworkingConnectionResponseInfo new];
    object.response = operation.response;
    object.responseData = operation.responseData;
    return object;
}
@end

//=============================================================================================================================

@implementation TRCConnectionAFNetworking
{
    AFHTTPRequestOperationManager *_operationManager;
    NSCache *_responseSerializersCache;
    NSCache *_requestSerializersCache;
    id<TRCConnectionReachabilityDelegate> _reachabilityDelegate;
}

- (instancetype)initWithBaseUrl:(NSURL *)baseUrl
{
    self = [super init];
    if (self) {
        _baseUrl = baseUrl;
        _operationManager = [[AFHTTPRequestOperationManager alloc] initWithBaseURL:baseUrl];
        _responseSerializersCache = [NSCache new];
        _requestSerializersCache = [NSCache new];
        [self startReachabilityMonitoring];
    }
    return self;
}

- (AFNetworkReachabilityManager *)reachabilityManager
{
    return _operationManager.reachabilityManager;
}

- (void)startReachabilityMonitoring
{
    [self.reachabilityManager startMonitoring];
}

- (void)stopReachabilityMonitoring
{
    [self.reachabilityManager stopMonitoring];
}

#pragma mark - HttpWebServiceConnection protocol

- (void)setReachabilityDelegate:(id<TRCConnectionReachabilityDelegate>)reachabilityDelegate
{
    _reachabilityDelegate = reachabilityDelegate;
}

- (TRCConnectionReachabilityState)reachabilityState
{
    return ReachabilityStateFromAFNetworkingState(_operationManager.reachabilityManager.networkReachabilityStatus);
}

- (NSMutableURLRequest *)requestWithOptions:(id<TRCConnectionRequestCreationOptions>)options error:(NSError **)requestComposingError
{
    NSError *urlComposingError = nil;
    NSURL *url = [self urlFromPath:options.path parameters:options.pathParameters error:&urlComposingError];

    if (urlComposingError) {
        if(requestComposingError) {
            *requestComposingError = urlComposingError;
        }
        return nil;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = options.method;
    NSAssert([request.HTTPMethod length] > 0, @"Incorrect HTTP method ('%@') for request with options: %@", options.method, options);

    id bodyObject = options.body;

    if (!IsBodyAllowedInHttpMethod(options.method)) {
        bodyObject = nil;
    }

    id<AFURLRequestSerialization> serializer = [self requestSerializationForTRCSerializer:options.serialization];
    request = [[serializer requestBySerializingRequest:request withParameters:bodyObject error:requestComposingError] mutableCopy];

    [options.headers enumerateKeysAndObjectsUsingBlock:^(NSString *field, NSString *value, BOOL *stop) {
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
            [request setValue:value forHTTPHeaderField:field];
        }
    }];

    return request;
}

- (id<TRCProgressHandler>)sendRequest:(NSURLRequest *)request withOptions:(id<TRCConnectionRequestSendingOptions>)options completion:(TRCConnectionCompletion)completion
{
    AFHTTPRequestOperation *requestOperation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    requestOperation.responseSerializer = [self responseSerializationForTRCSerializer:options.responseSerialization];
    requestOperation.outputStream = options.outputStream;

    TRCAFNetworkingConnectionProgressHandler *progressHandler = [TRCAFNetworkingConnectionProgressHandler new];
    progressHandler.operation = requestOperation;

    [requestOperation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        if (completion) {
            completion(operation.responseObject, nil, [TRCAFNetworkingConnectionResponseInfo infoWithOperation:operation]);
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        if (error) {
            NSInteger httpCode = operation.response.statusCode;
            error = NSErrorWithDictionaryUnion(error, @{@"TRCHttpStatusCode": @(httpCode)});
        }
        if (completion) {
            completion(operation.responseObject, error, [TRCAFNetworkingConnectionResponseInfo infoWithOperation:operation]);
        }
    }];

    requestOperation.queuePriority = options.queuePriority;

    [_operationManager.operationQueue addOperation:requestOperation];

    return progressHandler;
}

#pragma mark - URL composing

- (NSURL *)urlFromPath:(NSString *)path parameters:(NSDictionary *)parameters error:(NSError **)error
{
    NSURL *result = [self absoluteUrlFromPath:path];

    if ([parameters count] > 0) {
        NSString *query = TRCQueryStringFromParametersWithEncoding(parameters, NSUTF8StringEncoding);
        result = [NSURL URLWithString:[[result absoluteString] stringByAppendingFormat:result.query ? @"&%@" : @"?%@", query]];
    }

    return result;
}

- (NSURL *)absoluteUrlFromPath:(NSString *)path
{
    BOOL isAlreadyAbsolute = [path hasPrefix:@"http://"] || [path hasPrefix:@"https://"];
    if (isAlreadyAbsolute) {
        return [[NSURL alloc] initWithString:path];
    } else {
        return [[NSURL alloc] initWithString:path relativeToURL:self.baseUrl];
    }
}

#pragma mark - Utils

BOOL IsBodyAllowedInHttpMethod(TRCRequestMethod method)
{
    return method == TRCRequestMethodPost || method == TRCRequestMethodPut || method == TRCRequestMethodPatch;
}

NSError *NSErrorWithDictionaryUnion(NSError *error, NSDictionary *dictionary)
{
    NSMutableDictionary *userInfo = [[error userInfo] mutableCopy];
    [userInfo addEntriesFromDictionary:dictionary];
    return [NSError errorWithDomain:error.domain code:error.code userInfo:dictionary];
}

TRCConnectionReachabilityState ReachabilityStateFromAFNetworkingState(AFNetworkReachabilityStatus state)
{
    return (TRCConnectionReachabilityState)state;
}

//-------------------------------------------------------------------------------------------
#pragma mark - Serializers Cache
//-------------------------------------------------------------------------------------------


- (id<AFURLResponseSerialization>)responseSerializationForTRCSerializer:(id<TRCResponseSerializer>)serializer
{
    AFTRCResponseSerializer *result = [_responseSerializersCache objectForKey:serializer];
    if (!result) {
        result = [AFTRCResponseSerializer new];
        result.serializer = serializer;
        [_responseSerializersCache setObject:result forKey:serializer];
    }
    return result;
}

- (id<AFURLRequestSerialization>)requestSerializationForTRCSerializer:(id<TRCRequestSerializer>)serializer
{
    AFTRCRequestSerializer *result = [_requestSerializersCache objectForKey:serializer];
    if (!result) {
        result = [AFTRCRequestSerializer new];
        result.serializer = serializer;
        [_requestSerializersCache setObject:result forKey:serializer];
    }
    return result;
}

@end

@implementation NSError(HttpStatusCode)

- (NSInteger)httpStatusCode
{
    return [self.userInfo[@"TRCHttpStatusCode"] integerValue];
}

@end