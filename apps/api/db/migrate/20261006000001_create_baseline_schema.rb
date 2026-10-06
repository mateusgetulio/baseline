class CreateBaselineSchema < ActiveRecord::Migration[8.1]
  def change
    create_table :sandboxes do |t|
      t.string :name, null: false
      t.timestamps
    end

    create_table :facilities do |t|
      t.references :sandbox, null: false, foreign_key: true
      t.string :name, null: false
      t.string :time_zone, null: false
      t.integer :opens_minute, null: false
      t.integer :closes_minute, null: false
      t.timestamps
    end

    create_table :courts do |t|
      t.references :facility, null: false, foreign_key: true
      t.string :name, null: false
      t.string :sport, null: false
      t.integer :hourly_rate_cents, null: false
      t.string :currency, limit: 3, null: false
      t.timestamps
    end

    create_table :customers do |t|
      t.references :sandbox, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email, null: false
      t.timestamps
    end

    create_table :api_keys do |t|
      t.references :sandbox, null: false, foreign_key: true
      t.string :lookup, null: false, index: { unique: true }
      t.string :secret_digest, null: false
      t.json :permissions, null: false
      t.datetime :revoked_at
      t.timestamps
    end

    create_table :holds do |t|
      t.references :sandbox, null: false, foreign_key: true
      t.references :court, null: false, foreign_key: true, index: false
      t.references :customer, null: false, foreign_key: true
      t.references :api_key, null: false, foreign_key: true, index: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.datetime :expires_at, null: false
      t.string :status, null: false
      t.timestamps
      t.index [ :court_id, :status, :starts_at ]
      t.index [ :api_key_id, :status ]
    end

    create_table :bookings do |t|
      t.references :sandbox, null: false, foreign_key: true
      t.references :court, null: false, foreign_key: true, index: false
      t.references :customer, null: false, foreign_key: true
      t.references :hold, null: false, foreign_key: true, index: { unique: true }
      t.references :api_key, null: false, foreign_key: true
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.integer :price_cents, null: false
      t.string :currency, limit: 3, null: false
      t.string :status, null: false
      t.timestamps
      t.index [ :court_id, :status, :starts_at ]
    end

    create_table :preview_tokens do |t|
      t.references :hold, null: false, foreign_key: true
      t.references :customer, null: false, foreign_key: true
      t.string :token_digest, null: false, index: { unique: true }
      t.integer :price_cents, null: false
      t.string :currency, limit: 3, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.timestamps
    end

    create_table :idempotency_records do |t|
      t.references :api_key, null: false, foreign_key: true, index: false
      t.string :key, null: false, collation: "utf8mb4_bin"
      t.string :request_method, null: false
      t.string :request_path, null: false
      t.string :body_digest, null: false
      t.string :state, null: false
      t.integer :response_status
      t.text :response_body, size: :medium
      t.timestamps
      t.index [ :api_key_id, :key ], unique: true
    end

    create_table :request_logs do |t|
      t.references :sandbox, null: false, foreign_key: true, index: false
      t.references :api_key, null: false, foreign_key: true
      t.string :http_method, null: false
      t.string :path, null: false, limit: 1024
      t.integer :status, null: false
      t.string :error_code
      t.integer :duration_ms, null: false
      t.boolean :replayed, null: false, default: false
      t.string :client
      t.datetime :created_at, null: false
      t.index [ :sandbox_id, :id ]
    end
  end
end
