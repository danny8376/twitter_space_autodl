require "connect-proxy"
require "http/client"
require "oauth"
require "json"
require "log"

require "./config"

class Twitter
  class RateLimited < Exception
    property reset : Time?
  end

  @guest_token : String?
  @guest_token_time = Time.utc

  def initialize(token, secret, app_key, app_secret, proxy_host = "", proxy_port = 0)
    @client_index = ConnectProxy::HTTPClient.new("twitter.com", tls: true)
    @client_api = ConnectProxy::HTTPClient.new("api.twitter.com", tls: true)
    # disable compression here, twitter sometimes breaks crystal's umcompression...
    @client_api.compress = false
    unless proxy_host.empty?
      proxy = ConnectProxy.new(proxy_host, proxy_port)
      @client_index.set_proxy proxy
      @client_api.set_proxy proxy
    end
    OAuth.authenticate(@client_api, token, secret, app_key, app_secret)

    @username_cache = Hash(String, String).new
  end

  def self.new(twitter : Config::Twitter)
    self.new twitter.user_token, twitter.user_token_secret, twitter.app_key, twitter.app_secret, twitter.proxy_host, twitter.proxy_port
  end

  def guest_token
    if @guest_token.nil?
      res = @client_index.get "/"
      match = /((?<=gt\=)\d{19})/.match res.body
      if match
        @guest_token_time = Time.utc
        @guest_token = match[1]
      else
        guest_token
      end
    else
      if Time.utc - @guest_token_time > 1.hour
        @guest_token = nil
        guest_token
      else
        @guest_token.not_nil!
      end
    end
  end

  def guest_get(path)
    headers = HTTP::Headers{
      "authorization" => "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs=1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA",
      "x-guest-token" => guest_token
    }
    @client_index.get path, headers: headers
  end

  def get_userinfo(id)
    params = URI::Params.encode({
      variables: "{\"userId\":\"#{id}\",\"withSafetyModeUserFields\":false,\"withSuperFollowsUserFields\":false}"
    })
    res = guest_get "/i/api/graphql/I5nvpI91ljifos1Y3Lltyg/UserByRestId?#{params}"
    JSON.parse res.body
  end

  def get_username(id)
    if cache = @username_cache[id]?
      cache.not_nil!
    else
      info = get_userinfo id
      @username_cache[id] = info["data"]["user"]["result"]["legacy"]["screen_name"].as_s
    end
  end

  def get_spaceinfo(id)
    params = URI::Params.encode({
      variables: "{\"id\":\"#{id}\",\"isMetatagsQuery\":false,\"withSuperFollowsUserFields\":false,\"withUserResults\":false,\"withBirdwatchPivots\":false,\"withDownvotePerspective\":false,\"withReactionsMetadata\":false,\"withReactionsPerspective\":false,\"withSuperFollowsTweetFields\":false,\"withReplays\":false,\"withScheduledSpaces\":true}"
    })
    res = guest_get "/i/api/graphql/SZgtzqddpKiybhaMeCD_XQ/AudioSpaceById?#{params}"
    JSON.parse res.body
  end

  def get_playlist_mkey(mkey)
    res = guest_get "/i/api/1.1/live_video_stream/status/#{mkey}"
    JSON.parse(res.body)["source"]["location"].as_s
  end

  def get_playlist(id)
    info = get_spaceinfo id
    mkey = info["data"]["audioSpace"]["metadata"]?.try &.["media_key"]
    get_playlist_mkey mkey
  end

  def fleetline
    headers = HTTP::Headers{
      "user-agent" => "TwitterAndroid/9.22.0-release.0 (29220000-r-0)"
    }
    res = @client_api.get "/fleets/v1/fleetline?exclude_user_data=true", headers: headers
    case res.status_code
    when 200
      Log.debug { "Rate-Limit: #{res.headers["x-rate-limit-remaining"]} of #{res.headers["x-rate-limit-limit"]} remaining, reset at #{Time.unix res.headers["x-rate-limit-reset"].to_i64}" }
      JSON.parse res.body
    when 429
      reset = res.headers["x-rate-limit-reset"]?
      ex = RateLimited.new
      if reset
        ex.reset = Time.unix reset.not_nil!.to_i64
      end
      raise ex
    else
      Log.error { res }
      raise "HTTP Error #{res.status_code}"
    end
  rescue ex : JSON::ParseException
    Log.error { res }
    raise ex
  end
end
