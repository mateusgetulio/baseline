class RequestLog < ApplicationRecord
  belongs_to :sandbox
  belongs_to :api_key
end
