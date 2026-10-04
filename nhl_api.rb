require "net/http"
require "json"
require "uri"
require_relative "player"

class NHLApi

  def self.get_json(url)
    uri = URI(url)

    response = Net::HTTP.get_response(uri)

    unless response.is_a?(Net::HTTPSuccess)
      raise "NHL API request failed: #{response.code}"
    end

    JSON.parse(response.body)
  end

  def self.search_player(name)
    encoded_name = URI.encode_www_form_component(name)

    url = "https://search.d3.nhle.com/api/v1/search/player?culture=en-us&q=#{encoded_name}"

    results = get_json(url)

    exact_match = results.find do |player|
      player["name"].downcase == name.downcase
    end

    exact_match
  end

  def self.get_player(player_id)
    url = "https://api-web.nhle.com/v1/player/#{player_id}/landing"

    get_json(url)
  end

  def self.build_player(player_id)
    data = get_player(player_id)

    career = data.dig("careerTotals", "regularSeason") || {}
    playoffs = data.dig("careerTotals", "playoffs") || {}
    current_season = data.dig("featuredStats", "regularSeason") || {}

    draft = data["draftDetails"] || {}
    awards = data["awards"] || []

    Player.new(

      # =========================
      # BASIC INFORMATION
      # =========================

      id: data["playerId"],

      name: "#{data.dig("firstName", "default")} #{data.dig("lastName", "default")}",

      team: data["currentTeamAbbrev"] || "N/A",

      position: data["position"] || "N/A",

      birth_date: data["birthDate"],


      # =========================
      # CAREER STATISTICS
      # =========================

      games: career["gamesPlayed"] || 0,

      goals: career["goals"] || 0,

      assists: career["assists"] || 0,

      points: career["points"] || 0,

      shots: career["shots"],


      # =========================
      # CURRENT SEASON
      # =========================

      season_games: current_season["gamesPlayed"] || 0,

      season_goals: current_season["goals"] || 0,

      season_assists: current_season["assists"] || 0,

      season_points: current_season["points"] || 0,

      season_shots: current_season["shots"],


      # =========================
      # PLAYOFFS
      # =========================

      playoff_games: playoffs["gamesPlayed"] || 0,

      playoff_goals: playoffs["goals"] || 0,

      playoff_assists: playoffs["assists"] || 0,

      playoff_points: playoffs["points"] || 0,

      playoff_shots: playoffs["shots"],


      # =========================
      # DRAFT
      # =========================

      draft_year: draft["year"],

      draft_round: draft["round"],

      draft_pick: draft["pickInRound"],

      draft_team: draft["teamAbbrev"],


      # =========================
      # AWARDS
      # =========================

      awards: awards
    )
  end
end