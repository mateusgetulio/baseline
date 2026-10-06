if Sandbox.none?
  sandbox, key, token = Sandboxes::Provision.call(name: "Local sandbox")
  puts "Created sandbox #{sandbox.id} with key #{key.id} (#{key.permissions.join(', ')})."
  puts "API key (shown once): #{token}"
end
