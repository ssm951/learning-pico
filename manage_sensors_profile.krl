ruleset manage_sensors_profile {

    global {
        
    }

    rule init {
        select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid
        always {
            ent:sms_number := "+16265816580"
        }
    }

    rule notify_threshold_violation {
        select when sensor threshold_violation
        pre {
            message = event:attrs{"message"} || ""
        }
        fired {
            raise sms event "new_message" attributes {
                "to": ent:sms_number,
                "message": message
            }
        }
    }
}