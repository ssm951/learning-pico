ruleset com.twilio.sdk {
    meta {
        configure using
          sid = ""
          authToken = ""
        provides sendSMS, messages
      }
    global {
        base_url = "https://api.twilio.com/2010-04-01/Accounts"
        from_number = "+19362435422"
        sendSMS = defaction(to, message) {
            http:post(<<#{base_url}/#{sid}/Messages.json>>,
                auth = {"username": sid, "password": authToken}, 
                form = {"From": from_number, "To": <<#{to}>>, "Body": <<#{message}>>}) setting(response)
            return response
          }
        messages = function(pagesize = 50, nextpageuri = null, sending_num = null, receiving_num = null) {
          response = http:get(<<#{base_url}/#{sid}/Messages.json>>, 
                              auth = {"username": sid, "password": authToken},
                              qs={"pagesize": pagesize, "nextpageuri": nextpageuri, "to": sending_num, "from": receiving_num })
          response{"content"}.decode()
        }
    }
}