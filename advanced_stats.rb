require "csv"

class AdvancedStats
  attr_reader :games
  attr_reader :toi_seconds
  attr_reader :corsi_pct
  attr_reader :xgoals_pct
  attr_reader :ixg
  attr_reader :goals
  attr_reader :assists
  attr_reader :points
  attr_reader :shots
  attr_reader :hits
  attr_reader :takeaways
  attr_reader :giveaways
  attr_reader :penalty_minutes

  def initialize(row)
    @games = row["games_played"].to_i
    @toi_seconds = row["icetime"].to_f

    @corsi_pct = row["onIce_corsiPercentage"].to_f
    @xgoals_pct = row["onIce_xGoalsPercentage"].to_f

    @ixg = row["I_F_xGoals"].to_f
    @goals = row["I_F_goals"].to_i

    primary_assists = row["I_F_primaryAssists"].to_i
    secondary_assists = row["I_F_secondaryAssists"].to_i
    @assists = primary_assists + secondary_assists

    @points = row["I_F_points"].to_i
    @shots = row["I_F_shotsOnGoal"].to_i

    @hits = row["I_F_hits"].to_i
    @takeaways = row["I_F_takeaways"].to_i
    @giveaways = row["I_F_giveaways"].to_i

    @penalty_minutes = row["I_F_penalityMinutes"].to_f
  end

  def toi_minutes
    @toi_seconds / 60.0
  end

  def toi_per_game
    return 0 if @games == 0

    toi_minutes / @games
  end

  def points_per_60
    return 0 if @toi_seconds == 0

    @points / @toi_seconds * 3600
  end

  def goals_per_60
    return 0 if @toi_seconds == 0

    @goals / @toi_seconds * 3600
  end

  def shots_per_60
    return 0 if @toi_seconds == 0

    @shots / @toi_seconds * 3600
  end
end


class AdvancedStatsLoader
  FILE_PATH = "data/2025_2026.csv"

  def self.load_player(player_name)
    CSV.foreach(FILE_PATH, headers: true) do |row|
      next unless row["name"]&.downcase == player_name.downcase
      next unless row["situation"] == "all"

      return AdvancedStats.new(row)
    end

    nil
  end
end


