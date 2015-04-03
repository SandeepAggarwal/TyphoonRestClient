////////////////////////////////////////////////////////////////////////////////
//
//  AppsQuick.ly
//  Copyright 2015 AppsQuick.ly
//  All Rights Reserved.
//
//  NOTICE: This software is the proprietary information of AppsQuick.ly
//  Use is subject to license terms.
//
////////////////////////////////////////////////////////////////////////////////




#import <Foundation/Foundation.h>
#import "TRCRequest.h"
#import "TyphoonRestClient.h"

@protocol TRCConvertersRegistry;
@class TRCSchema;

/** TRCConverter converts whole responses or requests using TRCValueTransformer from registry */

@interface TRCConverter : NSObject

@property (nonatomic, strong) id<TRCConvertersRegistry> registry;
@property (nonatomic) TRCValidationOptions options;

#pragma mark - Initialization

- (instancetype)initWithSchema:(TRCSchema *)schema;

#pragma mark - Instance methods

- (id)convertResponseValue:(id)value error:(NSError **)error;

- (id)convertRequestValue:(id)value error:(NSError **)error;

#pragma mark - Errors

- (NSError *)conversionError;

- (NSOrderedSet *)conversionErrorSet;

@end