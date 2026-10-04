require_relative "nhl_api"
require_relative "contract_scraper"
require_relative "advanced_stats"
require_relative "trade_asset"
require_relative "player_value"

print "Enter player: "

name = gets.chomp

puts
puts "Searching for #{name}..."
puts

result = NHLApi.search_player(name)

if result.nil?
  puts "Player not found."
  exit
end

puts "Player found!"
puts "NHL ID: #{result["playerId"]}"
puts

# =================================
# NHL DATA
# =================================

puts "Fetching NHL data..."
puts

player = NHLApi.build_player(result["playerId"])


# =================================
# ADVANCED STATISTICS
# =================================

puts "Fetching advanced statistics..."
puts

advanced_stats = AdvancedStatsLoader.load_player(player.name)

if advanced_stats.nil?
  puts "Advanced statistics not found."
else
  puts "Advanced statistics loaded."
end


# =================================
# CONTRACT
# =================================

puts
puts "Fetching contract data..."
puts

slug = player.name.downcase
                  .gsub(/[^a-z0-9\s-]/, "")
                  .strip
                  .gsub(/\s+/, "-")

contract = ContractScraper.fetch_player(slug)


# =================================
# TRADE ASSET
# =================================

asset = TradeAsset.new(
  player: player,
  contract: contract,
  advanced_stats: advanced_stats
)


# =================================
# TRADE VALUE
# =================================

player_value = PlayerValue.new(asset)

puts
puts "TRADE VALUE"
puts "---------------------------------"
puts "Awards:       #{player_value.award_score.round(1)} / 100"
puts "Performance:  #{player_value.performance_score.round(1)} / 100"
puts "Future:       #{player_value.future_score.round(1)} / 100"
puts "Contract:     #{player_value.contract_score.round(1)} / 100"
puts "Reliability:  #{player_value.reliability_score.round(1)} / 100"

puts
puts "Trade Value:  #{player_value.score} / 100"