//
//  PNDataManager.h
// 
//
//  Created by moonlight on 1/20/13.
//
//


#import "PNDataManager.h"
#import "PNPresenceEvent+Protected.h"
#import "PNMessage+Protected.h"
#import "PNChannel+Protected.h"


#pragma mark Static

// Stores reference on shared data manager instance
static PNDataManager *_sharedInstance = nil;


#pragma mark - Private interface methods

@interface PNDataManager ()


#pragma mark - Properties

@property (nonatomic, strong) PNConfiguration *configuration;

// Stores reference on list of channels on which client is subscribed
@property (nonatomic, strong) NSArray *subscribedChannelsList;

// Stores reference on dictionary which stores messages for each of channels
@property (nonatomic, strong) NSMutableDictionary *messages;


@end


#pragma mark - Public interface methods

@implementation PNDataManager


#pragma mark - Class methods

+ (PNDataManager *)sharedInstance {

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        _sharedInstance = [PNDataManager new];
    });


    return _sharedInstance;
}


#pragma mark - Instance methods

- (id)init {

    // Check whether initialization successful or not
    if((self = [super init])) {

        self.messages = [NSMutableDictionary dictionary];
        self.configuration = [PNConfiguration defaultConfiguration];
        self.subscribedChannelsList = [NSMutableArray array];

        PNDataManager *weakSelf = self;
        [[PNObservationCenter defaultCenter] addClientChannelSubscriptionObserver:self
                                                                withCallbackBlock:^(NSArray *channels,
                                                                                    BOOL subscribed,
                                                                                    PNError *subscriptionError) {

                    if (subscribed) {

                        NSArray *unsortedList = [PubNub subscribedChannels];
                        NSSortDescriptor *nameSorting = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES];
                        self.subscribedChannelsList = [unsortedList sortedArrayUsingDescriptors:@[nameSorting]];
                    }
                }];

        [[PNObservationCenter defaultCenter] addClientChannelUnsubscriptionObserver:self
                                                                  withCallbackBlock:^(NSArray *channels,
                                                                                      PNError *error) {
                  NSArray *unsortedList = [PubNub subscribedChannels];
                  NSSortDescriptor *nameSorting = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES];
                  self.subscribedChannelsList = [unsortedList sortedArrayUsingDescriptors:@[nameSorting]];
              }];

        [[PNObservationCenter defaultCenter] addMessageReceiveObserver:self
                                                             withBlock:^(PNMessage *message) {

                 NSDateFormatter *dateFormatter = [NSDateFormatter new];
                 dateFormatter.dateFormat = @"HH:mm:ss MM/dd/yy";

                 PNChannel *channel = message.channel;
                 NSString *messages = [weakSelf.messages valueForKey:channel.name];
                 if (messages == nil) {

                     messages = @"";
                 }
                 messages = [messages stringByAppendingFormat:@"<%@> %@\n",
                                 [dateFormatter stringFromDate:message.receiveDate],
                                 message.message];
                 [weakSelf.messages setValue:messages forKey:channel.name];


                 weakSelf.currentChannelChat = [weakSelf.messages valueForKey:weakSelf.currentChannel.name];
             }];

        [[PNObservationCenter defaultCenter] addPresenceEventObserver:self
                                                            withBlock:^(PNPresenceEvent *event) {

                NSDateFormatter *dateFormatter = [NSDateFormatter new];
                dateFormatter.dateFormat = @"HH:mm:ss MM/dd/yy";
                NSString *eventType = @"joined";
                if (event.type == PNPresenceEventLeave) {

                    eventType = @"leaved";
                }
                else if (event.type == PNPresenceEventTimeout) {

                    eventType = @"timeout";
                }
                PNChannel *channel = event.channel;
                NSString *eventMessage = [weakSelf.messages valueForKey:channel.name];
                if (eventMessage == nil) {

                    eventMessage = @"";
                }
                eventMessage = [eventMessage stringByAppendingFormat:@"<%@> %@ '%@'\n",
                                                                     [dateFormatter stringFromDate:event.date],
                                                                     event.uuid,
                                                                     eventType];
                [weakSelf.messages setValue:eventMessage forKey:channel.name];


                weakSelf.currentChannelChat = [weakSelf.messages valueForKey:weakSelf.currentChannel.name];
            }];
}


    return self;
}

- (void)updateSSLOption:(BOOL)shouldEnableSSL {

    // This is very hard construction for configuration creation, better
    // use PNDefaultConfiguration.h header file and [PNConfiguration defaultConfiguration]
    PNConfiguration *configuration = [PNConfiguration configurationForOrigin:self.configuration.origin
                                                                  publishKey:self.configuration.publishKey
                                                                subscribeKey:self.configuration.subscriptionKey
                                                                   secretKey:self.configuration.secretKey
                                                                   cipherKey:self.configuration.cipherKey
                                                         useSecureConnection:shouldEnableSSL
                                                         shouldAutoReconnect:self.configuration.shouldAutoReconnectClient
                                            shouldReduceSecurityLevelOnError:self.configuration.shouldReduceSecurityLevelOnError
                                        canIgnoreSecureConnectionRequirement:self.configuration.canIgnoreSecureConnectionRequirement];

    self.configuration = configuration;
}

- (void)setCurrentChannel:(PNChannel *)currentChannel {

    [self willChangeValueForKey:@"currentChannel"];
    _currentChannel = currentChannel;
    [self didChangeValueForKey:@"currentChannel"];

    if (_currentChannel == nil) {

        self.currentChannelChat = nil;
    }
    else {

        self.currentChannelChat = [self.messages valueForKey:self.currentChannel.name];
    }

    // Checking whether participants list not updated
    // for a while and send request to get participants list
    // (updated date older than 30 seconds will mean that
    // list should be updated)
    BOOL shouldUpdate = NO;
    if(_currentChannel.presenceUpdateDate != nil) {

        if ([[NSDate date] timeIntervalSinceDate:_currentChannel.presenceUpdateDate] > 5.0f) {

            shouldUpdate = YES;
        }
    } else if ([_currentChannel presenceObserver] != nil) {

        shouldUpdate = YES;
    }


    if (shouldUpdate) {

        [PubNub requestParticipantsListForChannel:_currentChannel];
    }
}


#pragma mark -

@end