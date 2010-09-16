# LeadTune API Ruby Gem
#
# http://github.com/leadtune/leadtune-ruby
# Eric Wollesen (mailto:devs@leadtune.com)
# Copyright 2010 LeadTune LLC

dir = File.dirname(__FILE__)
$LOAD_PATH.unshift dir unless $LOAD_PATH.include?(dir)

require "yaml"
require "json"
require "curb"
require "uri"
require File.dirname(__FILE__) + "/../object_extensions"

require "prospect/validations"
require "prospect/response"


module Leadtune

  # Simplify the process of submitting prospects to LeadTune for duplicate
  # checking and appraisal.
  # 
  # For details about the LeadTune Seller API, see:
  # http://leadtune.com/api/seller
  #
  #  require "rubygems"
  #  require "leadtune"
  #
  #  prospect = Leadtune::Prospect.new do |p|
  #    p.event = "offers_prepared"                           # required
  #    p.organization = "LOL"                                # required
  #    p.email = "test@example.com"                          # required
  #    p.target_buyers = ["TB-LOL", "AcmeU",]                # required
  #    p.username = "admin@loleads.com"                      # required
  #    p.password = "secret"                                 # required
  #    ... include other factors here, see #factors or http://leadtune.com/factors for details
  #  end
  #  response = prospect.post
  #
  # <em>Or alternately</em>
  #
  #  prospect = Leadtune::Prospect.new({
  #    :event => "offers_prepared",
  #    :organization => "LOL",
  #    ... and so on
  #  })
  #
  # == Authentication
  #
  # Authentication credentials can be specified in several methods, as
  # detailed below:
  #
  # === Configuration File
  #
  # The configuration file can be specified when calling #new.  If no file is
  # specified, the gem will also look for +leadtune.yml+ in the current
  # directory.
  #
  # ==== Format
  # 
  # The configuration file is a YAML file, an example of which is:
  #  username: me@mycorp.com
  #  password: my_secret
  #  organization: MYC
  #--
  #  host: http://localhost:8080
  #++
  #
  # === Environment Variables
  # 
  # Your username, password, and organization can be specified in the
  # +LEADTUNE_USERNAME+, +LEADTUNE_PASSWORD+, and +LEADTUNE_ORGANIZATION+
  # environment variables. <em>These values take precedence over values read
  # from a configuration file.</em>
  #
  # === Instance Methods
  #
  # You can also set your username, password, and organization by calling the
  # Leadtune::Prospect object's <tt>\#username</tt>, <tt>\#password</tt>, and
  # <tt>\#organization</tt> methods. <em>These values take precedence over
  # values read from environment variables, or a configuration file.</em>
  #
  # == Dynamic Factor Access
  #
  # Getter and setter methods are dynamically defined for each possible factor
  # that can be specified.  To see a list of dynically defined factors, one
  # can call the #factors method.
  #
  # == Automatic Environment Determination
  #
  # At initialization, the Prospect class will attempt to determine your
  # application's current environment.  If a production environment is
  # detected, the Prospect will post prospects to LeadTune's production host.
  # Otherwise prospects will be posted to LeadTune's sandbox host.  The
  # environment can be overriden via the APP_ENV environment variable, which
  # takes precedence over all other methods.
  #
  #--
  #
  # The host used by the Prospect object can be manually overriden via the
  # LEADTUNE_HOST environment variable, the +host+ configuration file value,
  # or the #leadtune_host method as well.

  class Prospect
    include Validations

    class HttpError < RuntimeError ; end

    attr_accessor :decision, :username, :password, :timeout #:nodoc:

    # Initialize a new Leadtune::Prospect object.  
    #
    # [+config_file+] An optional filename or a file-like object, see
    #                 Authentication above.
    def initialize(*args, &block)
      @factors = {}
      @decision = nil
      @config = {}

      determine_environment
      load_factors
      load_options(args.extract_options!)
      load_config_file(args.first)
      load_authentication
      load_timeout

      block.call(self) if block_given?
    end

    # Post this lead to the LeadTune Appraiser service.
    # 
    # Returns a Response object.
    def post
      throw_post_error unless run_validations!

      curl = build_curl_easy_object
      curl.http("POST")

      Response.new(curl.body_str)
    end

    # Return an array of the factors which can be specified.
    #
    # Each LeadTune recognized factor's name will be returned in this array.
    # Additionally, each factor is available via getter and setter methods of
    # the same name on the Response object, e.g. if a call to #factors
    # includes a factor named +browser_family+, then the Prospect object will
    # have methods named <tt>#browser_family</tt> and
    # <tt>#browser_family=</tt>.
    #
    # See http://leadtune.com/factors for a detailed list of factors and their
    # accepted values.

    def factors
      @@factors
    end

    # Override the normal host
    def leadtune_host=(host) #:nodoc:
      @leadtune_host = host
    end

    # Assign an array of organization codes for the prospects target buyers.
    def target_buyers=(target_buyers)
      unless target_buyers.is_a?(Array)
        raise ArgumentError.new("target_buyers must be an Array")
      end

      @decision = {"target_buyers" => target_buyers}
    end

    # Return an array of organization codes for the prospects target buyers.
    def target_buyers
      @decision ||= {}
      @decision["target_buyers"] ||= []
    end


    private 

    def throw_post_error #:nodoc:
      raise RuntimeError.new(errors.full_messages.inspect) 
    end

    def headers #:nodoc:
      {"Content-Type" => "application/json",
       "Accept" => "application/json",}
    end

    def self.load_factors(file=default_factors_file) #:nodoc:
      factors = YAML::load(file)
      factors.sort {|x,y| x["code"] <=> y["code"]}.each do |factor|
        @@factors << factor["code"]

        next if instance_methods.include?(factor["code"]) 

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

    def load_options(options) #:nodoc:
      raise RuntimeError.new("must load factors first") unless @@factors_loaded
      options.each_pair do |key, value|
        if respond_to?("#{key}=")
          self.send("#{key}=", value)
        end
      end
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
        if File.exist?("leadtune.yml")
          @config_file = File.open("leadtune.yml")
        end
      end
    end

    def determine_environment #:nodoc:
      if production_detected?
        @environment = :production
      else
        @environment = :sandbox
      end
    end

    def production_detected? #:nodoc:
      if ENV.include?("APP_ENV")
        "production" == ENV["APP_ENV"]
      else
        defined?(Rails) && Rails.env.production? ||
          "production" == ENV["RACK_ENV"] ||
          "production" == ENV["RAILS_ENV"] ||
          defined?(RAILS_ENV) && "production" == RAILS_ENV
      end
    end

    def production? #:nodoc:
      :production == @environment
    end

    def load_authentication #:nodoc:
      self.username = ENV["LEADTUNE_USERNAME"] || @config["username"]
      self.password = ENV["LEADTUNE_PASSWORD"] || @config["password"]
      self.organization = ENV["LEADTUNE_ORGANIZATION"] || @config["organization"]
    end

    def load_timeout #:nodoc:
      self.timeout = ENV["LEADTUNE_TIMEOUT"] || 
        @config["timeout"] || 
        DEFAULT_TIMEOUT
      self.timeout ? self.timeout = self.timeout.to_i : nil
    end

    def load_factors #:nodoc:
      self.class.load_factors unless @@factors_loaded
      @@factors_loaded = true
    end

    def leadtune_host #:nodoc:
      @leadtune_host || 
        ENV["LEADTUNE_HOST"] || 
        @config["host"] || 
        LEADTUNE_HOSTS[@environment]
    end

    def build_curl_easy_object #:nodoc:
      Curl::Easy.new do |curl|
        curl.url = URI.join(leadtune_host, "/prospects").to_s
        curl.userpwd = "#{username}:#{password}"
        curl.timeout = timeout 
        curl.headers = headers
        curl.post_body = @factors.merge(:decision => @decision).to_json
        curl.on_failure do |curl, code|
          raise HttpError.new(curl.response_code)
        end
      end
    end

    LEADTUNE_HOST_SANDBOX = "https://sandbox-appraiser.leadtune.com".freeze
    LEADTUNE_HOST_PRODUCTION = "https://appraiser.leadtune.com".freeze

    LEADTUNE_HOSTS = {
      :production => LEADTUNE_HOST_PRODUCTION,
      :sandbox => LEADTUNE_HOST_SANDBOX,
    }

    DEFAULT_TIMEOUT = 5

    @@factors_loaded = false
    @@factors = []

    # stolen from ActiveSupport
    def extract_options!
      last.is_a?(::Hash) ? pop : {}
    end

  end
end