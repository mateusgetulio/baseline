require "json_schemer"

module OpenapiContract
  DOCUMENT_PATH = Rails.root.join("../../docs/openapi.yaml")

  def self.document
    @document ||= YAML.safe_load_file(DOCUMENT_PATH)
  end

  def self.schemer
    @schemer ||= JSONSchemer.openapi(document)
  end

  def self.response_schema(method, path, status, media_type)
    responses = document.dig("paths", path, method.downcase, "responses") ||
                raise("#{method} #{path} is not in openapi.yaml")
    response = responses[status.to_s] || raise("#{method} #{path} does not document status #{status}")
    response = schemer.ref(response["$ref"]).value if response["$ref"]
    schema = response.dig("content", media_type, "schema") ||
             raise("#{method} #{path} #{status} does not document #{media_type}")
    schemer.ref(schema.fetch("$ref"))
  end

  def self.errors_for(method, path, response)
    schema = response_schema(method, path, response.status, response.media_type)
    schema.validate(JSON.parse(response.body)).map { |e| e["error"] }.to_a
  end
end

RSpec::Matchers.define :match_openapi do |method, path|
  match do |response|
    @errors = OpenapiContract.errors_for(method, path, response)
    @errors.empty?
  end

  failure_message do |response|
    "expected #{method} #{path} #{response.status} to match openapi.yaml:\n#{@errors.join("\n")}\n#{response.body}"
  end
end
