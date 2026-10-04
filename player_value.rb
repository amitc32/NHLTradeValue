require "date"
require_relative "advanced_stats"
require_relative "salary_cap"

class PlayerValue
  # --------------------------------------------------
  # MARKET VALUE CURVES
  # --------------------------------------------------

  MARKET_CAP_CURVE = [
    [0, 0.01],
    [40, 0.02],
    [50, 0.04],
    [60, 0.06],
    [70, 0.08],
    [80, 0.10],
    [85, 0.13],
    [90, 0.16],
    [92, 0.18],
    [95, 0.21],
    [97, 0.23],
    [100, 0.26]
  ]

  # --------------------------------------------------
  # AGE CURVE
  # --------------------------------------------------
  #
  # Represents the expected aging effect on established
  # NHL ability.
  #
  # This is separate from Future Value.
  #
  AGE_CURVE = [
    [18, 0.82],
    [19, 0.88],
    [20, 0.98],
    [21, 1.00],
    [22, 1.02],
    [23, 1.03],
    [24, 1.04],
    [25, 1.05],
    [26, 1.04],
    [27, 1.03],
    [28, 1.02],
    [29, 1.00],
    [30, 0.99],
    [31, 0.95],
    [32, 0.92],
    [33, 0.90],
    [34, 0.85],
    [35, 0.83],
    [36, 0.79],
    [37, 0.76],
    [38, 0.70],
    [39, 0.65],
    [40, 0.60],
    [41, 0.53],
    [42, 0.49],
    [43, 0.45],
    [44, 0.40]
  ]

  # --------------------------------------------------
  # DEVELOPMENT POTENTIAL CURVE
  # --------------------------------------------------
  #
  # Represents how much developmental opportunity
  # generally remains at each age.
  #
  # This is NOT a prediction that the player will
  # actually reach 100.
  #
  # It controls how much additional upside the model
  # can assign to Future.
  #
  DEVELOPMENT_CURVE = [
    [18, 100],
    [19, 98],
    [20, 95],
    [21, 91],
    [22, 86],
    [23, 78],
    [24, 68],
    [25, 57],
    [26, 45],
    [27, 32],
    [28, 20],
    [29, 10],
    [30, 4],
    [31, 0],
    [32, 0],
    [33, 0],
    [34, 0],
    [35, 0],
    [36, 0],
    [37, 0],
    [38, 0],
    [39, 0],
    [40, 0],
    [41, 0],
    [42, 0],
    [43, 0],
    [44, 0]
  ]

  # --------------------------------------------------
  # FUTURE VALUE SETTINGS
  # --------------------------------------------------
  #
  # Future is intentionally different from Performance.
  #
  # It answers:
  #
  # "How valuable should this player be expected to be
  # going forward?"
  #
  # Rather than:
  #
  # "How good is this player right now?"
  #
  # Current performance establishes the baseline.
  # Development adds upside.
  # Aging subtracts future value.
  #
  FUTURE_BASELINE_STRENGTH = 0.80
  FUTURE_DEVELOPMENT_STRENGTH = 0.65

  # Maximum additional Future value development can add.
  FUTURE_MAX_DEVELOPMENT_BONUS = 30.0

  # --------------------------------------------------
  # FUTURE HORIZON
  # --------------------------------------------------

  FUTURE_YEARS = 4

  FUTURE_YEAR_WEIGHTS = [
    0.40,
    0.30,
    0.20,
    0.10
  ]

  # --------------------------------------------------
  # INITIALIZATION
  # --------------------------------------------------

  def initialize(asset)
    @asset = asset

    @performance_score = nil
    @future_score = nil
    @contract_score = nil
  end

  # --------------------------------------------------
  # OVERALL SCORE
  # --------------------------------------------------

  def score
    (
      performance_score * 0.40 +
      future_score * 0.32 +
      contract_score * 0.17 +
      award_score * 0.03 +
      reliability_score * 0.08
    ).round(2)
  end

  # --------------------------------------------------
  # CONTRACT PROJECTION
  # --------------------------------------------------
  #
  # Prints the expected value of every remaining contract
  # season using the projected-performance engine.
  #
  def performance_score
    return @performance_score unless @performance_score.nil?

    score =
      historical_performance_score

    @performance_score =
      score.nil? ? 0 : score
  end

  # --------------------------------------------------
  # FUTURE VALUE
  # --------------------------------------------------
  #
  # Future is intentionally separated from Performance.
  #
  # The model uses three concepts:
  #
  # 1. CURRENT ABILITY BASELINE
  #
  #    How valuable is the player already?
  #
  # 2. DEVELOPMENT UPSIDE
  #
  #    How much room does the player have to improve?
  #
  # 3. AGING PENALTY
  #
  #    How much future value should be discounted because
  #    the player is moving beyond their prime?
  #
  # Crucially:
  #
  # Lack of development is NOT a penalty.
  #
  # A 29-year-old superstar does not become a poor Future
  # asset simply because there is little development left.
  #
  def future_score
    return @future_score unless @future_score.nil?

    age =
      @asset.age

    return 50 if age.nil?

    performance =
      performance_score.clamp(0, 100)

    # --------------------------------------------------
    # CURRENT ABILITY BASELINE
    # --------------------------------------------------
    #
    # Compress Performance toward 50.
    #
    # This makes Future meaningfully different from
    # Performance.
    #
    # Examples:
    #
    # Performance 30 -> Baseline 34
    # Performance 70 -> Baseline 66
    # Performance 90 -> Baseline 82
    # Performance 98 -> Baseline 88
    #
    current_baseline =
      future_current_baseline(
        performance
      )

    # --------------------------------------------------
    # DEVELOPMENT UPSIDE
    # --------------------------------------------------
    #
    # Development is an additive bonus.
    #
    # It does NOT replace current ability.
    #
    development =
      development_potential_score(age)

    development_bonus =
      future_development_bonus(
        performance,
        development
      )

    # --------------------------------------------------
    # AGING PENALTY
    # --------------------------------------------------
    #
    # No meaningful penalty through the player's prime.
    #
    # The penalty grows progressively with age.
    #
    aging_penalty =
      future_aging_penalty(age)

    # --------------------------------------------------
    # FOUR-YEAR TRAJECTORY
    # --------------------------------------------------
    #
    # Instead of evaluating only the player's current age,
    # look at the development opportunity remaining over
    # the next four seasons.
    #
    # This is a relatively small modifier so that it does
    # not overwhelm the primary Future calculation.
    #
    trajectory_adjustment =
      future_trajectory_adjustment(
        age,
        performance
      )

    # --------------------------------------------------
    # FINAL FUTURE SCORE
    # --------------------------------------------------

    future =
      current_baseline +
      development_bonus -
      aging_penalty +
      trajectory_adjustment

    @future_score =
      future.clamp(0, 100).round(2)
  end

  # --------------------------------------------------
  # CONTRACT VALUE
  # --------------------------------------------------

  def contract_score
    return @contract_score unless @contract_score.nil?

    aav =
      @asset.aav

    years =
      @asset.contract_years_remaining

    age =
      @asset.age

    if aav.nil? ||
       years.nil? ||
       age.nil? ||
       years <= 0

      @contract_score = 50
      return @contract_score
    end

    salary_efficiency =
      contract_salary_efficiency_score(
        age,
        years
      )

    contract_control =
      contract_control_score(
        years
      )

    performance =
      performance_score.clamp(0, 100)

    # High-performance players receive more emphasis
    # on contract control.
    #
    # Lower-performance players receive more emphasis
    # on whether they are actually being paid efficiently.
    salary_weight =
      0.90 -
      (performance / 100.0) * 0.50

    control_weight =
      1.0 -
      salary_weight

    calculated_score =
      salary_efficiency * salary_weight +
      contract_control * control_weight

    @contract_score =
      calculated_score.round(2)
  end

  # --------------------------------------------------
  # CONTRACT SALARY EFFICIENCY
  # --------------------------------------------------

  def contract_salary_efficiency_score(starting_age, years)
    total_projected =
      0.0

    total_actual =
      0.0

    aav =
      @asset.aav.to_f

    contract_start_year =
      first_contract_season

    current_year =
      Date.today.year

    years.times do |year|

      age =
        starting_age +
        (contract_start_year - current_year) +
        year

      season =
        contract_start_year +
        year

      salary_cap =
        SalaryCap.get(season)

      projected_performance =
        projected_performance_for_age(
          age
        )

      expected_cap_percentage =
        interpolate_market_cap_percentage(
          projected_performance
        )

      actual_cap_percentage =
        aav /
        salary_cap

      total_projected +=
        expected_cap_percentage

      total_actual +=
        actual_cap_percentage
    end

    return 50 if total_projected <= 0

    surplus_ratio =
      (
        total_projected -
        total_actual
      ) /
      total_projected

    if surplus_ratio >= 0

      salary_efficiency =
        50 +
        surplus_ratio * 50

    else

      salary_efficiency =
        50 +
        surplus_ratio * 25

    end

    salary_efficiency.clamp(0, 100)
  end

  def first_contract_season
    current_year =
      Date.today.year

    start_year =
      @asset.contract_start.to_i

    [
      current_year,
      start_year
    ].max
  end

  # --------------------------------------------------
  # CONTRACT CONTROL
  # --------------------------------------------------

  def contract_control_score(years)
    (
      100 *
      (
        1 -
        Math.exp(
          -years.to_f / 2.5
        )
      )
    ).clamp(0, 100)
  end

  # --------------------------------------------------
  # CONTRACT SURPLUS
  # --------------------------------------------------

  def reliability_score
    games =
      @asset.current_games

    return 50 if games.nil?

    normalize(
      games,
      20,
      82
    )
  end

  # --------------------------------------------------
  # AWARDS
  # --------------------------------------------------

  def award_score
    awards =
      @asset.player.formatted_awards

    return 0 if awards.nil? ||
                awards.empty?

    total =
      0.0

    awards.each do |award|

      base_value =
        award_base_value(
          award[:name]
        )

      award[:seasons].each do |season|

        years_ago =
          award_years_ago(
            season
          )

        recency_multiplier =
          award_recency_multiplier(
            years_ago
          )

        total +=
          base_value *
          recency_multiplier
      end
    end

    [
      [total, 0].max,
      100
    ].min
  end

  # ==================================================
  # PRIVATE METHODS
  # ==================================================

  private

  # --------------------------------------------------
  # PERFORMANCE HELPERS
  # --------------------------------------------------

  def historical_performance_score
    rows =
      HistoricalStatsLoader.load_all

    HistoricalStatsLoader.position_performance_score(
      rows,
      @asset.name
    )
  end

  # --------------------------------------------------
  # FUTURE BASELINE
  # --------------------------------------------------
  #
  # Future should recognize that a player who is already
  # excellent is likely to remain valuable, even if they
  # have little developmental upside.
  #
  # However, Future should NOT simply equal Performance.
  #
  # A compression factor of 0.80 is used.
  #
  def future_current_baseline(performance)
    50 +
      (
        performance - 50
      ) *
      FUTURE_BASELINE_STRENGTH
  end

  # --------------------------------------------------
  # FUTURE DEVELOPMENT BONUS
  # --------------------------------------------------
  #
  # Development adds upside rather than acting as a
  # standalone rating.
  #
  # The amount of upside is based on:
  #
  #   1. Remaining room between Performance and 100
  #   2. Age-based development potential
  #
  # This means:
  #
  # Young + already excellent:
  #   large but controlled upside
  #
  # Young + weak current performance:
  #   meaningful upside
  #
  # Prime superstar:
  #   little upside, but also no penalty
  #
  # Older player:
  #   essentially no development bonus
  #
  def future_development_bonus(
    performance,
    development
  )

    remaining_gap =
      (
        100.0 -
        performance
      ).clamp(0, 100)

    bonus =
      remaining_gap *
      (development / 100.0) *
      FUTURE_DEVELOPMENT_STRENGTH

    bonus.clamp(
      0,
      FUTURE_MAX_DEVELOPMENT_BONUS
    )
  end

  # --------------------------------------------------
  # FUTURE AGING PENALTY
  # --------------------------------------------------
  #
  # The aging penalty is intentionally modest around
  # the end of a player's prime and increases sharply
  # through the mid/late 30s.
  #
  # The important distinction is:
  #
  # 29-year-old superstar:
  #   low development
  #   LOW aging penalty
  #
  # 39-year-old superstar:
  #   low development
  #   HIGH aging penalty
  #
  def future_aging_penalty(age)
    case age

    when 18..27
      0.0

    when 28
      0.5

    when 29
      2.0

    when 30
      4.0

    when 31
      6.0

    when 32
      9.0

    when 33
      12.0

    when 34
      16.0

    when 35
      20.0

    when 36
      24.0

    when 37
      28.0

    when 38
      33.0

    when 39
      38.0

    when 40
      43.0

    when 41
      48.0

    when 42
      53.0

    when 43
      57.0

    else
      60.0
    end
  end

  # --------------------------------------------------
  # FUTURE TRAJECTORY ADJUSTMENT
  # --------------------------------------------------
  #
  # Looks at the next four seasons rather than only the
  # player's current age.
  #
  # This is deliberately a small adjustment.
  #
  # The purpose is to distinguish:
  #
  #   20-year-old
  #   24-year-old
  #   29-year-old
  #
  # without allowing the age curve to completely determine
  # Future.
  #
  def future_trajectory_adjustment(
    age,
    performance
  )

    future_ages =
      (1..FUTURE_YEARS).map do |year|
        age + year
      end

    development_values =
      future_ages.map do |future_age|
        development_potential_score(
          future_age
        )
      end

    weighted_development =
      development_values
        .zip(FUTURE_YEAR_WEIGHTS)
        .sum do |value, weight|
          value * weight
        end

    current_development =
      development_potential_score(
        age
      )

    development_change =
      weighted_development -
      current_development

    # Normalize the difference so that it has a small
    # influence on Future.
    #
    # Young players generally have a positive trajectory
    # before development fades.
    #
    # Older players have a negative trajectory.
    #
    adjustment =
      development_change *
      0.04

    # Very low-performance players should not receive an
    # enormous boost merely from being young.
    #
    # Conversely, elite players should be allowed to
    # retain their future value.
    performance_modifier =
      if performance < 40
        0.85
      elsif performance >= 85
        1.05
      else
        1.00
      end

    (
      adjustment *
      performance_modifier
    ).clamp(-5.0, 5.0)
  end

  # --------------------------------------------------
  # DEVELOPMENT POTENTIAL
  # --------------------------------------------------

  def development_potential_score(age)
    interpolate_curve(
      DEVELOPMENT_CURVE,
      age
    )
  end

  # --------------------------------------------------
  # PROJECTED PERFORMANCE
  # --------------------------------------------------
  #
  # Used by the CONTRACT model.
  #
  # This is intentionally separate from Future Score.
  #
  # Future Score asks:
  #
  #   "How attractive is this player's future?"
  #
  # Projected Performance asks:
  #
  #   "What performance should we expect when valuing
  #    each future contract season?"
  #
  def projected_performance_for_age(projected_age)
    performance =
      performance_score

    current_age =
      @asset.age

    return 50 if performance.nil? ||
                  current_age.nil?

    current_factor =
      age_projection_factor(
        current_age
      )

    future_factor =
      age_projection_factor(
        projected_age
      )

    return performance if current_factor <= 0

    # --------------------------------------------------
    # AGING
    # --------------------------------------------------

    aging_projection =
      performance *
      (
        future_factor /
        current_factor
      )

    # --------------------------------------------------
    # DEVELOPMENT
    # --------------------------------------------------
    #
    # Development is based on the player's CURRENT age.
    #
    # It fades as the player moves forward through the
    # projection horizon.
    #
    current_development =
      interpolate_curve(
        DEVELOPMENT_CURVE,
        current_age
      ) / 100.0

    years_forward =
      [
        projected_age - current_age,
        0
      ].max

    development_progress =
      case years_forward
      when 0
        0.0

      when 1
        0.35

      when 2
        0.60

      when 3
        0.80

      else
        1.00
      end

    remaining_gap =
      (
        100.0 -
        aging_projection
      ).clamp(0, 100)

    development_gain =
      remaining_gap *
      current_development *
      development_progress *
      0.35

    projected =
      aging_projection +
      development_gain

    projected.clamp(
      0,
      100
    )
  end

  # --------------------------------------------------
  # AGE PROJECTION
  # --------------------------------------------------

  def age_projection_factor(age)
    interpolate_curve(
      AGE_CURVE,
      age
    )
  end

  # --------------------------------------------------
  # GENERIC CURVE INTERPOLATION
  # --------------------------------------------------

  def interpolate_curve(curve, value)
    return curve.first[1] if value <= curve.first[0]

    return curve.last[1] if value >= curve.last[0]

    curve.each_cons(2) do |lower, upper|

      lower_value,
      lower_score = lower

      upper_value,
      upper_score = upper

      next unless value <= upper_value

      position =
        (
          value - lower_value
        ).to_f /
        (
          upper_value - lower_value
        )

      return(
        lower_score +
        (
          upper_score -
          lower_score
        ) *
        position
      )
    end

    curve.last[1]
  end

  # --------------------------------------------------
  # MARKET CAP INTERPOLATION
  # --------------------------------------------------

  def interpolate_market_cap_percentage(performance)
    interpolate_curve(
      MARKET_CAP_CURVE,
      performance
    )
  end

  # --------------------------------------------------
  # MARKET VALUE INTERPOLATION
  # --------------------------------------------------

  def award_base_value(name)
    case name

    when "Hart Memorial Trophy"
      32

    when "Ted Lindsay Award"
      30

    when "Art Ross Trophy"
      28

    when "James Norris Memorial Trophy"
      28

    when "Vezina Trophy"
      28

    when "Maurice “Rocket” Richard Trophy"
      25

    when "Conn Smythe Trophy"
      22

    when "Selke Trophy"
      18

    when "Calder Memorial Trophy"
      16

    else
      8
    end
  end

  def award_years_ago(season)
    award_year =
      season.to_s[0..3].to_i

    Date.today.year -
      award_year
  end

  def award_recency_multiplier(years_ago)
    case years_ago

    when 0
      1.00

    when 1
      0.90

    when 2
      0.80

    when 3
      0.65

    when 4
      0.50

    when 5
      0.40

    when 6
      0.30

    when 7
      0.20

    when 8
      0.18

    when 9
      0.14

    when 10
      0.10

    else
      0.05
    end
  end

  # --------------------------------------------------
  # GENERAL HELPERS
  # --------------------------------------------------

  def normalize(value, minimum, maximum)
    value =
      value.to_f

    score =
      (
        (value - minimum) /
        (maximum - minimum)
      ) * 100

    [
      [score, 0].max,
      100
    ].min
  end
end