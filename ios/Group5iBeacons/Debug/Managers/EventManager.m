//
    //  EventManager.m
//  iBeacon-Geo-Demo
//
//  Created by Nemanja Joksovic on 4/26/14.
//  Copyright (c) 2014 R/GA. All rights reserved.
//

#import "EventManager.h"

#import "Polygon.h"
#import "Beacon.h"
#import "Transmission.h"

#import "Global.h"
#import "PolygonManager.h"
#import "LocationManager.h"

@interface EventManager ()

@property (strong, nonatomic) CLBeaconRegion *beaconRegion;
@property (strong, nonatomic) CLLocationManager *locationManager;

@property (strong, nonatomic) NSMutableSet *delegates;

@property (strong, nonatomic) Event *lastEvent;

- (void)performExecution:(BOOL)coverage
           transmissions:(NSArray *)transmissions;

@end

@implementation EventManager

+ (instancetype)shared
{
    static dispatch_once_t once;
    static EventManager *shared;

    dispatch_once(&once, ^ {
        shared = [[self alloc] init];
    });
    
    return shared;
}

- (instancetype)init
{
    if (self = [super init]) {
        _delegates = [NSMutableSet set];
        
        // Set beacons Proximity UUID
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:kBeaconProximityUUID];
        _beaconRegion = [[CLBeaconRegion alloc] initWithProximityUUID:uuid identifier:kBeaconRegionIdentifier];
        _beaconRegion.notifyEntryStateOnDisplay = YES;

        // Initialize sand start Location Manager
        _locationManager = [[CLLocationManager alloc] init];
        [_locationManager setDelegate:self];
        [_locationManager startMonitoringForRegion:_beaconRegion];
    }
    
    return self;
}

- (void)startListening
{
    [_locationManager startRangingBeaconsInRegion:_beaconRegion];
}

- (void)stopListening
{
    [_locationManager stopRangingBeaconsInRegion:_beaconRegion];
}

- (void)addDelegate:(id<EventManagerDelegate>)delegate
{
    [_delegates addObject:delegate];
}

- (void)removeDelegate:(id<EventManagerDelegate>)delegate
{
    [_delegates removeObject:delegate];
}

- (void)performExecution:(BOOL)coverage
           transmissions:(NSArray *)transmissions
{
    if (!transmissions || [transmissions count] == 0) {
        [self forwardEvent:[[Event alloc] initWithType:kUnknown]];
    }
    else {
        [LocationManager determine:transmissions
                           success:^(Location *location) {
                               if (location) {
                                   NSSet *polygons = [[PolygonManager shared] allPolygons];

                                   for (Polygon *polygon in polygons) {
                                       if ([polygon contains:location]) {
                                           [self forwardEvent:[[PolygonEvent alloc] initWithType:kEnterPolygon
                                                                                         polygon:polygon]];
                                           return;
                                       }
                                   }
                               }
                              
                               if (_lastEvent && _lastEvent.type == kEnterPolygon) {
                                   PolygonEvent *polygonEvent = (PolygonEvent *)_lastEvent;
                                   [self forwardEvent:[[PolygonEvent alloc] initWithType:kExitPolygon
                                                                                 polygon:polygonEvent.polygon]];
                               }
                               else {
                                   [self forwardEvent:[[Event alloc] initWithType:kUnknown]];
                               }
                           }
                           failure:^(NSError *error) {
                               [self forwardEvent:[[Event alloc] initWithType:kUnknown]];
                           }
         ];
    }
}

- (void)forwardEvent:(Event *)event
{
    if (!_lastEvent || ![_lastEvent isEqualToEvent:event]) {
        _lastEvent = event;

        for (id<EventManagerDelegate> delegete in _delegates) {
            if (delegete && [delegete respondsToSelector:@selector(onEvent:)]) {
                [delegete onEvent:event];
            }
        }
    }
}

#pragma mark -
#pragma mark LocationManager delegate methods

- (void)locationManager:(CLLocationManager *)manager
        didRangeBeacons:(NSArray *)beacons
               inRegion:(CLBeaconRegion *)region
{
    NSMutableArray *transmissions = [[NSMutableArray alloc] init];
    
    for (CLBeacon *beacon in beacons) {
        Transmission *transmission = [Transmission transmissionWithCLBeacon:beacon];
        
        if (transmission) {
            [transmissions addObject:transmission];
        }
    }
        
    [self performExecution:YES
             transmissions:transmissions];

    for (id<EventManagerDelegate> delegete in _delegates) {
        if (delegete && [delegete respondsToSelector:@selector(onTransmissions:)]) {
            [delegete onTransmissions:transmissions];
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager
      didDetermineState:(CLRegionState)state
              forRegion:(CLRegion *)region
{
    if (state == CLRegionStateInside) {
        NSLog(@"Monitoring: INSIDE");
        [self startListening];
        [self performExecution:YES transmissions:nil];
    }
    else if (state == CLRegionStateOutside) {
        NSLog(@"Monitoring: OUTSIDE");
        [self stopListening];
        [self performExecution:NO transmissions:nil];
    }
    else {
        NSLog(@"Monitoring: OTHER");
    }
}

@end
