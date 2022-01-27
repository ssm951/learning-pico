ruleset wovyn_base {

    global {
        temperature_threshold = 80.0;
        notify_number = "+16265816580"
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
                if (temperature > temperature_threshold);
        } 
    }

    rule threshold_notification {
        select when wovyn threshold_violation
        pre {
            temperature = event:attrs{"temperature"} || ""
        }
        fired {
            raise sms event "new_message" attributes {
                "to": notify_number,
                "message": "Temperature is over " + temperature_threshold + " degrees! It is " + temperature + " degrees."
            }
        } 
    }
}