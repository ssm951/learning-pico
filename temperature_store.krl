ruleset temperature_store {

    meta {
        provides temperatures, threshold_violations, inrange_temperatures
        shares temperatures, threshold_violations, inrange_temperatures
    }

    global {
        temperatures = function() {
            ent:temperature_list
        }

        threshold_violations = function() {
            ent:threshold_violation_list
        }

        inrange_temperatures = function() {
            ent:temperature_list.filter(function(x) {
                ent:threshold_violation_list.filter(function(y) {
                    x{"temperature"} == y{"temperature"} && x{"timestamp"} == y{"timestamp"}
                }).length() == 0
            })
        }
    }

    rule init {
        select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid
        always {
            ent:temperature_list := []
            ent:threshold_violation_list := []
        }
    }

    rule collect_temperatures {
        select when wovyn new_temperature_reading
        pre {
            temperature = event:attrs{"temperature"}.klog("temperature received: ") 
            timestamp =  event:attrs{"timestamp"}.klog("timestamp received: ") 
        }

        always {
            ent:temperature_list := ent:temperature_list.append({"timestamp": timestamp, "temperature": temperature})
        }
    }

    rule collect_threshold_violations {
        select when wovyn threshold_violation
        pre {
            temperature = event:attrs{"temperature"}.klog("temperature received: ") 
            timestamp =  event:attrs{"timestamp"}.klog("timestamp received: ") 
        }
        always {
            // stores the violation temperature and a timestamp in a different entity variable that collects threshold violations.
            ent:threshold_violation_list := ent:threshold_violation_list.append({"timestamp": timestamp, "temperature": temperature})
        }
    }

    rule clear_temperatures {
        select when sensor reading_reset
        always {
            ent:temperature_list := []
            ent:threshold_violation_list := []
        }
    }
}