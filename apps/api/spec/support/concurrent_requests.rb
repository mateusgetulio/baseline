module ConcurrentRequests
  Result = Struct.new(:status, :body) do
    def json = JSON.parse(body)
  end

  def self.run(requests)
    gate = Concurrent::CountDownLatch.new(1)
    ready = Concurrent::CountDownLatch.new(requests.size)
    threads = requests.map do |request|
      Thread.new do
        env = Rack::MockRequest.env_for(request[:path], method: request[:method], input: request[:body].to_json,
                                        "CONTENT_TYPE" => "application/json")
        request[:headers].each { |name, value| env["HTTP_#{name.upcase.tr('-', '_')}"] = value }
        ready.count_down
        gate.wait
        status, _headers, body = Rails.application.call(env)
        chunks = +""
        body.each { |chunk| chunks << chunk }
        body.close if body.respond_to?(:close)
        Result.new(status, chunks)
      end
    end
    ready.wait
    gate.count_down
    threads.map(&:value)
  end
end
