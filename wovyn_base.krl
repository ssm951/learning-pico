ruleset wovyn_base {
    meta {
        use module sensor_profile alias profile
    }

    rule process_heartbeat {
        select when wovyn heartbeat
        pre {
            genericThing = event:attrs{"genericThing"} || ""
        }
        if genericThing then send_directive("wovyn", {"heartbeat": "Hello World" })
        fired {
            log info "Heartbeat logged"
            log info "genericThing:"+genericThing
            temperature = genericThing{"data"}{"temperature"}[0].klog()

            raise wovyn event "new_temperature_reading" attributes {
                "temperature": temperature{"temperatureF"},
                "timestamp": event:time
            }
        } else {
            log info "Event skipped "
            log info "genericThing:"+genericThing
        }
    }
    
    rule find_high_temps {
        select when wovyn new_temperature_reading
        pre {
            temperature = event:attrs{"temperature"} || ""
        }
        fired {
            raise wovyn event "threshold_violation" 
                attributes event:attrs
                if (temperature > profile:temperature_threshold().klog("temp threshold"));
        } 
    }

    rule threshold_notification {
        select when wovyn threshold_violation
        pre {
            temperature = event:attrs{"temperature"} || ""
        }
        fired {
            raise sms event "new_message" attributes {
                "to": profile:notify_number(),
                "message": "Temperature is over " + profile:temperature_threshold() + " degrees! It is " + temperature + " degrees."
            }
        } 
    }
}