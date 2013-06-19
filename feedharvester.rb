#!/usr/bin/env ruby

# vim: set ts=2 sw=2 et:

require 'bundler/setup'
require 'twitter'
require 'feedzirra'
require 'yaml'
require 'mongo'
# require 'pinboard' # undercooked
# require 'buffer' # also missing functionality
require 'addressable/uri'
require 'buff'

include Mongo

class FeedHarvester
  def initialize
    @config = YAML.load_file("config.yml")

    if @config["export_to"].include?("twitter")
      Twitter.configure do |c|
        c.consumer_key = ""
        c.consumer_secret = ""
        c.oauth_token = ""
        c.oauth_token_secret = ""
      end
    end

    @db = MongoClient.new.db(@config["db"])
  end

  def update
    file = @config["feed_file"] || "feeds.txt"
    File.open(file) do |f|
      f.each_line { |url| update_feed(url) }
    end
  end

private

  def update_feed(url)
    feed = feed_from_db(url)
    if feed.nil?
      puts("New feed #{url}")
      feed = Feedzirra::Feed.fetch_and_parse(url)
    else
      puts("Updating #{url}")
    end

    fresh_feed = Feedzirra::Feed.update(feed)
    if !fresh_feed.new_entries.empty?
      fresh_feed.new_entries.each do |entry|
#       text = "[#{fresh_feed.title.sanitize}] #{entry.title.sanitize}: #{entry.url}"   #sanitize was broken on UTF-8BIT
#       text = "[#{fresh_feed.title}] #{entry.title}: #{entry.url}"
        text = "#{entry.title}: #{entry.url}"
        puts("  " + text)
        if @config["export_to"].include?("twitter")
          begin
            Twitter.update(text)
            sleep(15)
          rescue
            puts("  error sending twitter data")
          end
        end
# add buffer support
        if @config["export_to"].include?("buffer")
          begin
            client = Buff::Client.new(options['access_token'])
            id = client.profiles[options['profile_index'].to_i].id
            response = client.create_update(body: {text: text, profile_ids: [ id ] } )
	    puts response
          rescue
            puts("  error sending buffer data")
          end
        end
      end
    else
      puts("  no updates")
    end

    feed_to_db(url, fresh_feed)
  end

  def feed_from_db(url)
    coll = @db["feeds"]
    doc = coll.find("url" => url).to_a
    feed = nil
    if !doc.empty?
      feed = YAML.load(doc[0]["data"].to_s)
    end
    feed
  end

  def feed_to_db(url, feed)
    serialized = YAML.dump(feed)
    doc = { "url" => url, "data" => serialized }
    coll = @db["feeds"]
    coll.insert(doc)
  end
end

feeds = FeedHarvester.new
feeds.update
