module Sandboxes
  module Provision
    module_function

    def call(name:, permissions: ApiKey::PERMISSIONS)
      ActiveRecord::Base.transaction do
        sandbox = Sandbox.create!(name: name)
        Seed.call(sandbox)
        key, token = ApiKey.issue!(sandbox: sandbox, permissions: permissions)
        [ sandbox, key, token ]
      end
    end
  end
end