class HistoricalStatsLoader
  DATA_DIRECTORY = "data"
  CURRENT_SEASON = 2025

  # --------------------------------------------------------------------------
  # DATA LOADING
  # --------------------------------------------------------------------------

  def self.load_all
    rows = []

    Dir.glob("#{DATA_DIRECTORY}/*.csv").sort.each do |file|
      CSV.foreach(file, headers: true) do |row|
        next unless row["situation"] == "all"
        next if row["name"].nil?
        next if row["position"].nil?

        rows << row
      end
    end

    rows
  end

  # Loads all rows, including 5v5 and PK rows.
  #
  # This is intentionally separate from load_all because the normal historical
  # population is still based on "all" rows.
  def self.load_all_situations
    rows = []

    Dir.glob("#{DATA_DIRECTORY}/*.csv").sort.each do |file|
      CSV.foreach(file, headers: true) do |row|
        next if row["name"].nil?
        next if row["position"].nil?
        next if row["situation"].nil?

        rows << row
      end
    end

    rows
  end

  # --------------------------------------------------------------------------
  # POSITION PROFILES
  # --------------------------------------------------------------------------

  def self.position_profile(position)
    case position
    when "D"
      {
        offensive_weight: 0.335,
        defensive_weight: 0.615,
        toi_weight: 0.05
      }

    when "C"
      {
        offensive_weight: 0.725,
        defensive_weight: 0.225,
        toi_weight: 0.05
      }

    when "L", "R"
      {
        offensive_weight: 0.745,
        defensive_weight: 0.205,
        toi_weight: 0.05
      }

    else
      nil
    end
  end

  # --------------------------------------------------------------------------
  # OFFENSE
  # --------------------------------------------------------------------------

  def self.offensive_stats
    [
      :points_per_60,
      :goals_per_60,
      :primary_assists_per_60,
      :shots_per_60
    ]
  end

  # These are the defensive possession metrics used by the 5v5 model.
  def self.possession_defensive_stats
    [
      :xgoals_percentage_5v5,
      :fenwick_percentage_5v5,
      :corsi_percentage_5v5
    ]
  end

  # Kept for compatibility with existing main.rb diagnostics.
  def self.position_performance_score(rows, player_name)
  player = player_row(rows, player_name)

  return nil if player.nil?

  position = player["position"]
  profile = position_profile(position)

  return nil if profile.nil?

  offensive_percentiles =
    offensive_stats.filter_map do |stat|
      player_percentile(rows, player_name, stat)
    end

  return nil if offensive_percentiles.empty?

  defensive_score =
    defensive_score(
      load_all_situations,
      player_name
    )

  return nil if defensive_score.nil?

  toi_percentile =
    player_percentile(
      rows,
      player_name,
      :toi_per_game
    )

  return nil if toi_percentile.nil?

  offensive_base_score =
    offensive_percentiles.sum / offensive_percentiles.length

  offensive_specialist_bonus =
    offensive_specialist_adjustment(
      offensive_percentiles,
      profile[:offensive_weight]
    )

  offensive_score =
    (
      offensive_base_score +
      offensive_specialist_bonus
    ).clamp(0, 100)

  (
    offensive_score * profile[:offensive_weight] +
    defensive_score * profile[:defensive_weight] +
    toi_percentile * profile[:toi_weight]
  ).clamp(0, 100)
  end
  # --------------------------------------------------------------------------
  # DEFENSIVE ARCHITECTURE
  #
  # 50% Possession Defense
  # 40% Shutdown Defense
  # 10% Penalty Killing
  #
  # Possession:
  #   xGF% 45%
  #   Fenwick% 25%
  #   Corsi% 30%
  #
  # Shutdown:
  #   5v5 xGA/60       35%
  #   5v5 relative xGA 20%
  #   D-zone workload  15%
  #   Takeaways/60     10%
  #   Blocks/60        10%
  #   D-zone GA/60     10%
  #
  # PK:
  #   PK xGA/60        60%
  #   PK GA/60         25%
  #   PK workload      15%
  #
  # Workload is deliberately a contextual component rather than being treated
  # as direct evidence of defensive quality.
  # --------------------------------------------------------------------------

  def self.defensive_score(rows, player_name)
  possession = possession_defense_score(rows, player_name)
  shutdown = shutdown_defense_score(rows, player_name)
  pk = penalty_killing_score(rows, player_name)

  return nil if possession.nil? || shutdown.nil? || pk.nil?

  base_score =
    possession * 0.50 +
    shutdown * 0.40 +
    pk * 0.10

  defensive_percentiles =
    possession_defensive_stats.filter_map do |stat|
      player_percentile(rows, player_name, stat)
    end

  specialist_adjustment =
    specialist_adjustment(defensive_percentiles)

  (
    base_score + specialist_adjustment
  ).clamp(0, 100)
end

  def self.specialist_adjustment(percentiles)
  values = percentiles.compact
  return 0.0 if values.length < 3

  elite_count = values.count { |value| value >= 85 }
  strong_count = values.count { |value| value >= 75 }
  mediocre_count = values.count { |value| value >= 50 && value < 60 }
  weak_count = values.count { |value| value < 50 }

  bonus = 0.0
  penalty = 0.0

  # Reward a genuine cluster of elite/strong results.
  bonus += [elite_count - 1, 0].max * 4.0
  bonus += [strong_count - 2, 0].max * 3.0

  # Penalize a broad pattern of mediocre results.
  penalty += [mediocre_count - 1, 0].max * 1.0

  # Slightly stronger penalty when multiple metrics are actually weak.
  penalty += [weak_count - 1, 0].max * 2.0

  (bonus - penalty).clamp(-15.0, 15.0)
