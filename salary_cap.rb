class SalaryCap
  HISTORICAL_CAP = {
    2017 => 75_000_000,
    2018 => 79_500_000,
    2019 => 81_500_000,
    2020 => 81_500_000,
    2021 => 81_500_000,
    2022 => 81_500_000,
    2023 => 83_500_000,
    2024 => 88_000_000,
    2025 => 95_500_000,
    2026 => 104_000_000
  }

  def self.get(year)
    HISTORICAL_CAP[year] || projected_cap(year)
  end

  def self.projected_cap(year)
    # Temporary projection
    latest_year = HISTORICAL_CAP.keys.max
    latest_cap = HISTORICAL_CAP[latest_year]

    years_forward = year - latest_year

    latest_cap * (1.06 ** years_forward)
  end
end