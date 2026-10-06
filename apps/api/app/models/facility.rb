class Facility < ApplicationRecord
  belongs_to :sandbox
  has_many :courts, dependent: :destroy

  def zone
    ActiveSupport::TimeZone[time_zone]
  end

  def opening_window(date)
    [ local_instant(date, opens_minute), local_instant(date, closes_minute) ]
  end

  def local_date_of(instant)
    instant.in_time_zone(zone).to_date
  end

  private

  def local_instant(date, minute_of_day)
    day = date + (minute_of_day / 1440)
    minute = minute_of_day % 1440
    zone.local(day.year, day.month, day.day, minute / 60, minute % 60)
  end
end
