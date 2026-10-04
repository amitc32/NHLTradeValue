require "date"

class TradeAsset
  attr_reader :player
  attr_reader :contract
  attr_reader :advanced_stats

  def initialize(player:, contract:, advanced_stats:)
    @player = player
    @contract = contract
    @advanced_stats = advanced_stats
  end

  # =================================
  # PLAYER
  # =================================

  def name
    player.name
  end

  def age
    player.age
  end

  def position
    player.position
  end

  def team
    player.team
  end

  # =================================
  # CURRENT SEASON
  # =================================

  def current_games
    return advanced_stats.games if advanced_stats

    player.season_games
  end

  def cap_hit
    return nil if contract.nil?

    contract[:cap_hit]
  end

  def aav
    return nil if contract.nil?

    contract[:aav]
  end

  def contract_start
    return nil if contract.nil?

    contract[:contract_start]
  end

  def contract_end
    return nil if contract.nil?

    contract[:contract_end]
  end

  def contract_years_remaining
    return nil if contract_end.nil?

    current_year = Date.today.year
    start_year = contract_start.to_i
    end_year = contract_end.to_i

    first_remaining_season = [current_year, start_year].max

    return 0 if end_year < first_remaining_season

    end_year - first_remaining_season + 1
  end
end