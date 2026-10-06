module ReadCommitted
  module_function

  def transaction(&block)
    if ActiveRecord::Base.connection.transaction_open?
      ActiveRecord::Base.transaction(&block)
    else
      ActiveRecord::Base.transaction(isolation: :read_committed, &block)
    end
  end
end
