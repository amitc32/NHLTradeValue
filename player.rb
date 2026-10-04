require "date"

class Player
  attr_reader :id, :name, :team, :position, :birth_date

  # Career statistics
  attr_reader :games, :goals, :assists, :points, :shots

  # Current season
  attr_reader :season_games, :season_goals, :season_assists
  attr_reader :season_points, :season_shots

  # Playoffs
  attr_reader :playoff_games, :playoff_goals, :playoff_assists
  attr_reader :playoff_points, :playoff_shots

  # Draft
  attr_reader :draft_year, :draft_round, :draft_pick, :draft_team

  # Awards
  attr_reader :awards

  # Advanced statistics
  attr_reader :advanced_stats

  def initialize(
    id:,
    name:,
    team:,
    position:,
    birth_date:,

    games:,
    goals:,
    assists:,
    points:,
    shots:,

    season_games:,
    season_goals:,
    season_assists:,
    season_points:,
    season_shots:,

    playoff_games:,
    playoff_goals:,
    playoff_assists:,
    playoff_points:,
    playoff_shots:,

    draft_year:,
    draft_round:,
    draft_pick:,
    draft_team:,

    awards:,

    advanced_stats: nil
  )
    @id = id
    @name = name
    @team = team
    @position = position
    @birth_date = birth_date

    @games = games
    @goals = goals
    @assists = assists
    @points = points
    @shots = shots

    @season_games = season_games
    @season_goals = season_goals
    @season_assists = season_assists
    @season_points = season_points
    @season_shots = season_shots

    @playoff_games = playoff_games
    @playoff_goals = playoff_goals
    @playoff_assists = playoff_assists
    @playoff_points = playoff_points
    @playoff_shots = playoff_shots

    @draft_year = draft_year
    @draft_round = draft_round
    @draft_pick = draft_pick
    @draft_team = draft_team

    @awards = awards

    @advanced_stats = advanced_stats
  end

  def age
    return nil if birth_date.nil?

    birth = Date.parse(birth_date)
    today = Date.today

    age = today.year - birth.year

    if today < Date.new(today.year, birth.month, birth.day)
      age -= 1
    end

    age
  end

  def formatted_awards
    return [] if awards.nil?

    awards.map do |award|
      trophy = award.dig("trophy", "default")
      seasons = award["seasons"] || []

      {
        name: trophy,
        seasons: seasons.map do |season|
          season_id = season["seasonId"].to_s

          if season_id.length == 8
            "#{season_id[0..3]}-#{season_id[6..7]}"
          else
            season_id
          end
        end
      }
    end
  end
end