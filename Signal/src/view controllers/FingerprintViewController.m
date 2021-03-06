//
//  FingerprintViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 02/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "FingerprintViewController.h"

#import "Cryptography.h"
#import <AxolotlKit/NSData+keyVersionByte.h>
#import <25519/Curve25519.h>
#import "NSData+hexString.h"
#import "DJWActionSheet+OWS.h"
#import "TSStorageManager.h"
#import "TSStorageManager+IdentityKeyStore.h"
#import "TSStorageManager+SessionStore.h"
#import "PresentIdentityQRCodeViewController.h"
#import "ScanIdentityBarcodeViewController.h"
#import "SignalsNavigationController.h"
#include "NSData+Base64.h"

#import "TSFingerprintGenerator.h"

@interface FingerprintViewController ()
@property TSContactThread *thread;
@property (nonatomic) BOOL isPresentingDialog;
@end

static NSString* const kPresentIdentityQRCodeViewSegue = @"PresentIdentityQRCodeViewSegue";
static NSString* const kScanIdentityBarcodeViewSegue = @"ScanIdentityBarcodeViewSegue";

@implementation FingerprintViewController

- (void)configWithThread:(TSThread *)thread{
    self.thread = (TSContactThread*)thread;
}


- (void)viewDidLoad {
    [super viewDidLoad];
    [self.view setAlpha:0];
    UITapGestureRecognizer *tapToShowFingerprint = [[UITapGestureRecognizer alloc]  initWithTarget:self action:@selector(showFingerprint)];
    tapToShowFingerprint.numberOfTapsRequired = 1;

    UITapGestureRecognizer *tapToScanFingerprint = [[UITapGestureRecognizer alloc]  initWithTarget:self action:@selector(scanFingerprint)];
    tapToScanFingerprint.numberOfTapsRequired = 1;
    
    UILongPressGestureRecognizer *longpressToResetSession = [[UILongPressGestureRecognizer alloc]  initWithTarget:self action:@selector(shredAndDelete:)];
    longpressToResetSession.minimumPressDuration = 1.0;
    [self.view addGestureRecognizer:longpressToResetSession];
    [self.view addGestureRecognizer:tapToShowFingerprint];
    [_theirFingerprintView addGestureRecognizer:tapToScanFingerprint];

}

- (void)viewWillAppear:(BOOL)animated
{
    
    [self setTheirKeyInformation];
    
    NSData *myPublicKey = [[TSStorageManager sharedManager] identityKeyPair].publicKey;
    self.userFingerprintLabel.text = [TSFingerprintGenerator getFingerprintForDisplay:myPublicKey];
    
    [UIView animateWithDuration:0.6 delay:0. options:UIViewAnimationOptionCurveEaseInOut animations:^{
        [self.view setAlpha:1];
    } completion:nil];
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (void)setTheirKeyInformation {
    self.contactFingerprintTitleLabel.text = self.thread.name;
    NSData *identityKey = [[TSStorageManager sharedManager] identityKeyForRecipientId:self.thread.contactIdentifier];
    self.contactFingerprintLabel.text = [TSFingerprintGenerator getFingerprintForDisplay:identityKey];
    
    if([self.contactFingerprintLabel.text length] == 0) {
        // no fingerprint, hide this view
        _presentationLabel.hidden = YES;
        _theirFingerprintView.hidden = YES;
    }
    
}

-(NSData*) getMyPublicIdentityKey {
    return [[TSStorageManager sharedManager] identityKeyPair].publicKey;
}

-(NSData*) getTheirPublicIdentityKey {
    return [[TSStorageManager sharedManager] identityKeyForRecipientId:self.thread.contactIdentifier];
    
}


#pragma mark - Action
- (IBAction)closeButtonAction:(id)sender
{
    [UIView animateWithDuration:0.6 delay:0. options:UIViewAnimationOptionCurveEaseInOut animations:^{
        [self.view setAlpha:0];
    } completion:^(BOOL succeeded){
        [self dismissViewControllerAnimated:YES completion:nil];
    }];
    
}


- (IBAction)shredAndDelete:(id)sender
{
    if(!_isPresentingDialog) {
        _isPresentingDialog = YES;
        [DJWActionSheet showInView:self.view withTitle:@"Are you sure wou want to shred the following? This action is irreversible."
                 cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@[@"Shred all keying material"]
                          tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                              _isPresentingDialog = NO;
                              if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                                  NSLog(@"User Cancelled");
                              } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex) {
                                  NSLog(@"Destructive button tapped");
                              }else {
                                  switch (tappedButtonIndex) {
                                      case 0:
                                          [self shredKeyingMaterial];
                                          break;
                                      default:
                                          break;
                                  }
                              }
                          }];
    }
}


-(void) showFingerprint {
    [self performSegueWithIdentifier:kPresentIdentityQRCodeViewSegue sender:self];
}


-(void) scanFingerprint {
    [self performSegueWithIdentifier:kScanIdentityBarcodeViewSegue sender:self];
}


- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if([[segue identifier] isEqualToString:kPresentIdentityQRCodeViewSegue]){
        [segue.destinationViewController setIdentityKey:[[self getMyPublicIdentityKey] prependKeyType]];
    }
    else if([[segue identifier] isEqualToString:kScanIdentityBarcodeViewSegue]){
        [segue.destinationViewController setIdentityKey:[[self getTheirPublicIdentityKey] prependKeyType]];
    }
    
}


- (IBAction)unwindToIdentityKeyWasVerified:(UIStoryboardSegue *)segue{
    // Can later be used to mark identity key as verified if we want step above TOFU in UX
}


- (IBAction)unwindCancel:(UIStoryboardSegue *)segue{
    NSLog(@"action cancelled");
    // Can later be used to mark identity key as verified if we want step above TOFU in UX
}

#pragma mark - Shredding & Deleting

- (void)shredKeyingMaterial {
    [[TSStorageManager sharedManager] removeIdentityKeyForRecipient:self.thread.contactIdentifier];
    [[TSStorageManager sharedManager] deleteAllSessionsForContact:self.thread.contactIdentifier];
    [self setTheirKeyInformation];
}

- (void)shredDiscussionsWithContact {
    UINavigationController *nVC = (UINavigationController*)self.presentingViewController;
    for (UIViewController __strong *vc in nVC.viewControllers) {
        if ([vc isKindOfClass:[MessagesViewController class]]) {
            vc = nil;
        }
    }

    [self.thread remove]; // this removes the thread and all it's discussion (YapDatabaseRelationships)
    __block SignalsNavigationController *vc = (SignalsNavigationController*)[self presentingViewController];
    [vc dismissViewControllerAnimated:YES completion:^{
        [vc popToRootViewControllerAnimated:YES];
    }];
}

@end
