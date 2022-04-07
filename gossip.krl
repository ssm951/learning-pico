ruleset gossip {
    meta {
        use module io.picolabs.wrangler alias wrangler
        use module io.picolabs.subscription alias subs
        shares origin, messages, state, rx_map, temperatures, getSchedule
    }

    global {
        origin = function() {
            ent:origin
        }
        messages = function() {
            ent:state{[ent:origin, "messages"]}
        }
        state = function() {
            ent:state
        }
        rx_map = function() {
            ent:rx_peers
        }
        temperatures = function() {
            ent:state.keys().map(function(id) {
                {}.put(id, getReceivedMessages(id).mapMessageToTemperature())
            })
        }
        getSchedule = function() {
            schedule:list
        }
        isProcessing = function() {
            ent:process
        }

        mapMessageToTemperature = function(self) {
            self.map(function(msg) {
                {
                    "temperature": msg{"Temperature"},
                    "timestamp": msg{"Timestamp"}
                }
            })
        }
        getReceivedMessages = function(id) {
            ent:state{[id, "messages"]}.keys().sort("numeric")
                        .filter(function(x) {x <= ent:state{[ent:origin, "seen", id]}})
                        .map(function(x) {
                            ent:state{[id, "messages", x]}
                        })
        }
        createMessage = function(origin, seq, temperature, timestamp) {
            {
                "MessageID": origin + ":" + seq,
                "SensorID": origin,
                "Temperature": temperature,
                "Timestamp": timestamp,
           }
        }
        sendRumor = defaction(tx, message) {
            event:send({ 
                "eci": tx, 
                "domain": "gossip", "type": "rumor",
                "attrs": message
            })
        }
        sendSeen = defaction(tx) {
            event:send({ 
                "eci": tx, 
                "domain": "gossip", "type": "seen",
                "attrs": {"seen": ent:state{[ent:origin, "seen"]}}
            })
        }
    }

    rule init {
        select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid
        pre {
            origin = random:uuid()
        }
        always {
            ent:origin := origin
            ent:state := {}.put(origin, {"seen": {}, "messages": {}})
            // {
            //     "peerId": {
            //         "Tx": "id",
            //         "seen": {
            //             "origin": 0
            //         }
            //     "messages": {
            //         "seq" : {message}
            //       }
            //     }
            // }
            ent:rx_peers := {}
            ent:process := true 

            schedule gossip event "heartbeat"
                repeat << */10 * * * * * >>  attributes { } setting(id);
            ent:schedule_id := id
        }
    }

    rule new_peer {
        select when gossip new_peer
            wellKnown_eci   re#(.+)#
            setting(wellKnown_eci)
        event:send({"eci": wellKnown_eci,
            "domain":"wrangler", "name":"subscription",
            "attrs": {
                "wellKnown_Tx": subs:wellKnown_Rx(){"id"},
                "Rx_role":"node", "Tx_role":"node",
                "name": ent:origin, "channel_type":"subscription"
            }
        })
        fired {
            
        }
    }
    
    rule auto_accept_peer {
        select when wrangler inbound_pending_subscription_added
        pre {
          my_role = event:attrs{"Rx_role"}
          their_role = event:attrs{"Tx_role"}
          their_origin = event:attrs{"name"}
        }
        if my_role=="node" && their_role=="node" then noop()
        fired {
            raise wrangler event "pending_subscription_approval"
                attributes event:attrs
            
        } else {
          raise wrangler event "inbound_rejection"
            attributes event:attrs
        }
    }
    rule confirm_added_peer {
        select when wrangler subscription_added
        foreach subs:established() setting (subscription)
        pre {
            my_role = subscription{"Rx_role"}
            their_role = subscription{"Tx_role"}
            their_Rx = subscription{"Tx"}.klog("their_Rx")
            their_Tx = subscription{"Rx"}.klog("their_Tx")
        }
        if my_role=="node" && their_role=="node" then 
        event:send({ 
            "eci": their_Rx, 
            "domain": "gossip", "type": "established",
            "attrs": {
                "Tx": their_Tx,
                "Rx": their_Rx,
                "origin": ent:origin
            }
        })
    }

    rule established {
        select when gossip established
            Tx re#(.+)#
            Rx re#(.+)#
            origin re#(.+)#
            setting(Tx, Rx, origin)
        if ent:state{origin}.isnull() then noop()
        fired {
            ent:state{origin} := {
                "Tx": Tx,
                "seen": {},
                "messages": {}
            }
            ent:rx_peers{Rx} := origin
        }
    }

    rule new_message {
        select when wovyn new_temperature_reading
        pre {
            temperature = event:attrs{"temperature"} || ""
            timestamp = time:now()
            seq = ent:state{[ent:origin, "seen", ent:origin]}.defaultsTo(-1) + 1
        }
        if not temperature.isnull() then noop()
        fired {
            raise gossip event "rumor"
                attributes createMessage(ent:origin, seq, temperature, timestamp)
        }
    }

    rule gossip_heartbeat {
        select when gossip heartbeat
        pre {
            rand = random:integer(1)
        }
        if ent:process then noop()
        fired {
            raise gossip event "send_rumor"
                attributes {} if rand == 0
            raise gossip event "send_seen"
                attributes {} if rand == 1
        }
    }

    rule send_rumor {
        select when gossip send_rumor
        pre {
            // Obtain peers who need a message
            peer_keys = ent:state.filter(function(v, key) {key != ent:origin})  // Don't select self
                .filter(function(peer, key) {
                    peer{"seen"}.klog("Seen for peer").length() == 0 ||                       // If peer has no seen
                    // If peer missing a seen from state
                    ent:state{[ent:origin, "seen"]}                 // There is a seen in state that this peer is missing
                        .filter(function(self_seq, node_id) {
                            key != node_id &&                            // Filter out the node we are looking at
                            (
                                not node_id >< peer{"seen"}.keys() ||   // The node ID in state's seen is not in peer's seen
                                self_seq > peer{["seen", node_id]}      // The state's seen sequence for node is hhigher than the peer's
                            )    
                        }).length() > 0
                }).keys()
            _ = peer_keys.length().klog("Number of peers that needs a message")
            selected_index = random:integer(peer_keys.length() - 1)
            selected_id = peer_keys.slice(selected_index, selected_index).head().klog("Selected peer")
            selected_Tx = ent:state{[selected_id, "Tx"]}

            // Select a message to send
            candidate_messages = ent:state{[ent:origin, "seen"]}
                .filter(function(self_seq, node_id) {
                    not selected_id.isnull() &&
                    (   not node_id >< ent:state{[selected_id, "seen"]}.keys() ||   // The node ID in state's seen is not in peer's seen
                        self_seq > ent:state{[selected_id, "seen", node_id]}        // The state's seen sequence for node is hhigher than the peer's
                    )      
                }).map(function(seq, node_id) {
                    ent:state{[node_id, "messages", 
                                ent:state{[selected_id, "seen", node_id]}.defaultsTo(0)]}
                })
            candidate_index = random:integer(candidate_messages.length() - 1)
            selected_message = candidate_messages{candidate_messages.keys().slice(candidate_index, candidate_index).head()}.klog("Selected message")
        }
        if not selected_id.isnull() then 
        sendRumor(selected_Tx, selected_message)
        always {

        }
    }

    rule send_seen {
        select when gossip send_seen
        foreach subs:established() setting (node)
        pre {
        }
        if node{"Tx_role"} == "node" then
            sendSeen(node{"Tx"}.klog("Sending Seen to"))
        always {
        }
    }

    rule handle_rumor {
        select when gossip rumor
            MessageID re#(.+)#
            SensorID re#(.+)#
            Temperature re#(.+)#
            Timestamp re#(.+)#
            setting(messageId,sensorId,temperature,timestamp)
        pre {
            seq = messageId.split(re#:#).tail().head().klog("Parsed Sequence number").as("Number")
            seenSeq = ent:state{[ent:origin, "seen", sensorId]}.defaultsTo(-1).klog("Existing seen")
        }
        if ent:process && (seenSeq < seq) then noop()
        fired {
            ent:state{sensorId} := {"seen": {}, "messages": {}} 
                if ent:state{sensorId}.isnull()

            ent:state{[sensorId, "messages"]} := ent:state{[sensorId, "messages"]}.put(seq, event:attrs)
            ent:state{[ent:origin, "seen", sensorId]} := seq 
                if seenSeq + 1 == seq
        }
    }

    rule update_peer_seen {
        select when gossip seen 
        pre {
            peer_seen = event:attrs{"seen"}
            peer_id = ent:rx_peers{event:eci}
        }
        if ent:process then noop()
        fired{
            ent:state{[peer_id, "seen"]} := peer_seen
        }
    }
    rule handle_seen {
        select when gossip seen 
        foreach ent:state{[ent:origin, "seen"]} setting(seq, id)
        pre {
            peer_seen = event:attrs{"seen"}
            peer_seq = event:attrs{["seen", id.klog("Checking Origin")]}.defaultsTo(-1)
            peer_id = ent:rx_peers{event:eci.klog("ECI")}
            tx = ent:state{[peer_id, "Tx"]}

        }
        if ent:process && peer_seq < seq then 
        sendRumor(tx.klog("Sending rumor to channel"), ent:state{[id, "messages", peer_seq + 1]}.klog("Sending message as rumor"))
    }

    rule process {
        select when gossip process
            status re#(on|off)#
        setting (status)
        always {
            ent:process := true if status == "on"
            ent:process := false if status == "off"
        }
    }

    rule new_period {
        select when gossip period
            period re#([0-9]+)#
            setting(period, unit)
        
        schedule:remove(ent:schedule_id)
        always {
            schedule gossip event "heartbeat"
                repeat << */#{period} * * * * * >>  attributes { } setting(id)
            
            ent:schedule_id := id
        }
    }
    rule delete_peer {
        select when gossip delete_origin
            origin re#(.+)#
            setting (origin)
        pre {
            Tx = ent:state{[origin, "Tx"]}
        }
        always {
            clear ent:state{origin}
            raise wrangler event "subscription_cancellation"
                attributes {"Tx": Tx} 
                if not Tx.isnull()
        }
    }
}