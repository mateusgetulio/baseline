# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_06_000001) do
  create_table "api_keys", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "sandbox_id", null: false
    t.string "lookup", null: false
    t.string "secret_digest", null: false
    t.json "permissions", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lookup"], name: "index_api_keys_on_lookup", unique: true
    t.index ["sandbox_id"], name: "index_api_keys_on_sandbox_id"
  end

  create_table "bookings", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "sandbox_id", null: false
    t.bigint "court_id", null: false
    t.bigint "customer_id", null: false
    t.bigint "hold_id", null: false
    t.bigint "api_key_id", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.integer "price_cents", null: false
    t.string "currency", limit: 3, null: false
    t.string "status", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key_id"], name: "index_bookings_on_api_key_id"
    t.index ["court_id", "status", "starts_at"], name: "index_bookings_on_court_id_and_status_and_starts_at"
    t.index ["customer_id"], name: "index_bookings_on_customer_id"
    t.index ["hold_id"], name: "index_bookings_on_hold_id", unique: true
    t.index ["sandbox_id"], name: "index_bookings_on_sandbox_id"
  end

  create_table "courts", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "facility_id", null: false
    t.string "name", null: false
    t.string "sport", null: false
    t.integer "hourly_rate_cents", null: false
    t.string "currency", limit: 3, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["facility_id"], name: "index_courts_on_facility_id"
  end

  create_table "customers", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "sandbox_id", null: false
    t.string "name", null: false
    t.string "email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sandbox_id"], name: "index_customers_on_sandbox_id"
  end

  create_table "facilities", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "sandbox_id", null: false
    t.string "name", null: false
    t.string "time_zone", null: false
    t.integer "opens_minute", null: false
    t.integer "closes_minute", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sandbox_id"], name: "index_facilities_on_sandbox_id"
  end

  create_table "holds", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "sandbox_id", null: false
    t.bigint "court_id", null: false
    t.bigint "customer_id", null: false
    t.bigint "api_key_id", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.datetime "expires_at", null: false
    t.string "status", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key_id", "status"], name: "index_holds_on_api_key_id_and_status"
    t.index ["court_id", "status", "starts_at"], name: "index_holds_on_court_id_and_status_and_starts_at"
    t.index ["customer_id"], name: "index_holds_on_customer_id"
    t.index ["sandbox_id"], name: "index_holds_on_sandbox_id"
  end

  create_table "idempotency_records", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "api_key_id", null: false
    t.string "key", null: false, collation: "utf8mb4_bin"
    t.string "request_method", null: false
    t.string "request_path", null: false
    t.string "body_digest", null: false
    t.string "state", null: false
    t.integer "response_status"
    t.text "response_body", size: :medium
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key_id", "key"], name: "index_idempotency_records_on_api_key_id_and_key", unique: true
  end

  create_table "preview_tokens", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "hold_id", null: false
    t.bigint "customer_id", null: false
    t.string "token_digest", null: false
    t.integer "price_cents", null: false
    t.string "currency", limit: 3, null: false
    t.datetime "expires_at", null: false
    t.datetime "used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_preview_tokens_on_customer_id"
    t.index ["hold_id"], name: "index_preview_tokens_on_hold_id"
    t.index ["token_digest"], name: "index_preview_tokens_on_token_digest", unique: true
  end

  create_table "request_logs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "sandbox_id", null: false
    t.bigint "api_key_id", null: false
    t.string "http_method", null: false
    t.string "path", limit: 1024, null: false
    t.integer "status", null: false
    t.string "error_code"
    t.integer "duration_ms", null: false
    t.boolean "replayed", default: false, null: false
    t.string "client"
    t.datetime "created_at", null: false
    t.index ["api_key_id"], name: "index_request_logs_on_api_key_id"
    t.index ["sandbox_id", "id"], name: "index_request_logs_on_sandbox_id_and_id"
  end

  create_table "sandboxes", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "api_keys", "sandboxes"
  add_foreign_key "bookings", "api_keys"
  add_foreign_key "bookings", "courts"
  add_foreign_key "bookings", "customers"
  add_foreign_key "bookings", "holds"
  add_foreign_key "bookings", "sandboxes"
  add_foreign_key "courts", "facilities"
  add_foreign_key "customers", "sandboxes"
  add_foreign_key "facilities", "sandboxes"
  add_foreign_key "holds", "api_keys"
  add_foreign_key "holds", "courts"
  add_foreign_key "holds", "customers"
  add_foreign_key "holds", "sandboxes"
  add_foreign_key "idempotency_records", "api_keys"
  add_foreign_key "preview_tokens", "customers"
  add_foreign_key "preview_tokens", "holds"
  add_foreign_key "request_logs", "api_keys"
  add_foreign_key "request_logs", "sandboxes"
end