end


  def self.possession_defense_score(rows, player_name)
    metrics = possession_defensive_stats.filter_map do |stat|
      player_percentile(rows, player_name, stat)
    end

    return nil if metrics.empty?

    weights = [0.45, 0.25, 0.30]

    weighted_average(metrics, weights)
  end

  def self.shutdown_defense_score(rows, player_name)
  metrics = [
    [
      player_percentile(
        rows,
        player_name,
        :xgoals_against_per_60_5v5,
        invert: true
      ),
      0.35
    ],
    [
      player_percentile(
        rows,
        player_name,
        :xgoals_against_relative_5v5,
        invert: true
      ),
      0.20
    ],
    [
      defensive_zone_workload_score(rows, player_name),
      0.15
    ],
    [
      player_percentile(
        rows,
        player_name,
        :takeaways_per_60_5v5
      ),
      0.10
    ],
    [
      player_percentile(
        rows,
        player_name,
        :blocked_shots_per_60_5v5
      ),
      0.10
    ],
    [
      player_percentile(
        rows,
        player_name,
        :dzone_giveaways_per_60_5v5,
        invert: true
      ),
      0.10
    ]
  ]

  valid_metrics = metrics.filter { |value, _weight| !value.nil? }

  return nil if valid_metrics.empty?

  values = valid_metrics.map(&:first)
  weights = valid_metrics.map(&:last)

  base_score = weighted_average(values, weights)

  specialist_bonus =
    specialist_adjustment(values)

  (
    base_score + specialist_bonus
  ).clamp(0, 100)
