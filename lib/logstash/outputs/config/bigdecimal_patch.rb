require 'bigdecimal'

class BigDecimal
    # Floating-point numbers that go through the 'json' Logstash filter get automatically converted into BigDecimals.
    # Example of such a filter:
    #
    # filter {
    #   json {
    #     source => "message"
    #   }
    # }
    #
    # The problem is that { "value" => BigDecimal('0.12345') } gets serialized into { "value": "0.12345e0"}. We do
    # want to keep floating point numbers serialized as floating point numbers, even at the expense of loosing a little
    # bit of precision during the conversion. So, in the above example, the correct serialization would be:
    # { "value": 0.12345}
    def to_json(options = nil) #:nodoc:
      if finite?
        self.to_f.to_s
      else
        'null'
      end
    end
  end