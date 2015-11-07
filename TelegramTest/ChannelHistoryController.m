//
//  ChannelHistoryController.m
//  Telegram
//
//  Created by keepcoder on 08.09.15.
//  Copyright (c) 2015 keepcoder. All rights reserved.
//

#import "ChannelHistoryController.h"
#import "MessageTableItem.h"
#import "TGChannelsPolling.h"

#import "ChannelImportantFilter.h"
#import "ChannelFilter.h"
#import "MegagroupChatFilter.h"
@interface ChannelHistoryController () <TGChannelPollingDelegate>
@property (nonatomic,assign) BOOL pollingIsStarted;
@end

@implementation ChannelHistoryController


static TGChannelsPolling *channelPolling;

-(id)initWithController:(id<MessagesDelegate>)controller historyFilter:(Class)historyFilter {
    if(self = [super initWithController:controller historyFilter:historyFilter]) {
        
        
        [self.queue dispatchOnQueue:^{
            
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                channelPolling = [[TGChannelsPolling alloc] initWithDelegate:self withUpdatesLimit:50];
                
            });
            
            [channelPolling setDelegate:self];
            [channelPolling setCurrentConversation:controller.conversation];
            
            _pollingIsStarted = NO;
            
        } synchronous:YES];
        
    }
    
    return self;
}


-(void)request:(BOOL)next anotherSource:(BOOL)anotherSource sync:(BOOL)sync selectHandler:(selectHandler)selectHandler {
    
    [self.queue dispatchOnQueue:^{
        
        
         HistoryFilter *filter = [self filterWithNext:next];
        
        if([filter checkState:ChatHistoryStateFull next:next] || self.isProccessing) {
            return;
        }
        
        self.proccessing = YES;
        
       
        [filter request:next callback:^(NSArray *result, ChatHistoryState state) {
            
            if([filter checkState:ChatHistoryStateLocal next:next] && result.count == 0) {
                
                [filter proccessResponse:[self.controller messageTableItemsFromMessages:result] state:state next:next];
                
                self.proccessing = NO;
                
                [self request:next anotherSource:anotherSource sync:sync selectHandler:selectHandler];
                
                return ;
            }
            
            NSArray *converted = [filter proccessResponse:[self.controller messageTableItemsFromMessages:result] state:state next:next];
            
            
            MessageTableItem *service = [[filter selectAllItems] lastObject];
            
            if(service.message.action && [service.message.action isKindOfClass:[TL_messageActionChannelMigrateFrom class]] && [filter checkState:ChatHistoryStateFull next:next]) {
                
                TLChat *chat = [[ChatsManager sharedManager] find:service.message.action.chat_id];
                
                HistoryFilter *filter = [[MegagroupChatFilter alloc] initWithController:self conversation:chat.dialog];
                
                [filter setState:ChatHistoryStateFull next:NO];
                
                [self addFilter:filter];
                
            }
            
            [self performCallback:selectHandler result:converted range:NSMakeRange(0, converted.count)];
            
            [channelPolling checkInvalidatedMessages:converted important:[self.filter isKindOfClass:[ChannelImportantFilter class]]];
            
            
            
            
        }];
        
    } synchronous:sync];
    
}



-(void)pollingDidSaidTooLongWithHole:(TGMessageHole *)hole {
    
    if(hole != nil) {
        
        [self.filter setHole:hole withNext:NO];
        
        [self.filter setState:ChatHistoryStateRemote next:NO];
        
        [self.filter request:NO callback:^(id response, ChatHistoryState state) {
            
            NSArray *converted = [self.filter proccessResponse:response state:state next:NO];
            
            [ASQueue dispatchOnMainQueue:^{
                
                [self.controller receivedMessageList:converted inRange:NSMakeRange(0, converted.count) itsSelf:NO];
                
            }];
            
        }];
        
    }
    
    
    
}



-(void)loadAroundMessagesWithMessage:(MessageTableItem *)item limit:(int)limit selectHandler:(selectHandler)selectHandler {
    
    
    [self.queue dispatchOnQueue:^{
        
        [self addItemWithoutSavingState:item];
    
        [[Storage manager] addHolesAroundMessage:item.message];
        
        if(self.filter.class == [ChannelFilter class]) {
            [(ChannelFilter *)self.filter fillGroupHoles:@[item.message] bottom:NO];
        }
        
        [[Storage manager] insertMessage:item.message];
        
        NSMutableArray *prevResult = [NSMutableArray array];
        NSMutableArray *nextResult = [NSMutableArray array];
        
        self.proccessing = YES;
        [self loadAroundMessagesWithSelectHandler:selectHandler limit:(int)limit prevResult:prevResult nextResult:nextResult];
        
      
    } synchronous:YES];
    
    
}

-(void)loadAroundMessagesWithSelectHandler:(selectHandler)selectHandler limit:(int)limit prevResult:(NSMutableArray *)prevResult nextResult:(NSMutableArray *)nextResult {
    
    
    BOOL nextLoaded = nextResult.count >= limit/2 || self.nextState == ChatHistoryStateFull;
    BOOL prevLoaded = prevResult.count >= limit/2 || self.prevState == ChatHistoryStateFull;
    
    
    if(nextLoaded && prevLoaded) {
        
        NSArray *result = [self.filter selectAllItems];
        
        [self performCallback:selectHandler result:result range:NSMakeRange(0, result.count)];

        [channelPolling checkInvalidatedMessages:result important:[self.filter isKindOfClass:[ChannelImportantFilter class]]];
        
        self.proccessing = NO;
        return;
    }
    
    BOOL nextRequest = prevLoaded;
    
    
    [self.filter request:nextRequest callback:^(NSArray *result, ChatHistoryState state) {
        
        NSArray *converted = [self.filter proccessResponse:[self.controller messageTableItemsFromMessages:result] state:state next:nextRequest];
        
        if(nextRequest) {
            [nextResult addObjectsFromArray:converted];
        } else {
            [prevResult addObjectsFromArray:converted];
        }
        
    
        [self loadAroundMessagesWithSelectHandler:selectHandler limit:(int)limit prevResult:prevResult nextResult:nextResult];
        
    }];
    
}



-(void)pollingReceivedUpdates:(id)updates endPts:(int)pts {
    
}



-(void)startChannelPolling {
    
    if(!channelPolling.isActive) {
        [channelPolling start];
        _pollingIsStarted = YES;
    }
}

-(void)startChannelPollingIfAlreadyStoped {
    if(!channelPolling.isActive && _pollingIsStarted) {
        [channelPolling start];
    }
}

-(void)stopChannelPolling {
    [channelPolling stop];
}




-(void)drop:(BOOL)dropMemory {
    
    [super drop:YES];
}

-(void)dealloc {
    [channelPolling stop];
}


@end
