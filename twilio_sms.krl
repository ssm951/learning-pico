ruleset twilio_sms {
    meta {
        use module com.twilio.sdk alias sdk
            with
            sid = meta:rulesetConfig{"sid"}
            authToken = meta:rulesetConfig{"auth_token"}
            shares messages
    }
    global {
        messages = function(pagesize = 50, nextpageuri = null, sending_num = null, receiving_num = null) {
            sdk:messages(pagesize, nextpageuri, sending_num, receiving_num)
        }
    }
    rule send_message {
        select when sms new_message
          to re#(\+1[1-9][0-9]{9})#
          message re#(.*)#
          setting(to, message)
        sdk:sendSMS(to, message) setting(response)
        fired {
            log info "response:"+response{"content"}
            error info "Empty message" if(message like "^$")
            ent:lastResponse := response
            ent:lastTimestamp := time:now()
            raise sms event "sent" attributes event:attrs
        }
    }
}