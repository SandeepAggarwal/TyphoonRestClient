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

#import "TRCSchemeFactory.h"
#import "TRCSchema.h"
#import "TRCRequest.h"
#import "TRCErrorHandler.h"
#import "TRCObjectMapper.h"
#import "TRCInfrastructure.h"
#import "TyphoonRestClient.h"
#import "TRCSchemaData.h"
#import "TRCConvertersRegistry.h"

@interface TyphoonRestClient (Private) <TRCConvertersRegistry, TRCSchemaDataProvider>

@end

@implementation TRCSchemeFactory
{
    NSMutableDictionary *_formats;

    NSString *_moduleName;

    NSSet<NSString *> *_cachedFilenames;
    BOOL _shouldRecacheFilenames;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _formats = [NSMutableDictionary new];

        _moduleName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
        _moduleName = [_moduleName stringByAppendingString:@"."];
    }
    return self;
}

//-------------------------------------------------------------------------------------------
#pragma mark - Schemes
//-------------------------------------------------------------------------------------------

- (TRCSchema *)schemeForErrorHandler:(id<TRCErrorHandler>)parser
{
    return [self schemeForObject:parser nameSelector:@selector(errorValidationSchemaName) suffix:@"response"
                       isRequest:NO];
}

- (TRCSchema *)schemeForPathParametersWithRequest:(id<TRCRequest>)request
{
    return [self schemeForObject:request nameSelector:@selector(pathParametersValidationSchemaName) suffix:@"path"
                       isRequest:YES];
}

- (TRCSchema *)schemeForRequest:(id<TRCRequest>)request
{
    return [self schemeForObject:request nameSelector:@selector(requestBodyValidationSchemaName) suffix:@"request"
                       isRequest:YES];
}

- (TRCSchema *)schemeForResponseWithRequest:(id<TRCRequest>)request
{
    return [self schemeForObject:request nameSelector:@selector(responseBodyValidationSchemaName) suffix:@"response"
                       isRequest:NO];
}

- (id<TRCSchemaData>)requestSchemaDataForMapper:(id<TRCObjectMapper>)mapper
{
    return [self schemeForObject:mapper nameSelector:@selector(requestValidationSchemaName) suffix:@[@"request", @""]
                       isRequest:YES].data;
}

- (id<TRCSchemaData>)responseSchemaDataForMapper:(id<TRCObjectMapper>)mapper
{
    return [self schemeForObject:mapper nameSelector:@selector(responseValidationSchemaName) suffix:@[@"response", @""]
                       isRequest:NO].data;
}

- (TRCSchema *)schemeForObject:(id)object nameSelector:(SEL)sel suffix:(id)suffix isRequest:(BOOL)request
{
    NSString *filePath = nil;
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];

    if ([object respondsToSelector:sel]) {
        NSString *(*impl)(id, SEL) = (NSString*(*)(id, SEL))[object methodForSelector:sel];
        NSString *fileName = impl(object, sel);
        filePath = [bundle pathForResource:fileName ofType:nil];
        //Used for UnitTests only
        if (fileName && !filePath) {
            return [self schemeForName:fileName isRequest:request];
        }
    }

    if (!filePath) {
        NSString *className = NSStringFromClass([object class]);

        if (_moduleName && [className hasPrefix:_moduleName]) {
            className = [className stringByReplacingOccurrencesOfString:_moduleName withString:@""];
        }

        if ([suffix isKindOfClass:[NSArray class]]) {
            for (NSString *suffixString in suffix) {
                filePath = [self pathForSchemeWithClassName:className suffix:suffixString];
                if (filePath) {
                    break;
                }
            }
        } else if ([suffix isKindOfClass:[NSString class]]) {
            filePath = [self pathForSchemeWithClassName:className suffix:suffix];
        }
    }

    if (filePath) {
        id<TRCSchemaData>schemaData = [self schemeDataFromFilePath:filePath isRequest:request];
        return [self schemeFromData:schemaData withName:[filePath lastPathComponent]];
    } else {
        return nil;
    }
}

- (NSString *)pathForSchemeWithClassName:(NSString *)className suffix:(NSString *)suffix
{
    NSString *fileName = suffix.length > 0 ? [NSString stringWithFormat:@"%@.%@", className, suffix] : className;

    NSArray<NSString *> *formats = [_formats allKeys];
    for (NSString *formatExtension in formats) {
        NSString *fileNameToTest = [fileName stringByAppendingPathExtension:formatExtension];
        if ([self isSchemaExistsWithFilename:fileNameToTest]) {
            NSBundle *bundle = [NSBundle bundleForClass:[self class]];
            return [[bundle bundlePath] stringByAppendingPathComponent:fileNameToTest];
        }
    }
    return nil;
}

- (BOOL)isSchemaExistsWithFilename:(NSString *)filename
{
    return [[self cachedFilenames] containsObject:filename];
}

- (id<TRCSchemaData>)schemeDataFromFilePath:(NSString *)filePath isRequest:(BOOL)isRequest
{
    id<TRCSchemaData> result = nil;
    id<TRCSchemaFormat> format = [self formatForFileExtension:[filePath pathExtension]];
    if (format) {
        NSData *data = [[NSData alloc] initWithContentsOfFile:filePath];
        if (data) {
            NSError *error = nil;
            if (isRequest) {
                result = [format requestSchemaDataFromData:data dataProvider:self.owner error:&error];
            } else {
                result = [format responseSchemaDataFromData:data dataProvider:self.owner error:&error];
            }

            if (error) {
                NSLog(@"Error: Can't load scheme at path: %@. Error: %@", filePath, error);
            }
        }
    }
    return result;
}

- (TRCSchema *)schemeFromData:(id<TRCSchemaData>)data withName:(NSString *)name
{
    TRCSchema *schema = [TRCSchema schemaWithData:data name:name];
    schema.converterRegistry = self.owner;
    return schema;
}

/** Used for unit tests only */
- (TRCSchema *)schemeForName:(NSString *)schemeName isRequest:(BOOL)isRequest
{
    return nil;
}

//-------------------------------------------------------------------------------------------
#pragma mark - Registry
//-------------------------------------------------------------------------------------------

- (void)registerSchemeFormat:(id<TRCSchemaFormat>)schemeFormat forFileExtension:(NSString *)extension
{
    NSParameterAssert(extension);
    if (schemeFormat) {
        _formats[extension] = schemeFormat;
    } else {
        [_formats removeObjectForKey:extension];
    }

    _shouldRecacheFilenames = YES;
}

- (id<TRCSchemaFormat>)formatForFileExtension:(NSString *)extension
{
    if (extension) {
        return _formats[extension];
    } else {
        return nil;
    }
}

//-------------------------------------------------------------------------------------------
#pragma mark - Filename cache
//-------------------------------------------------------------------------------------------

- (NSSet<NSString *> *)cachedFilenames
{
    if (!_cachedFilenames || _shouldRecacheFilenames) {
        NSMutableSet *filenames = [NSMutableSet new];

        NSBundle *bundle = [NSBundle bundleForClass:[self class]];

        NSArray *allFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[bundle bundlePath] error:nil];

        NSSet *supportedExtensions = [NSSet setWithArray:[_formats allKeys]];

        for (NSString *file in allFiles) {
            if ([supportedExtensions containsObject:[file pathExtension]]) {
                [filenames addObject:file];
            }
        }

        _cachedFilenames = filenames;
        _shouldRecacheFilenames = NO;
    }

    return _cachedFilenames;
}

@end
