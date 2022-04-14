ruleset wovyn_base {
    meta {
        use module sensor_profile alias profile
        use module io.picolabs.wrangler alias wrangler
        use module io.picolabs.subscription alias subs
    }

    rule init {
        select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid
        pre {
            tags = ["sensor"]
            eventPolicy = {"allow": [{"domain": "*", "name": "*"}], "deny": []}
            queryPolicy = {"allow": [{"rid": "*", "name": "*"}], "deny": []}
            wellKnown_eci = subs:wellKnown_Rx(){"id"}
        }
        every {
            wrangler:createChannel(tags,eventPolicy,queryPolicy) setting(channel)
            event:send(
                { "eci": wrangler:parent_eci(), 
                  "domain": "sensor", "type": "init_complete",
                  "attrs": event:attrs.put("channel", channel{"id"})
                                        .put("wellKnown_eci", wellKnown_eci)
                }
            )
        }
        always {
            
        }
    }

    rule auto_accept {
        select when wrangler inbound_pending_subscription_added
        pre {
          my_role = event:attr("Rx_role")
          their_role = event:attr("Tx_role")
        }
        if my_role=="sensor" && their_role=="management" then noop()
        fired {
          raise wrangler event "pending_subscription_approval"
            attributes event:attrs
          ent:subscriptionTx := event:attr("Tx")
        } else {
        //   raise wrangler event "inbound_rejection"
        //     attributes event:attrs
        }
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
        if (temperature > profile:temperature_threshold().klog("temp threshold")) then noop()
        fired {
            raise wovyn event "threshold_violation" 
                attributes event:attrs;
        } else {
            raise wovyn event "no_violation"
                attributes event:attrs;
        }
    }

    rule threshold_notification {
        select when wovyn threshold_violation
        pre {
            tx = subs:established().klog().head(){"Tx"}.klog()
            temperature = event:attrs{"temperature"} || ""
            message = "Temperature is over " + profile:temperature_threshold() + " degrees! It is " + temperature + " degrees."
        }
            event:send({"eci":tx,
                "domain":"sensor", "name":"threshold_violation",
                "attrs":{
                    "wellKnown_Tx":subs:wellKnown_Rx(){"id"},
                    "message": message
                }
        })
        always {

        }
    }
}