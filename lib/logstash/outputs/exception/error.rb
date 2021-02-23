class Error
  class BadResponseCodeError < StandardError
    attr_reader :url, :response_code, :response_body

    def initialize(response_code, url)
      @response_code = response_code
      @url = url
    end

    def message
      "Got response code '#{@response_code}' contacting NewRelic at URL '#{@url}'"
    end
  end
end