end


  def self.penalty_killing_score(rows, player_name)
    player = current_situation_row(
      rows,
      player_name,
      "4on5"
    )

    return 50 if player.nil?

    position = player["position"]

    population =
      rows.select do |row|
        row["season"].to_i == CURRENT_SEASON &&
          row["situation"] == "4on5" &&
          row["position"] == position &&
          meaningful_sample?(row)
      end

    return 50 if population.empty?

    xga_percentile =
      percentile_for_row(
        player,
        population,
        :xgoals_against_per_60_4on5,
        invert: true
      )

    goals_against_percentile =
      percentile_for_row(
        player,
        population,
        :goals_against_per_60_4on5,
        invert: true
      )

    workload_percentile =
      percentile_for_row(
        player,
        population,
        :toi_per_game_4on5
      )

    values = [
      xga_percentile,
      goals_against_percentile,
      workload_percentile
    ]

    return 50 if values.any?(&:nil?)

    (
      xga_percentile * 0.60 +
      goals_against_percentile * 0.25 +
      workload_percentile * 0.15
    ).clamp(0, 100)
  end

  # --------------------------------------------------------------------------
  # DEFENSIVE-ZONE WORKLOAD
  # --------------------------------------------------------------------------

  def self.defensive_zone_workload_score(rows, player_name)
    player = current_situation_row(
      rows,
      player_name,
      "5on5"
    )

    return nil if player.nil?

    position = player["position"]

    population =
      rows.select do |row|
        row["season"].to_i == CURRENT_SEASON &&
          row["situation"] == "5on5" &&
          row["position"] == position &&
          meaningful_sample?(row)
      end

    return nil if population.empty?

    percentile_for_row(
      player,
      population,
      :defensive_zone_start_percentage
    )
  end

  # --------------------------------------------------------------------------
  # CURRENT-SEASON SITUATION ROWS
  # --------------------------------------------------------------------------

  def self.current_situation_row(rows, player_name, situation)
    rows.find do |row|
      row["name"]&.strip&.downcase == player_name.strip.downcase &&
        row["season"].to_i == CURRENT_SEASON &&
        row["situation"] == situation
    end
  end

  def self.stat_value(row, stat)
    icetime = row["icetime"].to_f

    case stat
    when :points_per_60
      return 0 if icetime <= 0
      row["I_F_points"].to_f / icetime * 3600

    when :goals_per_60
      return 0 if icetime <= 0
      row["I_F_goals"].to_f / icetime * 3600

    when :primary_assists_per_60
      return 0 if icetime <= 0
      row["I_F_primaryAssists"].to_f / icetime * 3600

    when :shots_per_60
      return 0 if icetime <= 0
      row["I_F_shotsOnGoal"].to_f / icetime * 3600

    when :xgoals_percentage
      row["onIce_xGoalsPercentage"].to_f

    when :corsi_percentage
      row["onIce_corsiPercentage"].to_f

    when :fenwick_percentage
      row["onIce_fenwickPercentage"].to_f

    when :toi_per_game
      games = row["games_played"].to_f
      return 0 if games <= 0

      icetime / 60.0 / games

    when :xgoals_percentage_5v5
      row["onIce_xGoalsPercentage"].to_f

    when :corsi_percentage_5v5
      row["onIce_corsiPercentage"].to_f

    when :fenwick_percentage_5v5
      row["onIce_fenwickPercentage"].to_f

    when :xgoals_against_per_60_5v5
      xga_per_60(row)

    when :xgoals_against_relative_5v5
      relative_xga_per_60(row)

    when :takeaways_per_60_5v5
      per_60(row["I_F_takeaways"], icetime)

    when :blocked_shots_per_60_5v5
      per_60(row["shotsBlockedByPlayer"], icetime)

    when :dzone_giveaways_per_60_5v5
      per_60(row["I_F_dZoneGiveaways"], icetime)

    when :defensive_zone_start_percentage
      defensive_zone_start_percentage(row)

    when :xgoals_against_per_60_4on5
      xga_per_60(row)

    when :goals_against_per_60_4on5
      goals_against_per_60(row)

    when :toi_per_game_4on5
      games = row["games_played"].to_f
      return 0 if games <= 0

      icetime / 60.0 / games

    else
      raise ArgumentError, "Unknown statistic: #{stat}"
    end
  end

  # --------------------------------------------------------------------------
  # PERCENTILES
  # --------------------------------------------------------------------------

  def self.percentile(value, population)
    return nil if population.empty?

    sorted = population.sort

    below =
      sorted.count do |number|
        number < value
      end

    equal =
      sorted.count do |number|
        number == value
      end

    ((below + equal * 0.5).to_f / sorted.length) * 100
  end

  def self.player_percentile(
    rows,
    player_name,
    stat,
    invert: false
  )
    player = player_row(rows, player_name)

    return nil if player.nil?

    position = player["position"]

    # Possession and shutdown metrics must use the player's 5v5 row.
    if situation_stat?(stat)
      situation =
        situation_for_stat(stat)

      player =
        current_situation_row(
          rows,
          player_name,
          situation
        )

      return nil if player.nil?

      population =
        rows.select do |row|
          row["season"].to_i == CURRENT_SEASON &&
            row["situation"] == situation &&
            row["position"] == position &&
            meaningful_sample?(row)
        end

      return nil if population.empty?

      return percentile_for_row(
        player,
        population,
        stat,
        invert: invert
      )
    end

    player_value =
      stat_value(player, stat)

    population =
      rows.filter_map do |row|
        next unless row["position"] == position
        next unless row["season"].to_i == CURRENT_SEASON
        next unless meaningful_sample?(row)

        stat_value(row, stat)
      end

    return nil if population.empty?

    result = percentile(player_value, population)

    invert ? 100.0 - result : result
  end

 def self.offensive_specialist_adjustment(
  percentiles,
  offensive_weight
)
  values = percentiles.compact
  return 0.0 if values.length < 3

  elite_count =
    values.count { |value| value >= 90 }

  strong_count =
    values.count { |value| value >= 75 }

  mediocre_count =
    values.count { |value| value >= 50 && value < 60 }

  weak_count =
    values.count { |value| value < 50 }

  bonus = 0.0
  penalty = 0.0

  # Reward multiple elite offensive categories.
  bonus +=
    [elite_count - 1, 0].max * 4.0

  # Reward broad high-end offensive performance.
  bonus +=
    [strong_count - 2, 0].max * 2.0

  # Penalize broad offensive weakness.
  penalty +=
    [mediocre_count - 1, 0].max * 1.0

  penalty +=
    [weak_count - 1, 0].max * 2.0

  raw_adjustment =
    bonus - penalty

  # Offensive specialization matters more for positions
  # where offense has a smaller base weight.
  #
  # Defensemen have a 30.5% offensive weight, so they receive
  # the full adjustment. Forwards receive a smaller adjustment
  # because offense already dominates their score.
  position_multiplier =
    (1.0 - offensive_weight) / (1.0 - 0.305)

  adjusted =
    raw_adjustment * position_multiplier

  adjusted.clamp(-10.0, 10.0)
