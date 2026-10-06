module Sandboxes
  module Reset
    module_function

    def call(sandbox)
      ActiveRecord::Base.transaction do
        hold_ids = Hold.where(sandbox_id: sandbox.id).select(:id)
        Booking.where(sandbox_id: sandbox.id).delete_all
        PreviewToken.where(hold_id: hold_ids).delete_all
        Hold.where(sandbox_id: sandbox.id).delete_all
        IdempotencyRecord.where(api_key_id: sandbox.api_keys.select(:id)).delete_all
        Court.where(facility_id: sandbox.facilities.select(:id)).delete_all
        sandbox.facilities.delete_all
        sandbox.customers.delete_all
        Seed.call(sandbox)
      end
    end
  end
end
