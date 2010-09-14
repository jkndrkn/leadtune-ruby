# = LeadTune Lead Seller's API Ruby Gem
#
# http://github.com/leadtune/leadtune-seller <br/>
# Eric Wollesen (mailto:devs@leadtune.com)  <br/>
# Copyright 2010 LeadTune LLC

dir = File.dirname(__FILE__)
$LOAD_PATH.unshift dir unless $LOAD_PATH.include?(dir)

require "ruby-debug"
require "yaml"
require "json"
require "curb-fu"
require "uri"
require File.dirname(__FILE__) + "/../object_extensions"

require "seller/validations"
require "seller/response"

module Leadtune

  # Simplify the process of submitting leads to LeadTune for duplicate
  # checking and appraisal.
  # 
  # For details about the LeadTune Seller API, see:
  # http://leadtune.com/api/seller
  #
  #  require "rubygems"
  #  require "leadtune/seller"
  #
  #  seller = Leadtune::Seller.new do |s|
  #    s.event = "offers_prepared"                           # required
  #    s.organization = "LOL"                                # required
  #    s.email = "test@example.com"                          # required
  #    s.decision = {"target_buyers" => ["TB-LOL", "AcmeU"]} # required
  #    s.username = "admin@loleads.com"                      # required
  #    s.password = "secret"                                 # required
  #    ... include other factors here, see #factors or http://leadtune.com/factors for details
  #  end
  #  response = seller.post
  #
  # == Authentication
  #
  # Authentication credentials can be specified in several methods, as
  # detailed below:
  #
  # === Configuration File
  #
  # The configuration file can be specified when calling #new.  If no file is
  # specified, the gem will also look for +leadtune-seller.yml+ in the current
  # directory.
  #
  # ==== Format
  # 
  # The configuration file is a YAML file, an example of which is:
  #  username: me@mycorp.com
  #  password: my_secret
  #
  # === Environment Variables
  # 
  # Your username and password can be specified in the
  # +LEADTUNE_SELLER_USERNAME+ and +LEADTUNE_SELLER_PASSWORD+ environment
  # variables. <em>These values take precedence over values read from a
  # configuration file.</em>
  #
  # === Instance Methods
  #
  # You can also set your username and password by calling the
  # Leadtune::Seller object's <tt>\#username</tt> and <tt>\#password</tt>
  # methods. <em>These values take precedence over values read from
  # environment variables, or a configuration file.</em>
  #
  # == Dynamic Factor Access
  #
  # Getter and setter methods are dynamically defined for each possible factor
  # that can be specified.  To see a list of dynically defined factors, one
  # can call the #factors method.
  class Seller
    include Validations

    attr_accessor :decision, :username, :password #:nodoc:

    # Initialize a new Leadtune::Seller object.  
    #
    # [+config_file+] An optional filename or a file-like object, see
    #                 Authentication above.
    def initialize(config_file=nil, &block)
      @factors = {}
      @decision = nil
      @config = {}

      determine_environment
      load_config_file(config_file)
      load_authentication
      load_factors

      block.call(self) if block_given?
    end

    # Post this lead to the LeadTune Appraiser service.
    # 
    # Return a Response object.
    def post
      throw_post_error unless run_validations!
      CurbFu::debug = true if :sandbox == @environment
      Response.new(CurbFu.post(post_options, 
                               @factors.merge(:decision => @decision).to_json))
    end

    # Return an array of the factors which can be specified.
    def factors
      @@factors
    end

    # Override the normal URL
    def leadtune_seller_url=(url) #:nodoc:
      @leadtune_seller_url = url
    end


    private 

    def throw_post_error #:nodoc:
      raise RuntimeError.new(errors.full_messages.inspect) 
    end

    def headers #:nodoc:
      {"Content-Type" => "application/json",
       "Accept" => "application/json",}
    end

    def post_options #:nodoc:
      uri = URI::parse(leadtune_url)
      {:protocol => uri.scheme,
       :username => username,
       :password => password,
       :headers => headers,
       :host => uri.host,
       :port => uri.port,
       :path => "/prospects",}
    end

    def self.load_factors(file=default_factors_file) #:nodoc:
      factors = YAML::load(file)
      factors.each do |factor|
        @@factors << factor["code"]

        define_method(factor["code"].to_sym) do
          @factors[factor["code"]]
        end

        define_method(("%s=" % [factor["code"]]).to_sym) do |value|
          @factors[factor["code"]] = value
        end
      end
    end

    def self.default_factors_file #:nodoc:
      File.open("/Users/ewollesen/src/uber/site/db/factors.yml") # FIXME: magic
    end

    def load_config_file(config_file) #:nodoc:
      find_config_file(config_file)

      if @config_file
        @config = YAML::load(@config_file)
      end
    end

    def find_config_file(config_file) #:nodoc:
      case config_file
      when String; @config_file = File.open(config_file)
      when File, StringIO; @config_file = config_file
      when nil
        if File.exist?("leadtune-seller.yml")
          @config_file = File.open("leadtune-seller.yml")
        end
      end
    end

    # TODO: check for other methods to automatically determine environment
    def determine_environment #:nodoc:
      if production_detected?
        @environment = :production
      else
        @environment = :sandbox
      end
    end

    def production_detected? #:nodoc:
      "production" == ENV["RAILS_ENV"] ||
        defined?(RAILS_ENV) && "production" == RAILS_ENV
    end

    def production? #:nodoc:
      :production == @environment
    end

    def load_authentication #:nodoc:
      self.username = ENV["LEADTUNE_SELLER_USERNAME"] || @config["username"]
      self.password = ENV["LEADTUNE_SELLER_PASSWORD"] || @config["password"]
    end

    def load_factors #:nodoc:
      self.class.load_factors unless @@factors_loaded
      @@factors_loaded = true
    end

    def leadtune_url #:nodoc:
      @leadtune_seller_url || 
        ENV["LEADTUNE_SELLER_URL"] || 
        @config["leadtune_seller_url"] || 
        LEADTUNE_URLS[@environment]
    end

    LEADTUNE_URL_SANDBOX = "https://sandbox-appraiser.leadtune.com".freeze
    LEADTUNE_URL_PRODUCTION = "https://appraiser.leadtune.com".freeze

    LEADTUNE_URLS = {
      #:production => LEADTUNE_URL_PRODUCTION,
      :sandbox => LEADTUNE_URL_SANDBOX,
    }

    @@factors_loaded = false
    @@factors = []

  end
end