end

  def self.percentile_for_row(
    player,
    population,
    stat,
    invert: false
  )
    player_value = stat_value(player, stat)

    values =
      population.filter_map do |row|
        next unless meaningful_sample?(row)

        stat_value(row, stat)
      end

    return nil if values.empty?

    result = percentile(
      player_value,
      values
    )

    invert ? 100.0 - result : result
  end

  # --------------------------------------------------------------------------
  # PLAYER LOOKUP
  # --------------------------------------------------------------------------

  def self.player_row(rows, player_name)
    rows.find do |row|
      row["name"]&.strip&.downcase ==
        player_name.strip.downcase &&
        row["season"].to_i == CURRENT_SEASON
    end
  end

  # --------------------------------------------------------------------------
  # HELPERS
  # --------------------------------------------------------------------------

  def self.weighted_average(values, weights)
    return nil if values.empty?

    total_weight =
      weights.first(values.length).sum

    return nil if total_weight <= 0

    values
      .first(weights.length)
      .zip(weights)
      .sum { |value, weight| value * weight } /
      total_weight
  end

  def self.situation_stat?(stat)
    [
      :xgoals_percentage_5v5,
      :fenwick_percentage_5v5,
      :corsi_percentage_5v5,
      :xgoals_against_per_60_5v5,
      :xgoals_against_relative_5v5,
      :takeaways_per_60_5v5,
      :blocked_shots_per_60_5v5,
      :dzone_giveaways_per_60_5v5,
      :defensive_zone_start_percentage
    ].include?(stat)
  end

  def self.situation_for_stat(stat)
    case stat
    when :xgoals_percentage_5v5,
         :fenwick_percentage_5v5,
         :corsi_percentage_5v5,
         :xgoals_against_per_60_5v5,
         :xgoals_against_relative_5v5,
         :takeaways_per_60_5v5,
         :blocked_shots_per_60_5v5,
         :dzone_giveaways_per_60_5v5,
         :defensive_zone_start_percentage
      "5on5"
    else
      "all"
    end
  end

  def self.meaningful_sample?(row)
    games = row["games_played"].to_f
    icetime = row["icetime"].to_f

    games >= 20 &&
      icetime >= 300 * 60
  end

  def self.per_60(value, icetime)
    return 0 if icetime <= 0

    value.to_f / icetime * 3600
  end

  def self.xga_per_60(row)
    icetime = row["icetime"].to_f

    return 0 if icetime <= 0

    row["OnIce_A_xGoals"].to_f / icetime * 3600
  end

  def self.goals_against_per_60(row)
    icetime = row["icetime"].to_f

    return 0 if icetime <= 0

    row["OnIce_A_goals"].to_f / icetime * 3600
  end

  def self.relative_xga_per_60(row)
    icetime = row["icetime"].to_f
    bench_time = row["timeOnBench"].to_f

    return 0 if icetime <= 0
    return 0 if bench_time <= 0

    on_ice_xga =
      row["OnIce_A_xGoals"].to_f /
      icetime *
      3600

    off_ice_xga =
      row["OffIce_A_xGoals"].to_f /
      bench_time *
      3600

    on_ice_xga - off_ice_xga
  end

  def self.defensive_zone_start_percentage(row)
    d_zone =
      row["I_F_dZoneShiftStarts"].to_f

    o_zone =
      row["I_F_oZoneShiftStarts"].to_f

    neutral =
      row["I_F_neutralZoneShiftStarts"].to_f

    total =
      d_zone + o_zone + neutral

    return 0 if total <= 0

    d_zone / total
  end

  # Exposed for the diagnostic output in main.rb.
end