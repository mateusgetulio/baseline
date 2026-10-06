module DatabaseTruncation
  KEEP = %w[schema_migrations ar_internal_metadata].freeze

  def self.call
    connection = ActiveRecord::Base.connection
    connection.execute("SET FOREIGN_KEY_CHECKS = 0")
    (connection.tables - KEEP).each { |table| connection.execute("TRUNCATE TABLE #{connection.quote_table_name(table)}") }
  ensure
    connection&.execute("SET FOREIGN_KEY_CHECKS = 1")
  end
end
