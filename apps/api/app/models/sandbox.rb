class Sandbox < ApplicationRecord
  has_many :facilities, dependent: :destroy
  has_many :customers, dependent: :destroy
  has_many :api_keys, dependent: :destroy
end
