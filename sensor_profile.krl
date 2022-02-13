ruleset sensor_profile {
    meta {
        provides get_profile, sensor_name, sensor_location, notify_number, temperature_threshold
        shares get_profile, sensor_name, sensor_location, notify_number, temperature_threshold
    }

    global {
        get_profile = function() {
            {
                "name": ent:name,
                "location": ent:location,
                "sms_number": ent:sms_number,
                "threshold": ent:threshold
            }
        }
        sensor_name = function() {
            ent:name
        }
        sensor_location = function() {
            ent:location
        }
        notify_number = function() {
            ent:sms_number
        }
        temperature_threshold = function() {
            ent:threshold
        }
    }

    rule init {
        select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid
        always {
            ent:location := "Default"
            ent:name := "Sensor"
            ent:sms_number := "+16265816580"
            ent:threshold := 80.0
        }
    }

    rule sensor_update {
        select when sensor profile_updated
        pre {
            location = event:attrs{"location"}.klog("location received: ") 
            sensor_name = event:attrs{"name"}.klog("sensor_name received: ") 
            sms_number = event:attrs{"sms_number"}.klog("sms_number received: ") 
            threshold = event:attrs{"threshold"}.klog("threshold received: ") 
        }
        always {
            ent:location := event:attrs{"location"} || ent:location
            ent:name := event:attrs{"name"} || ent:name
            ent:sms_number := event:attrs{"sms_number"} || ent:sms_number
            ent:threshold := event:attrs{"threshold"} || ent:threshold
        }

    }
}