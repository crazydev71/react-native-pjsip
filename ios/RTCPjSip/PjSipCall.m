#import <React/RCTBridge.h>
#import <React/RCTEventDispatcher.h>

#import "PjSipCall.h"
#import "PjSipUtil.h"

@implementation PjSipCall

+ (instancetype)itemConfig:(int)id {
    return [[self alloc] initWithId:id];
}

- (id)initWithId:(int)id {
    self = [super init];
    
    if (self) {
        self.id = id;
        self.isHeld = false;
        self.isMuted = false;
    }
    
    return self;
}

#pragma mark - Actions

- (void)hangup {
    pj_status_t status = pjsua_call_hangup(self.id, 0, NULL, NULL);
    
    if (status != PJ_SUCCESS) {
        NSLog(@"Failed to hangup a call (%d)", status);
    } else {
        NSLog(@"Hangup success");
    }
}

- (void)decline {
    pjsua_call_hangup(self.id, PJSIP_SC_DECLINE, NULL, NULL);
}


- (void)answer {
    // TODO: Put on hold previous call
    
    pjsua_msg_data msgData;
    pjsua_msg_data_init(&msgData);
    pjsua_call_setting  callOpt;
    pjsua_call_setting_default(&callOpt);
    pjsua_call_answer2(self.id, &callOpt, 200, NULL, &msgData);
}

- (void)hold {
    if (self.isHeld) {
        return;
    }
    
    self.isHeld = true;
    
    // TODO: May be check whether call is answered before putting on hold
    pjsua_call_set_hold(self.id, NULL);
}

- (void)unhold {
    if (!self.isHeld) {
        return;
    }
    
    self.isHeld = false;
    
    // TODO: May be check whether call is answered before releasing from hold
    pjsua_call_reinvite(self.id, PJSUA_CALL_UNHOLD, NULL);
}

- (void)mute {
    pjsua_call_info info;
    pjsua_call_get_info(self.id, &info);
    
    pjsua_conf_adjust_rx_level(info.conf_slot, 0);
    
    self.isMuted = true;
}

- (void)unmute {
    pjsua_call_info info;
    pjsua_call_get_info(self.id, &info);
    
    pjsua_conf_adjust_rx_level(info.conf_slot, 1);
    
    self.isMuted = false;
}

- (void)xfer:(NSString*) destination {
    pj_str_t value = pj_str((char *) [destination UTF8String]);
    pjsua_call_xfer(self.id, &value, NULL);
}

- (void)xferReplaces:(int) destinationCallId {
    pjsua_call_xfer_replaces(self.id, destinationCallId, 0, NULL);
}

- (void)redirect:(NSString*) destination {
    pjsua_msg_data msgData;
    pjsip_generic_string_hdr my_hdr;
    pj_str_t hname = pj_str("Contact");
    pj_str_t hvalue = pj_str((char *) [destination UTF8String]);
    pjsua_msg_data_init(&msgData);
    pjsip_generic_string_hdr_init2(&my_hdr, &hname, &hvalue);
    pj_list_push_back(&msgData.hdr_list, &my_hdr);

    pjsua_call_setting callOpt;
    pjsua_call_setting_default(&callOpt);
    pjsua_call_answer2(self.id, &callOpt, PJSIP_SC_MOVED_TEMPORARILY, NULL, &msgData);
}

- (void)dtmf:(NSString*) digits {
    // TODO: Fallback for "The RFC 2833 payload format did not work".
    
    pj_str_t value = pj_str((char *) [digits UTF8String]);
    pjsua_call_dial_dtmf(self.id, &value);
}

#pragma mark - Callback methods

- (void)onStateChanged:(pjsua_call_info)info {
    // TODO ?
}

/**
 * The action may connect the call to sound device, to file, or
 * to loop the call.
 */
- (void)onMediaStateChanged:(pjsua_call_info)info {
   
    for (unsigned mi=0; mi < info.media_cnt; ++mi) {
        switch (info.media[mi].type) {
//            case PJMEDIA_TYPE_AUDIO:
//                on_call_audio_state(&call_info, mi, &has_error);
//                break;
            case PJMEDIA_TYPE_VIDEO:
                
                NSLog(@"Foudn video device id %d %d", info.media[mi].stream.vid.win_in, info.media[mi].stream.vid.cap_dev);

                // on_call_video_state(&call_info, mi, &has_error);
                break;
            default:
                /* Make gcc happy about enum not handled by switch/case */
                break;
        }
    }
    
    // TODO: Description why this needed
    
    
    
    pjsua_call_media_status status = info.media_status;
    
    if (status == PJSUA_CALL_MEDIA_ACTIVE || status == PJSUA_CALL_MEDIA_REMOTE_HOLD) {
        pjsua_conf_connect(info.conf_slot, 0);
        pjsua_conf_connect(0, info.conf_slot);
    }
}

#pragma mark - Extra

- (NSDictionary *)toJsonDictionary:(bool) isSpeaker {
    pjsua_call_info info;
    pjsua_call_get_info(self.id, &info);

    // -----
    int connectDuration = -1;
    
    if (info.state == PJSIP_INV_STATE_CONFIRMED ||
        info.state == PJSIP_INV_STATE_DISCONNECTED) {
        connectDuration = info.connect_duration.sec;
    }

    return @{
        @"id": @(self.id),
        @"callId": [PjSipUtil toString:&info.call_id],
        @"accountId": @(info.acc_id),
        
        @"localContact": [PjSipUtil toString:&info.local_contact],
        @"localUri": [PjSipUtil toString:&info.local_info],
        @"remoteContact": [PjSipUtil toString:&info.remote_contact],
        @"remoteUri": [PjSipUtil toString:&info.remote_info],
        @"state": [PjSipUtil callStateToString:info.state],
        @"stateText": [PjSipUtil toString:&info.state_text],
        @"connectDuration": @(connectDuration),
        @"totalDuration": @(info.total_duration.sec),
        
        @"lastStatusCode": [PjSipUtil callStatusToString:info.last_status],
        @"lastReason": [PjSipUtil toString:&info.last_status_text],
        
        @"held": @(self.isHeld),
        @"muted": @(self.isMuted),
        @"speaker": @(isSpeaker),
        
        @"remoteOfferer": @(info.rem_offerer),
        @"remoteAudioCount": @(info.rem_aud_cnt),
        @"remoteVideoCount": @(info.rem_vid_cnt),
        
        @"audioCount": @(info.setting.aud_cnt),
        @"videoCount": @(info.setting.vid_cnt)
    };
}


@end
