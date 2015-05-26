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

#import "ViewController.h"
#import "TyphoonRestClient.h"
#import "RequestToGetIssues.h"
#import "TRCValueTransformerDateISO8601.h"
#import "TRCObjectMapperIssue.h"
#import "RequestToGetIssue.h"
#import "Issue.h"

@interface ViewController ()

@end

@implementation ViewController {
    TyphoonRestClient *_restClient;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self setupRestClient];
    
    [self onGetIssues];
//    [self onGetIssueWithId:@1];
}

- (void)setupRestClient
{
    _restClient = [TyphoonRestClient new];
    
    id<TRCConnection> connection = [[TRCConnectionAFNetworking alloc] initWithBaseUrl:[NSURL URLWithString:@"http://www.redmine.org"]];
    
    //Comment to disable logging
    connection = [[TRCConnectionLogger alloc] initWithConnection:connection];
    
    _restClient.connection = connection;
    
    [_restClient registerValueTransformer:[TRCValueTransformerDateISO8601 new] forTag:@"{date_iso8601}"];
    [_restClient registerObjectMapper:[TRCObjectMapperIssue new] forTag:@"{issue}"];
}

- (void)onGetIssues
{
    RequestToGetIssues *request = [RequestToGetIssues new];
    request.range = NSMakeRange(10, 15);
    request.projectId = @1;
    
    [_restClient sendRequest:request completion:^(NSArray *result, NSError *error) {
        NSLog(@"Result: %@. Error: %@", result, error?:@"NO");
    }];
}

- (void)onGetIssueWithId:(NSNumber *)issueId
{
    RequestToGetIssue *request = [[RequestToGetIssue alloc] initWithIssueId:issueId];
    
    [_restClient sendRequest:request completion:^(Issue *result, NSError *error) {
        NSLog(@"Issue: %@, Error: %@", result, error?:@"NO");
    }];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
