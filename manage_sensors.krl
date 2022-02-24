ruleset manage_sensors {
    meta {
        use module io.picolabs.wrangler alias wrangler
        shares showChildren, getSensors, getSensorChannels, getSensorTemperatures
    }

    global {
        showChildren = function() {
            wrangler:children()
        }
        getSensors = function() {
            ent:sensors
        }
        getSensorChannels = function() {
            ent:sensor_channels
        }
        getSensorTemperatures = function() {
            ent:sensors.map(function(v,k) {
                    wrangler:picoQuery(ent:sensors{k},"temperature_store","temperatures",{})
                }
            )
        }
        child_rulesets = [
            {
                "name": "com.twilio.sdk", 
                "url": "file:///workspaces/cs462/rulesets/com/twilio/sdk.krl",
            },
            {
                "name": "twilio_sms", 
                "url": "file:///workspaces/cs462/rulesets/twilio_sms.krl", 
                "config": {
                    "sid": meta:rulesetConfig{"sid"}, 
                    "auth_token": meta:rulesetConfig{"auth_token"}
                }
            },
            {
                "name": "temperature_store", 
                "url": "file:///workspaces/cs462/rulesets/temperature_store.krl",
            },
            {
                "name": "sensor_profile", 
                "url": "file:///workspaces/cs462/rulesets/sensor_profile.krl",
            },
            {
                "name": "wovyn_base", 
                "url": "file:///workspaces/cs462/rulesets/wovyn_base.krl",
            },
            {
                "name": "io.picolabs.wovyn.emitter", 
                "url": "https://github.com/windley/temperature-network/raw/main/io.picolabs.wovyn.emitter.krl"},
        ]
    }

    rule init {
        select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid
        always {
            ent:sensors := {}
            ent:sensor_channels := {}
            ent:default_sms_number := "+16265816580"
            ent:default_threshold := 80.0
        }
    }

    rule new_sensor {
        select when sensor new_sensor
        pre {
            name = event:attrs{"name"}
            exists = ent:sensors >< name
          }
        if exists then
            send_directive("sensor_ready", {"name": name, "eci": ent:sensors{name}})
        notfired {
            raise wrangler event "new_child_request"
                attributes { "name": name, "backgroundColor": "#ff69b4" }
        }
    }

    rule new_child {
        select when wrangler new_child_created
            foreach child_rulesets setting (child_ruleset,i)
        pre {
            name = event:attrs{"name"}
            eci = event:attrs{"eci"}.klog("Child Sensor ECI")
        }
        event:send(
            { "eci": eci, 
              "domain": "wrangler", "type": "install_ruleset_request",
              "attrs": {
                "url": child_ruleset.get("url"),
                "config": child_ruleset.get("config"),
                "name": name,
                "eci": eci
              }
            }
        )
        always {
            
        }
    }

    rule sensor_ready {
        select when sensor init_complete
        pre{
            name = event:attrs{"name"}
            eci = event:attrs{"eci"}
            channel = event:attrs{"channel"}
        }
        event:send(
            { "eci": eci, 
              "domain": "sensor", "type": "profile_updated",
              "attrs": {
                "name": name,
                "sms_number": ent:default_sms_number,
                "threshold": ent:default_threshold
              }
            }
        )
        always{
            ent:sensors{name} := eci
            ent:sensor_channels{name} := channel
        }
    }

    rule sensor_update {
        select when sensor update_complete
        pre {
            new_name = event:attrs{"new_name"}
            old_name = event:attrs{"old_name"}
            exists = ent:sensors >< event:attrs{"new_name"}
            eci = ent:sensors{old_name}
            channel = ent:sensor_channels{new_name}
        } //TODO Not handling errors if new name already exists. I think this is out of scope of the project anyways
        if event:attrs{"new_name"} && not exists then
            noop()
        fired {
            clear ent:sensors{old_name}
            clear ent:sensor_channels{old_name} 
            ent:sensors{new_name} := eci
            ent:sensor_channels{new_name} := channel 
        }
    }

    rule delete_sensor {
        select when sensor unneeded_sensor
        pre {
            name = event:attrs{"name"}
            eci = ent:sensors{name}
        }
        if eci then
            send_directive("deleting_sensor", {"name": name, "eci":eci})
        fired {
            raise wrangler event "child_deletion_request"
                attributes {"eci": eci};
            clear ent:sensors{name}
            clear ent:sensor_channels{name}
        }
    }
}