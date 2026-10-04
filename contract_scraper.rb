require "net/http"
require "uri"
require "nokogiri"
require "json"

class ContractScraper
  
  def self.fetch_player(slug)
    url = URI("https://capwages.com/players/#{slug}")

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(url)

    request["User-Agent"] =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " \
      "AppleWebKit/537.36 (KHTML, like Gecko) " \
      "Chrome/154.0.0.0 Safari/537.36"

    request["Accept"] =
      "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8"

    request["Accept-Language"] = "en-US,en;q=0.9"
    request["Referer"] = "https://capwages.com/"
    request["Connection"] = "keep-alive"

    response = http.request(request)

    puts "HTTP Status: #{response.code}"
    puts "Content-Type: #{response["content-type"]}"
    puts "Content-Length: #{response.body&.bytesize}"

    unless response.is_a?(Net::HTTPSuccess)
      raise "CapWages returned HTTP #{response.code}"
    end
    doc = Nokogiri::HTML(response.body)

    extract_contract(doc)
  end

  def self.extract_contract(doc)

    json_ld = doc.at_css('script[type="application/ld+json"]')

    if json_ld.nil?
      raise "Could not find JSON-LD data"
    end

    data = JSON.parse(json_ld.text)

    person = data["mainEntity"]

    if person.nil?
      raise "Could not find mainEntity"
    end

    works_for = person["worksFor"]

    if works_for.nil?
      raise "Could not find contract information"
    end

    base_salary = works_for.dig("baseSalary", "value")

    {
      player_name: person["name"],
      nhl_id: find_identifier(person, "NHL"),
      slug: find_identifier(person, "slug"),

      contract_start: works_for["startDate"].to_i,
      contract_end: works_for["endDate"].to_i,

      cap_hit: base_salary.to_i,
      aav: base_salary.to_i,

      team: works_for.dig("worksFor", "name")
    }
  end

  def self.find_identifier(person, property_id)
    identifiers = person["identifier"] || []

    identifier = identifiers.find do |item|
      item["propertyID"] == property_id
    end

    identifier&.dig("value")
  end
end