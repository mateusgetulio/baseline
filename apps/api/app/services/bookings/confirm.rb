module Bookings
  class Confirm
    def initialize(api_key:, plaintext_token:)
      @api_key = api_key
      @plaintext_token = plaintext_token
    end

    def call
      if @plaintext_token.blank?
        raise ApiError.new(status: 422, code: "preview_token_missing", title: "preview_token is required",
                           detail: "Call POST /v1/holds/{id}/preview and send its preview_token.")
      end

      ReadCommitted.transaction do
        hold = Hold.lock.find_by(id: issued_token.hold_id)
        Court.lock.find(hold.court_id)
        @now = Time.current
        token = PreviewToken.find(issued_token.id)
        check_token!(token)
        check_hold!(hold)
        check_binding!(hold, token)
        if Booking.confirmed.where(court_id: hold.court_id).overlapping(hold.starts_at, hold.ends_at).exists?
          raise ApiError.conflict("slot_unavailable", "Slot is not available", "The court is already booked for part of this window.")
        end

        token.update!(used_at: @now)
        hold.update!(status: "converted")
        Booking.create!(
          sandbox_id: hold.sandbox_id, court_id: hold.court_id, customer_id: hold.customer_id, hold: hold,
          api_key: @api_key, starts_at: hold.starts_at, ends_at: hold.ends_at,
          price_cents: token.price_cents, currency: token.currency, status: "confirmed"
        )
      end
    end

    private

    def issued_token
      @issued_token ||= begin
        token = PreviewToken.find_by_plaintext(@plaintext_token)
        if token.nil? || token.hold.api_key_id != @api_key.id
          raise ApiError.new(status: 422, code: "preview_token_invalid", title: "preview_token was not issued to this key",
                             detail: "Use a preview_token returned by POST /v1/holds/{id}/preview with this key.")
        end
        token
      end
    end

    def check_token!(token)
      if token.used_at
        raise ApiError.conflict("preview_token_used", "preview_token was already used",
                                "Each preview_token confirms at most one booking.")
      end
      return if token.expires_at > @now

      raise ApiError.new(status: 410, code: "preview_token_expired", title: "preview_token has expired",
                         detail: "Preview tokens last 5 minutes or until the hold expires. Preview the hold again.")
    end

    def check_hold!(hold)
      return if hold.active?(@now)

      raise ApiError.conflict("hold_not_active", "Hold is not active",
                              "Hold #{hold.id} is #{hold.effective_status(@now)} and cannot be booked.")
    end

    def check_binding!(hold, token)
      current_price = hold.court.price_cents_for(hold.starts_at, hold.ends_at)
      return if token.customer_id == hold.customer_id && token.price_cents == current_price &&
                token.currency == hold.court.currency

      raise ApiError.conflict("preview_token_mismatch", "The previewed booking no longer matches",
                              "The hold's customer or price changed since the preview. Preview the hold again.")
    end
  end
end
