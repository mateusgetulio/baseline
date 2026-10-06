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

        restore(sandbox.facilities.order(:id).to_a, Seed::FACILITIES) do |facility, attrs|
          facility ||= sandbox.facilities.build
          facility.update!(attrs.except(:courts))
          restore(facility.courts.order(:id).to_a, attrs[:courts]) do |court, court_attrs|
            (court || facility.courts.build).update!(court_attrs)
          end
        end
        restore(sandbox.customers.order(:id).to_a, Seed::CUSTOMERS) do |customer, attrs|
          (customer || sandbox.customers.build).update!(attrs)
        end
      end
    end

    def restore(rows, seeds)
      seeds.each_with_index { |attrs, index| yield rows[index], attrs }
      extra = rows.drop(seeds.size)
      extra.each { |row| row.courts.delete_all if row.respond_to?(:courts) }
      extra.each(&:delete)
    end
  end
end
