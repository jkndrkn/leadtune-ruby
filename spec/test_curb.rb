#!/usr/bin/env ruby

# LeadTune API Ruby Gem
#
# http://github.com/leadtune/leadtune-ruby
# Eric Wollesen (mailto:devs@leadtune.com)
# Copyright 2010 LeadTune LLC

require "rubygems"
require "curb"
require "time"

c = Curl::Easy.new("http://www.google.com/")

c.on_failure do |curl, code|
  puts "failure!"
  puts "code: #{code.inspect}"
  puts "response code: #{curl.response_code}"
  puts "response headers:\n#{curl.header_str}"
end

c.on_success do |curl|
  puts "success!"
end

c.http_post
puts "*" * 20
c.http_get
